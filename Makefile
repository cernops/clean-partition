
PACKAGE=clean-partition
VERSION=2.1
SCRIPTS=clean-partition.pl clean-partition.logrotate
FILES=Makefile $(PACKAGE).spec README.md

sources: dist

dist: clean $(FILES) Makefile $(PACKAGE).spec
	rm -rf $(PACKAGE)-$(VERSION)
	mkdir -p $(PACKAGE)-$(VERSION)
	cp $(FILES) $(SCRIPTS) $(PACKAGE)-$(VERSION)/.
	tar cvfz $(PACKAGE)-$(VERSION).tar.gz $(PACKAGE)-$(VERSION)

clean:
	rm -rf $(PACKAGE)-$(VERSION)
	rm -rf $(PACKAGE)-$(VERSION).tar.gz


install:
	mkdir -p $(DESTDIR)/etc/cron.d
	mkdir -p $(DESTDIR)/etc/logrotate.d
	mkdir -p $(DESTDIR)/usr/sbin
	install -p -m  755 clean-partition.pl $(DESTDIR)/usr/sbin/clean-partition
	install -p -m  644 clean-partition.logrotate $(DESTDIR)/etc/logrotate.d/clean-partition



rpm:    dist
	rpmbuild --define "_sourcedir $(PWD)" -ba  $(PACKAGE).spec

tag: clean
	git tag v$(VERSION)
      
koji:   clean
	koji -c~/.koji/ai-config build --nowait ai6 git://github.com/cernops/$(PACKAGE).git?#v$(VERSION)
	koji -c~/.koji/ai-config build --nowait ai5 git://github.com/cernops/$(PACKAGE).git?#v$(VERSION)

