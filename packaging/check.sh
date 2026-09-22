#!/usr/bin/env bash
# Validate the release files without installing into the host system.
set -eu
cd "$(dirname "$0")/.."
python3 packaging/check.py
