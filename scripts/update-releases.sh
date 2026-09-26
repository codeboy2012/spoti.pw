#!/usr/bin/env bash
# ============================================================================
# update-releases.sh — refresh the website's release information, one command
# ============================================================================
#
#   scripts/update-releases.sh [options]
#
# Does the whole job:
#   1. fetches the newest published GitHub release for every project declared in
#      website/data/projects.json  ->  website/data/releases.json
#   2. fetches every AltSource declared there (SideloadLabs, for EeveeSpotify)
#      ->  website/data/altsource.json
#   3. re-renders website/ from website-src/ so the new data is actually visible
#   4. runs the website integrity checks
#
# GitHub is the source of truth for releases. The AltSource is a separate source
# of installable IPA variants and is kept in its own file; neither is ever
# presented as the other.
#
# Options (anything else is passed through to both updaters):
#   --no-render      only regenerate the data files
#   --no-test        skip the integrity checks
#   --no-altsource   skip the AltSource refresh
#   --verify-assets  HEAD-check every download URL
#   --strict         fail if any project or source did not update cleanly
#   --offline        do not call the network; re-render from existing data
#
# Set GITHUB_TOKEN to raise the API rate limit. It is passed to curl through a
# 0600 config file, is never written into the generated data, and never reaches
# the browser.
#
# Requirements: bash, perl (core modules only), curl or wget. No Node, no npm.
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

RENDER=1
TEST=1
ALTSOURCE=1
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-render)    RENDER=0 ;;
    --no-test)      TEST=0 ;;
    --no-altsource) ALTSOURCE=0 ;;
    -h|--help)      sed -n '3,32p' "$0"; exit 0 ;;
    *)              ARGS+=("$arg") ;;
  esac
done

command -v perl >/dev/null || { echo "perl is required" >&2; exit 1; }

TOTAL=4
[ "$ALTSOURCE" = 1 ] || TOTAL=3
STEP=0
step() { STEP=$((STEP + 1)); printf '\n\033[1m==> %d/%d  %s\033[0m\n' "$STEP" "$TOTAL" "$*"; }

step "fetching release data from GitHub"
perl PwEvevee/build-system/release/update-releases.pl ${ARGS[@]+"${ARGS[@]}"}

if [ "$ALTSOURCE" = 1 ]; then
  step "fetching AltSource variant data"
  perl PwEvevee/build-system/release/update-altsource.pl ${ARGS[@]+"${ARGS[@]}"}
fi

if [ "$RENDER" = 1 ]; then
  step "rendering the website"
  perl PwEvevee/build-system/release/render-site.pl
else
  step "rendering skipped (--no-render)"
fi

if [ "$TEST" = 1 ]; then
  step "checking the generated site"
  perl PwEvevee/build-system/tests/website-tests.pl
else
  step "checks skipped (--no-test)"
fi

printf '\nRelease information is up to date.\n'
