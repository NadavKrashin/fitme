#!/usr/bin/env bash
# Fails if a production app bundle contains staging-only demo data.
# Usage: scripts/verify-release.sh path/to/FitMe.app
set -euo pipefail

app="${1:?usage: verify-release.sh path/to/FitMe.app}"
[[ -d "$app" ]] || { echo "No app bundle at $app" >&2; exit 1; }

if find "$app" -name 'DemoCloset*' | grep -q .; then
    echo "error: demo closet resource found in Release bundle" >&2
    exit 1
fi
binary="$app/FitMe"
[[ -f "$binary" ]] || { echo "No binary at $binary" >&2; exit 1; }
# grep -c reads all input (grep -q would SIGPIPE strings); "|| true" only covers "zero matches".
matches="$(strings "$binary" | grep -c 'DemoCloset' || true)"
if [[ "$matches" != "0" ]]; then
    echo "error: demo closet code found in Release binary ($matches references)" >&2
    exit 1
fi
echo "Release bundle is clean: no demo data."
