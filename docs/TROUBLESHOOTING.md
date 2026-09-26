# Troubleshooting

Failure modes actually encountered in this project's history, with their real fixes.

## "Unknown archive type" when installing a .deb

**Cause:** the ar archive was malformed — member names written as directory-style
entries (`debian-binary/`), wrong member modes, or the mode field formatted through
`%o` (decimal 100644 becomes octal `030444`). dpkg/APT reads the member headers, finds
garbage, and reports the file as an unknown archive type.

**Fix:** `PwEvevee/build-system/package/make-deb.pl` writes the format correctly and directly:

- global magic `!<arch>\n`
- members in order: `debian-binary` (`2.0\n`), `control.tar.gz`, `data.tar.lzma`
- 60-byte GNU member headers: name + trailing `/` marker, mode string `100644`
  (literal, never through `%o`), decimal size, `` `\n `` terminator
- bodies padded to even length

**Verify:** `perl PwEvevee/build-system/tests/deb-format-test.pl` (30 checks) — it parses the generated
archive back member-by-member and asserts every field, then decodes the LZMA member
with `xz` and reads the tar. The same reader from the pre-restructure toolchain
(`scripts/deb-tree.pl`) also parses it cleanly.

**Historical proof:** rebuilding the reference Eevee deb's data from its unpacked
payload produced a `data.tar.lzma` byte-identical to the original working package
(5,970,903 bytes, sha-verified member-for-member).

## Eevee loads but its icons / resources don't appear

**Cause:** the build was missing Eevee's resources, not placing them in a "special"
directory. Eevee's BundleHelper searches:

1. `<home>/Library/Application Support/EeveeSpotify.bundle` (jailbreak layout), then
2. `Spotify.app/EeveeSpotify.bundle` (main-bundle fallback)

The known-good IPA ships the bundle inside the app (fallback 2) **plus 142 icon PNGs
at the app root** — the icon picker reads them there. Builds that skipped either part
showed the tweak working with broken theming.

**Fix:** the unified build installs both (bundle + icons) and `resolve-deps.pl`
fails the build if `EeveeSpotify.bundle/Info.plist`, the en.lproj strings, or fewer
than 140 app-root PNGs are present.

**Verify:**

```bash
unzip -l dist/<build>.ipa | grep -c EeveeSpotify.bundle      # 58 entries
unzip -l dist/<build>.ipa | grep -cE 'Payload/Spotify.app/[^/]+\.png$'  # >= 142
```

## Sideloadly injects conflicts or double-injects

**Cause:** letting Sideloadly inject tweaks on top of an IPA that already carries them.
The unified IPA is already fully integrated — the five load commands are in the main
executable and every dependency ships inside the app.

**Fix:** use Sideloadly (or any signer) in **sign-only** mode on the unified IPA. Do
not feed it `.deb`/`.dylib` inputs. If you must use an injection mode, verify the
binary afterwards: `ncmds` must still be 153 and each load command must appear exactly
once (the Mach-O validator's duplicate check exists for this).

**Verify:**

```bash
unzip -p dist/<build>.ipa Payload/Spotify.app/Spotify > /tmp/exe
perl scripts/macho-dump.pl /tmp/exe | grep -cE 'LC_LOAD_DYLIB @executable_path/Frameworks/(spotifyglass|Eevee)'
# 5
```

## Injector refuses: "padding after load commands is not zero"

**Cause:** the input binary was already modified (injected by another tool) and the
padding region contains data. Overwriting it would corrupt the binary.

**Fix:** start from a clean decrypted IPA. The pipeline assumes an unmodified input;
`unified.sh` on a fresh 9.1.84 IPA has ~131 KB of zero padding available.

## Injector refuses: "no room for another load command"

**Cause:** pathological binary with no padding. Not seen on 9.1.84 (needs ~72 bytes per
command; 131 KB is available). If it happens, the input is not the expected binary —
check its version with `PwEvevee/build-system/lib/plist-value.pl Info.plist CFBundleShortVersionString`.

## Wrong Spotify version / tweak mismatch

spoti.pw 0.22.0 is built and tested against Spotify **9.1.84** (0.21.1 against 9.1.78).
The mod hooks Spotify's own classes, which change between releases. If you feed a
different version, the build may succeed and the app may then crash at runtime. The
manifest records the input version — check `dist/build-manifest.json` before publishing.

## Dependency resolution fails with DUPLICATE DEPENDENCY

**Cause:** two suppliers provided the same dependency with different bytes (e.g. a
CydiaSubstrate from two sources).

**Fix:** pick one supplier. The policy lives in `PwEvevee/dependencies.json`
(`duplicate_policy`): byte-identical copies collapse with a note; different copies fail
the build naming both suppliers. Never "fix" this by deleting one copy silently —
resolve which version is actually required, then re-run.

## Website downloads 404

The website serves `website/releases/<name>.ipa`. If it's missing:

1. `perl PwEvevee/build-system/release/make-release.pl <ipa> dist/build-manifest.json` was run, and
2. `perl PwEvevee/build-system/release/render-site.pl` copied in-window files to `website/releases/`, and
3. your web server maps `/releases/` to `website/releases/`.

Check `releases/index.json`: a release with `"past_retention": true` is intentionally
not hosted — it links to GitHub Releases instead.

`perl PwEvevee/build-system/tests/website-tests.pl` checks this for you: it fails if any
page offers a download whose file is not present under `website/releases/`.

## Upstream versions on the site look wrong or stale

The site never hardcodes a version, so a wrong number means the generated data is out of
date or the last fetch failed.

1. `scripts/update-releases.sh` — refetch, re-render and re-check.
2. Read the diagnostics. Each project prints its resolved release; a failure prints why
   and says whether the previous known-good value was kept.
3. A card showing a `cached` badge means GitHub could not be reached on the last run and
   the site is deliberately showing the last good value instead of nothing.
4. `403`/`429` from GitHub is the anonymous rate limit (60 requests/hour). Export
   `GITHUB_TOKEN` and run again.
5. `451` means the repository has been disabled on GitHub. That is a real upstream state,
   not a bug — update the repository coordinates in `website/data/projects.json` if the
   project has moved.

Nothing on the site is edited by hand to fix a version. If a number is wrong, the data
file or `projects.json` is wrong.

## A page shows skeletons or "Release information is temporarily unavailable"

That state only appears when `render-site.pl` has not run against current data, so the
page shipped with an empty data region and the browser fallback took over. Run
`scripts/update-releases.sh` and redeploy `website/`.

## Device testing

The build is validated structurally, but only a device run proves the app: Eevee's
settings pane, the icon picker showing 142 icons, spoti.pw's Mod Settings, and the
Live Activity all need a real launch. Treat every structural validation as necessary,
not sufficient, before publishing.
