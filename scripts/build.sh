#!/usr/bin/env bash
set -ex

# We cache the DUB builds, so allow upgrades
dub upgrade

# Verbosely build the dub package
dub build -v

# Also build the ddox documentation
dub fetch ddox
dub build --build=ddox

echo "Successfully finished build script."
