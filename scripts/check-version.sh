#!/usr/bin/env bash
# Fails unless project.yml's MARKETING_VERSION equals the given version (the release tag without the "v").
# Usage: scripts/check-version.sh 1.2.0
set -euo pipefail

expected="${1:?usage: check-version.sh MAJOR.MINOR.PATCH}"
actual="$(sed -nE 's/^    MARKETING_VERSION: "([^"]+)"/\1/p' project.yml)"
if [[ "$actual" != "$expected" ]]; then
    echo "error: tag says $expected but project.yml MARKETING_VERSION is ${actual:-missing}. Use 'make release'." >&2
    exit 1
fi
echo "Version $actual matches the tag."
