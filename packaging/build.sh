#!/usr/bin/env bash
# Build release files locally. No tags, uploads or publication.
set -eu
cd "$(dirname "$0")/.."
format=${1:-all}
case $format in all|deb|rpm|archlinux) ;; *) echo "usage: $0 [all|deb|rpm|archlinux]" >&2; exit 2;; esac
nfpm=${NFPM:-nfpm}
if ! command -v "$nfpm" >/dev/null; then
  echo "Install nFPM, or run: bash packaging/install-nfpm.sh" >&2
  echo "Then: NFPM=\$PWD/.tools/nfpm make packages" >&2
  exit 1
fi
LSA_VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' lsa)
export LSA_VERSION
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
install -m 0755 lsa "$stage/lsa"
bash packaging/formula.sh > "$stage/lsa.rb"
formats=$format
[ "$format" != all ] || formats='deb rpm archlinux'
for package in $formats; do
  case $package in
    deb) name=lsa.deb;;
    rpm) name=lsa.rpm;;
    archlinux) name=lsa.pkg.tar.zst;;
  esac
  "$nfpm" package --config packaging/nfpm.yaml --packager "$package" --target "$stage/$name"
done
(cd "$stage" && shasum -a 256 lsa lsa.* > SHA256SUMS)
cp "$stage"/* dist/
echo "Release files are in dist/ (not published)."
