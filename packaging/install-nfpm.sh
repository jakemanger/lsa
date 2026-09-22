#!/usr/bin/env bash
# Development/CI helper: install a pinned packaging tool into this checkout.
set -eu
cd "$(dirname "$0")/.."
version=2.47.0
system=$(uname -s)
case $system in Darwin|Linux) ;; *) echo "Unsupported packaging host: $system" >&2; exit 1;; esac
case $(uname -m) in
  arm64|aarch64) arch=arm64;;
  x86_64|amd64) arch=x86_64;;
  *) echo "Unsupported packaging architecture" >&2; exit 1;;
esac
archive="nfpm_${version}_${system}_${arch}.tar.gz"
base="https://github.com/goreleaser/nfpm/releases/download/v$version"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
curl -fsSL "$base/$archive" -o "$temp/$archive"
curl -fsSL "$base/checksums.txt" -o "$temp/checksums.txt"
(cd "$temp" && awk -v name="$archive" '$2 == name' checksums.txt > selected.sha256
  test -s selected.sha256
  shasum -a 256 -c selected.sha256
  tar -xzf "$archive" nfpm)
mkdir -p .tools
install -m 0755 "$temp/nfpm" .tools/nfpm
echo "Installed nFPM $version to .tools/nfpm"
