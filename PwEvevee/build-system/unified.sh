#!/usr/bin/env bash
# ============================================================
# unified.sh — the ONE authoritative build pipeline
# ============================================================
#
#   decrypted Spotify IPA (input)
#        ↓  prepare          unzip, drop stale output, read version
#        ↓  merge            spoti.pw + EeveeSpotify payloads into Spotify.app
#        ↓  resolve          dependency resolution (duplicates = hard failure)
#        ↓  inject           LC_LOAD_DYLIB for every declared load command
#        ↓  validate         Mach-O + filesystem structure
#        ↓  package          deterministic store-only IPA
#        ↓  manifest         dist/build-manifest.json
#
#   PwEvevee/build-system/unified.sh <decrypted.ipa> [-o dist/out.ipa]
#
# No manual file editing between steps; rerunnable; stale-output safe.
set -euo pipefail
umask 022

ORIG_PWD="$(pwd)"
BS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$BS/../.." && pwd)"
cd "$REPO"

IN="" OUT="" OUT_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; OUT_GIVEN=1; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { echo "usage: PwEvevee/build-system/unified.sh <decrypted Spotify .ipa> [-o dist/out.ipa]" >&2; exit 1; }
case "$IN" in /*) ;; *) IN="$ORIG_PWD/$IN" ;; esac
[ -f "$IN" ] || { echo "no such input IPA: $IN" >&2; exit 1; }
if [ "$OUT_GIVEN" = 1 ]; then case "$OUT" in /*) ;; *) OUT="$ORIG_PWD/$OUT" ;; esac; fi

WORK="$BS/_work"
DIST="dist"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\n!! FAIL: %s\n' "$*" >&2; exit 1; }

command -v perl >/dev/null || fail "perl is required"
command -v xz    >/dev/null || fail "xz is required (apt/brew install xz)"
command -v unzip >/dev/null || fail "unzip is required"

step "0. clean stale output"
rm -rf "$WORK"; mkdir -p "$WORK/app/Payload" "$DIST"

step "1. prepare input IPA"
APP_REL="$(unzip -Z1 "$IN" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
[ -n "$APP_REL" ] || fail "no Payload/*.app in $IN"
APP_REL="${APP_REL%/}"
echo "    app dir: $APP_REL"
mkdir -p "$WORK/in"
( cd "$WORK/in" && unzip -q "$IN" ) || fail "unzip of $IN failed"
STAGED="$WORK/in/$APP_REL"
[ -d "$STAGED" ] || fail "staged app dir missing: $STAGED"

SPOTIFY_VERSION="$(perl "$BS/lib/plist-value.pl" "$STAGED/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
echo "    Spotify version: $SPOTIFY_VERSION"

step "2. merge components"
# spotipw: tweak dylib → Frameworks/
mkdir -p "$STAGED/Frameworks"
cp -a "$BS/../components/spotipw/dylibs/spotifyglass.dylib" "$STAGED/Frameworks/"
# eeveespotify: MobileSubstrate dylib → Frameworks/ (proven IPA layout)
cp -a "Evevee Spotify/component/package/dynamic-libraries/EeveeSpotify.dylib" "$STAGED/Frameworks/"
# frameworks (shared resolver below decides which)
cp -a "Evevee Spotify/component/frameworks/Orion.framework"             "$STAGED/Frameworks/"
cp -a "Evevee Spotify/component/frameworks/EeveeSwiftProtobuf.framework" "$STAGED/Frameworks/"
# Eevee resources: bundle + icon PNGs at app root (BundleHelper search order, audit §3)
cp -a "Evevee Spotify/component/bundles/EeveeSpotify.bundle" "$STAGED/"
find "Evevee Spotify/component/resources" -type f | while read -r r; do
  rel="${r#"Evevee Spotify/component/resources"/}"
  mkdir -p "$STAGED/$(dirname "$rel")"
  cp -a "$r" "$STAGED/$rel"
done
# shared dependency
cp -a "$BS/../shared-dependencies/cydiasubstrate/CydiaSubstrate.framework" "$STAGED/Frameworks/"
echo "    merged: spotifyglass.dylib, EeveeSpotify.dylib, 3 frameworks, bundle + $(find "Evevee Spotify/component/resources" -type f | wc -l) resources"

step "3. resolve dependencies"
perl "$BS/package/resolve-deps.pl" "$STAGED" || fail "dependency resolution failed"

step "4. inject load commands"
BIN="$STAGED/Spotify"
[ -f "$BIN" ] || fail "no main executable at $BIN"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  perl "$BS/inject/inject-dylib.pl" "$BIN" "$name"
done < <(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print "$_->{name}\n" for @{$d->{load_commands}}' < "$BS/../dependencies.json")

step "5. validate Mach-O"
perl "$BS/validate/validate-macho.pl" "$BIN" "$STAGED" || fail "Mach-O validation failed"

step "6. validate filesystem structure"
perl "$BS/validate/validate-ipa.pl" "$STAGED" || fail "structure validation failed"

step "7. package IPA (deterministic, store-only)"
MOD_VERSION="$(sed 's/[^0-9A-Za-z.-]//g' "$REPO/Spotipw/version.txt" 2>/dev/null || echo 0.0.0)"
EEVEE_VERSION="$(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print $d->{version}' < "Evevee Spotify/component/manifest.json")"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
if [ "$OUT_GIVEN" = 0 ]; then
  OUT="$DIST/pweevee-$MOD_VERSION-eevee${EEVEE_VERSION%%-*}-$STAMP.ipa"
fi
mkdir -p "$(dirname "$OUT")"
perl "$BS/package/make-ipa.pl" "$STAGED" "$OUT"
echo "    $(du -h "$OUT" | cut -f1)  $OUT"

step "8. build manifest"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IPA_SHA256="$(perl -MDigest::SHA -e 'print Digest::SHA::sha256_hex(scalar do { local $/; open(my $f,"<:raw",$ARGV[0]); <$f> })' "$OUT")"
IPA_SIZE="$(wc -c < "$OUT" | tr -d ' ')"
OUT_REL="${OUT#"$REPO"/}"   # repo-relative for the manifest when OUT sits inside the repo
DYLIBS="$(cd "$STAGED/Frameworks" && ls *.dylib 2>/dev/null | sed 's/^/  /' | tr '\n' ' ')"
FRAMEWORKS="$(cd "$STAGED/Frameworks" && ls -d *.framework 2>/dev/null | sed 's/^/  /' | tr '\n' ' ')"
SPOTIPW_VERSION="$(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print $d->{version}' < "$BS/../components/spotipw/manifest.json")"
SPOTIPW_COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
EEVEE_COMMIT="unknown (binary release 6.6.8-selfcontained.1)"
MANIFEST="$DIST/build-manifest.json"

cat > "$MANIFEST" <<EOF
{
  "project": "pweevee-unified (spoti.pw + EeveeSpotify integration build)",
  "spotify_version": "$SPOTIFY_VERSION",
  "spotipw_version": "$SPOTIPW_VERSION",
  "spotipw_commit": "$SPOTIPW_COMMIT",
  "eevee_version": "$EEVEE_VERSION",
  "eevee_commit": "$EEVEE_COMMIT",
  "build_date": "$BUILD_DATE",
  "ipa_path": "$OUT_REL",
  "ipa_sha256": "$IPA_SHA256",
  "ipa_size": $IPA_SIZE,
  "dylibs": ["spotifyglass.dylib", "EeveeSpotify.dylib"],
  "frameworks": ["CydiaSubstrate.framework", "EeveeSwiftProtobuf.framework", "Orion.framework"],
  "bundles": ["EeveeSpotify.bundle"],
  "resources": {
    "eevee_icons": $(find "Evevee Spotify/component/resources" -type f | wc -l),
    "load_commands": $(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print scalar @{$d->{expected_load_commands}}' < "$BS/../dependencies.json")
  },
  "validation": {
    "archive": true,
    "mach_o": true,
    "dependencies": true,
    "resources": true,
    "ipa": true
  }
}
EOF
echo "    $MANIFEST"

step "9. run packaging tests"
perl "$BS/tests/deb-format-test.pl" >/dev/null && echo "    deb format tests: OK"
perl "$BS/tests/build-tests.pl"    >/dev/null && echo "    build tests: OK"

printf '\n==> DONE: %s\n    sha256 %s\n' "$OUT" "$IPA_SHA256"
