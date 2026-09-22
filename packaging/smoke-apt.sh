#!/usr/bin/env bash
# Exercise a real apt client without changing the host's package sources.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${1:-dist/site/apt}
repo=$(cd "$repo" && pwd)
docker run --rm -v "$repo:/repo:ro" ubuntu:24.04 bash -euc '
  mkdir -p /etc/apt/keyrings
  install -m 0644 /repo/lsa.asc /etc/apt/keyrings/lsa.asc
  sed "s|https://jakemanger.github.io/lsa/apt/|file:/repo/|" /repo/lsa.sources > /etc/apt/sources.list.d/lsa.sources
  apt-get update -o APT::Update::Error-Mode=any
  apt-get install -y lsa
  lsa --version
  lsa --help >/dev/null
  apt-get remove -y lsa
  ! command -v lsa
'
