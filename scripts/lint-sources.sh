#!/usr/bin/env bash
set -ex

# Execute linter on sources
dub lint --report
