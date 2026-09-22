#!/usr/bin/env bash
# Build and sign locally; publishing is a separate manual workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
input=${1:-dist/apt-input}
output=${2:-dist/site/apt}
: "${APT_SIGNING_KEY_ID:?Set APT_SIGNING_KEY_ID to the archive key fingerprint}"
expected=$(gpg --batch --show-keys --with-colons packaging/lsa-archive-keyring.asc | awk -F: '$1 == "fpr" { print $10; exit }')
test "$APT_SIGNING_KEY_ID" = "$expected" || { echo 'Signing key does not match the committed public key' >&2; exit 1; }
python3 packaging/apt-index.py "$input" "$output"
gpg --batch --yes --local-user "$APT_SIGNING_KEY_ID" --digest-algo SHA256 \
  --output "$output/InRelease" --clearsign "$output/Release"
gpg --batch --yes --local-user "$APT_SIGNING_KEY_ID" --digest-algo SHA256 \
  --output "$output/Release.gpg" --detach-sign "$output/Release"
cp packaging/lsa-archive-keyring.asc "$output/lsa.asc"
cp packaging/lsa.sources "$output/lsa.sources"
echo "Signed APT repository: $output (not published)."
