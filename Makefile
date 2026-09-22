PREFIX ?= /usr/local

.PHONY: test lint install uninstall packages check-packages smoke-linux deb rpm arch formula clean

test:
	bash test.sh

lint:
	shellcheck -s bash lsa test.sh packaging/*.sh
	actionlint
	ruby -c Formula/lsa.rb

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 lsa "$(DESTDIR)$(PREFIX)/bin/lsa"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/lsa"

packages:
	bash packaging/build.sh all

deb rpm:
	bash packaging/build.sh $@

arch:
	bash packaging/build.sh archlinux

check-packages:
	bash packaging/check.sh

smoke-linux:
	bash packaging/smoke-linux.sh

formula:
	bash packaging/formula.sh > Formula/lsa.rb

clean:
	rm -rf dist
