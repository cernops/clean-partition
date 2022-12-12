Name:           clean-partition
Version:        2.2
Release:        4%{?dist}
Summary:        Clean a partition.

Group:          CERN
License:        BSD
URL:            https://github.com/cernops/clean-partition
Source0:        %{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildArch:      noarch


%description
Clean partition.

%prep
%setup -q

%build
#Nothing to build.

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%{_sbindir}/clean-partition
%{_sysconfdir}/logrotate.d/clean-partition
%doc README.md

%changelog
* Mon Dec 12 2022 Steve Traylen <steve.traylen@cern.ch> - 2.2-4
- Rebuild for AL/EL 8,9

* Fri Jan 21 2022 Steve Traylen <steve.traylen@cern.ch> - 2.2-3
- Rebuilt to add centos9

* Wed Mar 10 2021 Steve Traylen <steve.traylen@cern.ch> - 2.2-2
- Rebuilt to add centos8s

* Wed Apr 11 2012 Steve Traylen <steve.traylen@cern.ch> - 2.2-1
- --filesystem no longers works to stat on SL6. Use 
  --file-system instead which works on 5 as well.

* Tue Apr 10 2012 Steve Traylen <steve.traylen@cern.ch> - 2.1-1
- Better Readme.

* Mon Apr 9 2012 Steve Traylen <steve.traylen@cern.ch> - 2.0-1
- First github version.





