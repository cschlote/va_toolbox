#!/usr/bin/env bash
set -exu pipefail

7z a -tzip va-toolbox-bin.zip libva_toolbox.a

7z a -tzip va-toolbox-docs.zip docs docs.json

7z a -tzip va-toolbox-coverage.zip source*.lst coverage.json

echo "Succesfully deployed package."
