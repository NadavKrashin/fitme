#!/usr/bin/env bash
# Cuts a production release: stamps the version, moves CHANGELOG "Unreleased" under it, tags vX.Y.Z and pushes.
# CI then builds Release and, after approval, uploads it to TestFlight. See docs/RELEASE_PROCESS.md.
# Usage: scripts/release.sh 1.2.0
set -euo pipefail

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: make release VERSION=MAJOR.MINOR.PATCH" >&2; exit 1; }
tag="v$version"

[[ "$(git branch --show-current)" == "main" ]] || { echo "Releases are cut from main." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean." >&2; exit 1; }
git fetch --quiet origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main is not in sync with origin/main." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "Tag $tag already exists." >&2; exit 1; }

# The Unreleased section must say what's shipping.
unreleased="$(awk '/^## \[Unreleased\]/{flag=1; next} /^## \[/{flag=0} flag' CHANGELOG.md | grep -v '^\s*$' || true)"
[[ -n "$unreleased" ]] || { echo "CHANGELOG.md has nothing under [Unreleased]." >&2; exit 1; }

perl -pi -e "s/^(    MARKETING_VERSION: )\"[^\"]*\"/\\1\"$version\"/" project.yml
perl -pi -e "s/^## \\[Unreleased\\]\$/## [Unreleased]\\n\\n## [$version] - $(date +%Y-%m-%d)/" CHANGELOG.md

git add project.yml CHANGELOG.md
git commit --quiet -m "Release $version"
git tag -a "$tag" -m "FitMe $version"
git push --quiet origin main "$tag"
echo "Pushed $tag. Approve the production deploy in GitHub Actions when CI is green."
