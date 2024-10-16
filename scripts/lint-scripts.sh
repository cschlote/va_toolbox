#!/usr/bin/env bash
set -exu pipefail

echo "linting ..."

#docker run --rm -i hadolint/hadolint < Dockerfile
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck scripts/*.sh

echo "Finished linting successfully."