#!/usr/bin/env bash
# Exercise native package managers in disposable containers, after packaging.
# Requires a running Docker daemon; never installs packages on the host.
set -eu
cd "$(dirname "$0")/.."
version=$(./lsa --version | cut -d' ' -f2)
docker info >/dev/null

docker run --rm -e LSA_VERSION="$version" -v "$PWD/dist:/packages:ro" ubuntu:24.04 bash -euc '
  apt-get update -qq
  apt-get install -y /packages/lsa.deb
  test "$(lsa --version)" = "lsa $LSA_VERSION"
  lsa --help >/dev/null
  apt-get remove -y lsa
  test ! -e /usr/bin/lsa
'

docker run --rm -e LSA_VERSION="$version" -v "$PWD/dist:/packages:ro" fedora:latest bash -euc '
  dnf install -y /packages/lsa.rpm
  test "$(lsa --version)" = "lsa $LSA_VERSION"
  lsa --help >/dev/null
  dnf remove -y lsa
  test ! -e /usr/bin/lsa
'

docker run --rm -e LSA_VERSION="$version" -v "$PWD/dist:/packages:ro" archlinux:base bash -euc '
  pacman -Syu --noconfirm
  pacman -U --noconfirm /packages/lsa.pkg.tar.zst
  test "$(lsa --version)" = "lsa $LSA_VERSION"
  lsa --help >/dev/null
  pacman -R --noconfirm lsa
  test ! -e /usr/bin/lsa
'
