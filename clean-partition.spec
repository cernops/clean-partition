Name:           clean-partition
Version:        2.1
Release:        1%{?dist}
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
* Wed Apr 10 2012 Steve Traylen <steve.traylen@cern.ch> - 2.1-1
- Better Readme.

* Tue Apr 9 2012 Steve Traylen <steve.traylen@cern.ch> - 2.0-1
- First github version.





