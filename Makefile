PREFIX ?= /usr/local
VERSION := $(shell sed -n 's/^VERSION="\(.*\)"/\1/p' als)

.PHONY: test lint install uninstall deb formula clean

test:
	bash test.sh

lint:
	shellcheck -s bash als test.sh packaging/build-deb.sh

install:
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 als $(DESTDIR)$(PREFIX)/bin/als

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/als

deb:
	bash packaging/build-deb.sh

# Fill the sha256 in Formula/als.rb from the tagged tarball on GitHub.
formula:
	@sha=$$(curl -fsSL https://github.com/jakemanger/als/archive/refs/tags/v$(VERSION).tar.gz | shasum -a 256 | cut -d' ' -f1); \
	sed -i.bak -e 's|^  url .*|  url "https://github.com/jakemanger/als/archive/refs/tags/v$(VERSION).tar.gz"|' \
	           -e "s|^  sha256 .*|  sha256 \"$$sha\"|" Formula/als.rb && rm Formula/als.rb.bak; \
	echo "Formula/als.rb -> v$(VERSION) $$sha"

clean:
	rm -rf dist
