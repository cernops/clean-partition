clean-partition
===============

Script will try to remove files from $partition according an algorithm

The following algorithm will be used:

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

Authors 

Vladimir Bahyl - 11/2003
Steve Traylen - Aug 2010

