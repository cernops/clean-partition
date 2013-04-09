#!/usr/bin/perl -w
#
# This script will try to remove files from $partition according
# the following algorithm:
#
#  1st remove all files of users that do not run any process on the node
#      (~ are not logged in) and that are not in use by any other process
#  2nd remove all files that are not used by any process
#  3rd find out files that have already been removed but are still
#      in use by a process => kill that process
#  4th kill all processes that keep some files open on $partition
#      and remove the file
#
# Script always starts removing the largest files first.
# It collects it's output and mails it to a given e-mail address.
#
# If this script is called as 'clean-tmp-partition' then it will
# by default clean /tmp
#
# Vladimir Bahyl - 11/2003
#

# Steve Traylen,  Jul 2010 
# Disable the sync, it kills us, the fear is we delete an extra file
# but so what.
# Add timestamps per line to the logging.

# Steve Traylen Aug 2010
# Now use to perl's unlink function rather than fork of a rm.
# Use find | xargs rather than find -exec, much quicker.


use strict;
use IO::Pipe;
use Getopt::Long;
use Sys::Hostname;
use File::Basename;

use lib '/usr/src/sue/dist/lib/sue';
#use CCConfig;

my $stat_command       = '/usr/bin/stat';
my $find_command       = '/usr/bin/find';
my $find_options       = "-xdev -type f -print0 | xargs -r -0 /usr/bin/stat --format='%u#####%s#####%n'" ;
my $lsof_command       = '/usr/sbin/lsof -l';  # /usr/sbin/lsof -l +D $partition +L1
my $ps_command         = '/bin/ps --no-headers -eo uid';
#my $rm_command         = '/bin/rm -f'; # needed because the current Perl can not remove files > 2 GB
# We now use perl's unlink function. We should be fine on SLC5. SteveT August 2010.
my $sync_command       = '/bin/true';  # set this to '' if you do not want to sync (before calculating free space of the partition)

my (@FILES, @PROCESSES) = ((), ());
my %UID                 = ();
my $remove_root_files   = 0;
my $skip_root_processes = 1;
my ($partition, $usage, $quiet, $verbose, $noaction, $desired_occupancy) = ('', '', 0, 0, 0, 0);

my $sum_of_removed_files = 0;
my $log                  = 1;
my $log_file             = '/var/log/clean-partition.log';

use constant QUIET   => 2;
use constant VERBOSE => 3;

#
# Handle command line options
#
my $arguments = join(' ', @ARGV);
GetOptions ('partition=s' => \$partition, 'occupancy=i' => \$desired_occupancy, 'verbose' => \$verbose, 'quiet' => \$quiet, 'noaction' => \$noaction, 'remove-root-files' => \$remove_root_files);
if (lc(basename($0)) eq 'clean-tmp-partition') {
  $partition = '/tmp';
  $usage ="
Usage: $0 [options] --occupancy=<number>

  --occupancy=<number>  desired occupancy of the partition in percents (%)
                        Script will try to free space on $partition until it's
                        occupancy decreases bellow <number>.
                        <number> must be within the interval of (1, 100)
  --remove-root-files   with this option even the files owned by root
                        will be considered
  --noaction            don't remove any files nor kill any jobs
  --verbose             be verbose, show detailed output
  --quiet               be quiet, print only errors
";
} else {
$usage ="
Usage: $0 [options] --partition=<partition> --occupancy=<number>

  --partition=<partition> try to free space on <partition>
                          <partition> must be a separate mount point
  --occupancy=<number>    desired occupancy of the partition in percents (%)
                          Script will try to free space on <partition> until it's
                          occupancy decreases bellow <number>.
                          <number> must be within the interval of (1, 100)
  --remove-root-files     with this option even the files owned by root
                          will be considered
  --noaction              don't remove any files nor kill any jobs
  --verbose               be verbose, show detailed output
  --quiet                 be quiet, print only errors
";
}

die("$usage\n") unless ((($desired_occupancy > 1) and ($desired_occupancy < 100)) and ($partition =~ /^\/\w+/o));
die("$0: options --verbose and --quiet are exclusive\n") if ($quiet and $verbose);
die("$0: requires ROOT priviledges\n") unless ($< == 0);
die("$0: stat command $stat_command is missing\n") unless (-x $stat_command);

#my $cluster = CCConfig::Cluster();
#$cluster =~ s/\s+//og;
#die("$0: this script can only run on LXPLUS, LXBATCH and LXDEV clusters. This node belongs to ".uc($cluster)." cluster.\n") unless ((uc($cluster) eq 'LXPLUS') or (uc($cluster) eq 'LXBATCH') or (uc($cluster) eq 'LXDEV'));
$|=1;
&Report(QUIET, "$0: started ".localtime(time)." by ".(getpwuid($<) ? getpwuid($<) : $<)." on ".hostname." with arguments $arguments\n");

#
# Check if the $partition is a mount point
#
open(MTAB, '/etc/mtab') or &MyDie("$0: can not open /etc/mtab. $!\n");
my $mtab = join('', <MTAB>);
chomp($mtab);
close(MTAB) or &MyDie("$0: can not close /etc/mtab. $!\n");
&MyDie("$0: can not find $partition in /etc/mtab. $partition must be a valid mount point.\n") unless ($mtab =~ /\s*\S+\s+$partition\s+\S*/om);

#
# Find UIDs of all currently running processes on the node
#
my $PS = new IO::Pipe;
&Report(QUIET, "$0: finding UIDs of all processes running on the node ...");
&Report(VERBOSE, "\n");
$PS->reader($ps_command);
while (my $uid=<$PS>) {
  chomp($uid);
  if ($uid =~ /(\d+)/o) {
    $UID{$1} = 1;
  } else {
    warn "$0: incorrect UID $uid\n";
  }
}
if (scalar(keys(%UID))) {
  &Report(VERBOSE, "$0:");
  &Report(QUIET, " found ".scalar(keys(%UID))." distinct UIDs\n");
} else {
  &Report(VERBOSE, "$0:");
  &MyDie(" found no UIDs = no processes running - something is wrong\n");
}

#
# Find all files on the $partition and sort them by size largest first
# We use external call to find here because current Perl doesn't
# support lstat64 hence has problems with files > 2 GB
#
my $FIND = new IO::Pipe;
&Report(QUIET, "$0: finding all files".($verbose ? " (command: $find_command $partition $find_options)": '')." on $partition ...");
&Report(VERBOSE, "\n UID  |     Size     | Filename\n------+--------------+------------------------------------------\n");
$FIND->reader("$find_command $partition $find_options");
while (my $line=<$FIND>) {
  chomp($line);
  if ($line =~ /^(\d+)#####(\d+)#####(.+)/o) {
    my ($uid, $size, $filename) = ($1, $2, $3);
    &MyDie("$0: stat on $filename didn't return complete information (uid: $uid, size: $size)\n") unless (defined $uid and defined $size and defined $filename and ($uid =~ /\d+/o) and ($size =~ /\d+/o) and $filename);
    next if (($uid == 0) and ! $remove_root_files);
    push @FILES, { filename => $filename, size => $size, uid => $uid };
    &Report(VERBOSE, sprintf("%-5s | %+12s | %s\n", $uid, $size, $filename));
  } else {
    warn "$0: unexpected output ($line) from $find_command $partition $find_options\n";
  }
}
if (scalar(@FILES)) {
  &Report(VERBOSE, "$0:");
  &Report(QUIET, " found ".scalar(@FILES)." files\n");
} else {
  &Report(VERBOSE, "$0:");
  &Report(QUIET, " no files found on $partition\n");
}
@FILES = sort { ${$b}{size} <=> ${$a}{size} } @FILES;

#
# Find all open files of all running processes that access something on the $partition
#
my $LSOF = new IO::Pipe;
&Report(QUIET, "$0: finding all processes".($verbose ? " (command: $lsof_command $partition)": '')." accessing files on $partition ...");
&Report(VERBOSE, "\n PID  |  UID  |     Size     | Filename\n------+-------+--------------+------------------------------------------\n");
$LSOF->reader("$lsof_command $partition");
while (my $line=<$LSOF>) {
  chomp($line);
#  next unless ($line =~ /^\S+\s+(\d+)\s+(\d+)\s+\S+\s+REG\s+\S+\s+(\d+)\s+\d+\s+\d+\s+(.+)/o);
  next unless ($line =~ /^\S+\s+(\d+)\s+(\d+)\s+\S+\s+REG\s+\S+\s+(\d+)\s+\d+\s+(.+)/o);
  my ($pid, $uid, $size, $filename) = ($1, $2, $3, $4);
  next if (($uid == 0) and $skip_root_processes);
  push @PROCESSES, { pid => $pid, uid => $uid, size => $size, filename => $filename };
  &Report(VERBOSE, sprintf("%-5s | %-5s | %+12s | %s\n", $pid, $uid, $size, $filename));
}
if (scalar(@PROCESSES)) {
  &Report(VERBOSE, "$0:");
  &Report(QUIET, " found ".scalar(@PROCESSES)." processes\n");
} else {
  &Report(VERBOSE, "$0:");
  &Report(QUIET, " no processes found\n");
}
# Sort processes by 2 fields; first by the fact if they
# are deleted or not and then sort by size
@PROCESSES = sort { (${$b}{filename} =~ /\s+\(deleted\)\s*$/oi) <=> (${$a}{filename} =~ /\s+\(deleted\)\s*$/oi) || ${$b}{size} <=> ${$a}{size} } @PROCESSES;

&Report(QUIET, "$0: syncing disks\n");
my $actual_occupancy = &PartitionOccupancy;
if ($actual_occupancy <= $desired_occupancy) {
  &Report(QUIET, "$0: actual occupancy is $actual_occupancy% which is lower or equal than the desired occupancy $desired_occupancy%\n");
  exit;
}
#
# Try to remove files that are not used by any process in 2 steps:
#  1st remove files of users that are not logged
#  2nd remove files of all users
#
for my $skip_users_logged_in (1, 0) {
  &Report(QUIET, "$0: removing largest files that are".($skip_users_logged_in ? ' not owned by any user currently logged in and are': '')." not used by any process\nOccup. | Username |     Size     | Filename\n-------+----------+--------------+------------------------------------------\n");
  foreach my $filename (@FILES) {
    next if ((${$filename}{filename} eq 'ENTRY-REMOVED') and (${$filename}{size} eq 'ENTRY-REMOVED') and (${$filename}{uid} eq 'ENTRY-REMOVED'));
    next if &FileAccessed(${$filename}{filename});
    next if ((exists $UID{${$filename}{uid}}) and $skip_users_logged_in);
    my $username = getpwuid(${$filename}{uid});
    $username=${$filename}{uid} unless ($username);
    &Report(QUIET, sprintf("%+4s %% | %-8s | %+12s | %s\n", int($actual_occupancy), $username, ${$filename}{size}, ${$filename}{filename}));
    if ($noaction) {
      $sum_of_removed_files += ${$filename}{size};
    } else {
      &MyDie("$0: can not remove ".${$filename}{filename}.". $!\n") unless unlink(${$filename}{filename});

    }
    ${$filename}{filename} = ${$filename}{size} = ${$filename}{uid} = 'ENTRY-REMOVED';
    $actual_occupancy = &PartitionOccupancy;
    exit if ($actual_occupancy <= $desired_occupancy);
  }
}

&Report(QUIET, "$0: becaming brutal, contacting license server, license to kill is up-to-date\n");

#
# Process processes:
#  1st find out the files that have already been removed but
#      are still opened by a process - kill that process.
#  2nd kill all remaining processes that hold an open file
#      on $partition and remove that file
#
&Report(QUIET, "$0: killing processes; 1st those that hold an already deleted file on $partition, 2nd all processes with an open file on $partition\nOccup. | Username |     Size     | Filename\n-------+----------+--------------+------------------------------------------\n");
foreach my $process (@PROCESSES) {
  my $username = getpwuid(${$process}{uid});
  $username=${$process}{uid} unless ($username);
  &Report(QUIET, sprintf("%+4s %% | %-8s | %+12s | %s\n", int($actual_occupancy), $username, ${$process}{size}, ${$process}{filename}));
  kill 9, ${$process}{pid} unless ($noaction);
  if ($noaction) {
    $sum_of_removed_files += ${$process}{size};
  } else {
    unless (${$process}{filename} =~ /\s+\(deleted\)\s*$/oi) {
      &MyDie("$0: can not remove ".${$process}{filename}.". $!\n") unless unlink(${$process}{filename});
    }
  }
  $actual_occupancy = &PartitionOccupancy;
  exit if ($actual_occupancy <= $desired_occupancy);
}

&Report(QUIET, "$0: finished, tried all options to free some space, actual occupancy is ".int($actual_occupancy)."\n");

#################################################################################

#
# Check if a given file is accessed by a process
# Return PID of that process
#
sub FileAccessed ($) {
  my ($filename) = @_;

  my $pid = 0;

  foreach my $process (@PROCESSES) {
    if ($filename eq ${$process}{filename}) {
      $pid = ${$process}{pid};
      last;
    }
  }

  return $pid;
}

#
# Find out how much is the $partition occupied (in %)
#
sub PartitionOccupancy {
  my $percents = undef;

  my $partition_info = '';

  $partition_info=`$sync_command ; $stat_command --filesystem --format='%b#####%f#####%a#####%s' $partition 2>&1`;
  chomp($partition_info);
  &MyDie("$0: can not get partition information with command $stat_command --filesystem --format='%b#####%f#####%a#####%s' $partition 2>&1\n") unless ($partition_info =~ /^\d+#####\d+#####\d+#####\d+$/o);
  my ($partition_size, $partition_free, $partition_available, $block_size) = split ('#####', $partition_info);
  $partition_size *= $block_size;
  $partition_free *= $block_size;
  $partition_available *= $block_size;

  if ($noaction) {
    $partition_free += $sum_of_removed_files;
    $partition_available += $sum_of_removed_files;
  }

  # This formula might look crazy, but it is digged out from
  # the source code of the 'df' command:
  #
  # used = total - available_to_root;
  # u100 = used * 100;
  # nonroot_total = used + available;
  # pct = u100 / nonroot_total + (u100 % nonroot_total != 0);

  my $used = $partition_size - $partition_free;
  my $nonroot_total = $used + $partition_available;
  $percents = int(($used * 100) / $nonroot_total + ((($used * 100) % $nonroot_total) != 0));

  &MyDie("$0: can not calculate percentual occupancy of the partition $partition - something is wrong\n") unless (defined $percents);

  return $percents;
}

sub Report ($) {
  my ($code, $message) = @_;

  print $message if ((($code == VERBOSE) and $verbose) or (($code == QUIET) and ! $quiet));

  if ($log) {
    open LOG, ">>$log_file" or &MyDie("$0: can not append to the log file $log_file. $!\n");
    print LOG localtime().": ".$message;
    close LOG or &MyDie("$0: can not close the log file $log_file. $!\n");
  }

  return;
}

sub MyDie ($) {
  my ($message) = @_;

  $quiet = 1;
  &Report(QUIET, $message);

  die $message;
}
