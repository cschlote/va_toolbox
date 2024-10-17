#!/usr/bin/env bash
set -ex

# Compile and run the programm in unittest mode
dub test -b unittest-cov -- -v

# Anlyse the coverage files
./scripts/calcCoverage.d -j coverage.json
