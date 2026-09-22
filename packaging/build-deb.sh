#!/usr/bin/env bash
# Build dist/als_<version>_all.deb. Needs dpkg-deb (any Debian/Ubuntu box, or `brew install dpkg`).
set -eu
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' als)
root=dist/als_${VERSION}_all
rm -rf "$root"
install -d "$root/DEBIAN" "$root/usr/bin" "$root/usr/share/doc/als"
install -m 0755 als "$root/usr/bin/als"
install -m 0644 README.md LICENSE "$root/usr/share/doc/als/"
cat > "$root/DEBIAN/control" <<EOF
Package: als
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: bash (>= 3.2), grep, sed
Recommends: jq
Maintainer: Jake Manger <52495554+jakemanger@users.noreply.github.com>
Homepage: https://github.com/jakemanger/als
Description: ls for agent sessions
 Lists, prints and resumes Claude Code, Codex and pi transcripts.
EOF
dpkg-deb --build --root-owner-group "$root" "dist/als_${VERSION}_all.deb"
cp "dist/als_${VERSION}_all.deb" dist/als.deb
echo "built dist/als_${VERSION}_all.deb"
