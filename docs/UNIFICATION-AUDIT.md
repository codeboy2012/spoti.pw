# Unification Audit

Date: 2026-09-24 · Auditor: unified-build restructure (see git history)

This document records what was found **before** any restructuring. Nothing in the trees listed
below was modified to produce these findings; findings come from the imported reference clone and
from parsing the binary artifacts in `source-artifacts/` (ar/tar/Mach-O parsing and string
extraction, no guessing).

> **Path note (2026-09-24 reorganisation):** the repository is now split into `Spotipw/`
> (upstream source tree), `PwEvevee/` (unified build system) and `Evevee Spotify/`
> (Eevee payloads + source artifacts). Paths below reflect the layout **at audit time**;
> today `source-artifacts/` is `Evevee Spotify/source-artifacts/` and the upstream
> `tweak/` tree lives under `Spotipw/`. The findings and hashes are unchanged — every
> payload hash was re-verified byte-identical after the move.

---

## 1. What was imported, and where it came from

- `docs/spoti.pw-builds/` is a full **git clone** of
  <https://github.com/codeboy2012/spoti.pw-builds>, preserved exactly as received (`.git` intact,
  branch `main`, `git status` clean).
- Its `origin` URL, and the parent repository's `origin` URL, are the same repository. The parent
  working tree is byte-identical to the import except for the three untracked paths
  (`.freebuff/`, `Evvevv Spotify Data/`, `docs/spoti.pw-builds/`):
  `diff -rq docs/spoti.pw-builds .` → only "Only in" differences.
- HEAD at import time: `f0fd8ef` "Merge pull request #123 …" (release `0.22.0`,
  commit `d0f8fb9`).
- Branches present: `main` (checked out), plus remotes
  `chore/deb-package-id`, `chore/issue-forms`, `ci/release-please`,
  `ci/release-please-bootstrap`, `feat/own-entity-header`, `live-activity-demo`, `redesign`,
  `release-please--branches--main--components--spoti.pw`.
- History: 257 commits total, first 2026-09-06, latest 2026-09-23. 3 human contributors + 1 bot
  (release-please), 32 merged PRs detected.
- Note: the upstream spoti.pw project itself is `skopevoj/spoti.pw` (README links releases
  there). This clone (`codeboy2012/spoti.pw-builds`) is a mirror/fork of that source used for
  build experiments. Both are recorded as upstream in the credits.

## 2. Imported repository structure (reference tree)

```
docs/spoti.pw-builds/
├── Makefile                  # entry points → scripts/pipeline.sh
├── version.txt               # 0.22.0 (release-please managed)
├── README.md                 # "spoti.pw — Spotify, in glass"
├── LICENSE                   # PolyForm Strict 1.0.0 (v0.22.0); releases ≤ 0.21.1 GPL-3.0
├── CLA.md, CHANGELOG.md, release-please-config.json, .release-please-manifest.json
├── .github/workflows/        # build-ipa.yml, cla.yml, release.yml (Release Please)
├── .github/FUNDING.yml       # ko_fi: darkksh
├── tweak/                    # the Theos tweak (Objective-C + Logos)
│   ├── Makefile, control, spotifyglass.plist
│   └── Sources/{App,Core,Diagnostics,Headers,Native,Redesigned,Settings,Shared}
├── extension/                # Live Activity appex + App Groups shim (Swift)
├── scripts/                  # pipeline.sh, insert-dylib.py, extract-flags.py,
│                             # build-extension.sh, merge-appintents.py, install.sh,
│                             # check-layers.sh, record-*.py, dump-log.sh
├── plist/liquid-glass.plist  # filter: com.spotify.client
├── harness/                  # UI test harness screens
├── vendor/
│   ├── audio/{libbs2b,wdl,eel2-parser}   # MIT / zlib licences kept beside code
│   └── com.hopeless.autoflex_0.0.1_iphoneos-arm.deb  # FLEX inspector (debug builds only)
├── ipa/.gitkeep              # the build's decrypted Spotify input (never committed)
├── docs/ (icon, screenshots, tweaks.md)
└── AGENTS.md, CLAUDE.md, .agents/, .claude/
```

### Build system of the import

- `make build` / `make release` → `scripts/pipeline.sh <decrypted.ipa> [--no-flex]`.
- Toolchain: Theos (`$THEOS`, default `~/theos`), iPhoneOS 26+ SDK, `gmake`, `ldid`,
  `dpkg-deb`, **cyan** (pyzule-rw) for injection.
- Pipeline: extract remote-config flags from the IPA → Theos `clean package` builds
  `com.spotipw` `.deb` → Live Activity appex built with `swiftc` (via
  `scripts/build-extension.sh`) → App Groups shim dylib → `cyan -i in.ipa -o out.ipa -f
  <files> -l plist/liquid-glass.plist -w -s` injects the deb payload + appex + dylib →
  `scripts/insert-dylib.py` adds an `LC_LOAD_WEAK_DYLIB` for `SpotifyGlassAppGroups.dylib` into
  the WidgetExtension binary → App Intents metadata merged.
- Output: unsigned `out/spoti.pw-<version>.ipa`; user signs it (SideStore/Feather/Sideloadly…).

### Package system

- `tweak/control`: `Package: com.spotipw`, `Architecture: iphoneos-arm`, no `Version` field
  (Theos injects `version.txt`), no `Depends`.
- `tweak/spotifyglass.plist` filter: `{ Filter = { Bundles = ( "com.spotify.client" ); }; }`.

## 3. Binary artifacts audited (`source-artifacts/`, formerly `Evvevv Spotify Data/`)

| File | Kind | Verified contents |
|---|---|---|
| `EeveeSpotify-6.6.8-SelfContained-v2.deb` | .deb | ar members `debian-binary`(2.0\n), `control.tar.gz`(398 B), `data.tar.lzma`(5,970,903 B); all member modes `100644`; magic `!<arch>\n`. Control: `com.eevee.spotify.selfcontained` v`6.6.8-selfcontained.1`, `Depends: firmware (>= 14.0)`. Data tree (225 entries): `Spotify.app/` with 142 icon PNGs at app root, `EeveeSpotify.bundle` (localized .strings + images), `Spotify.app/Frameworks/{EeveeSwiftProtobuf.framework, Orion.framework}`, and **`var/jb/Library/MobileSubstrate/DynamicLibraries/{EeveeSpotify.dylib,EeveeSpotify.plist}`**. |
| `Evvev sptoify.ipa` | IPA | The known-good **Eevee working build**: Spotify.app with `Frameworks/EeveeSpotify.dylib` (sha256 `631d4f17…79de70`, byte-identical to the deb's dylib), `Frameworks/{CydiaSubstrate,EeveeSwiftProtobuf,Orion}.framework`, `EeveeSpotify.bundle`, Eevee icon PNGs, Safari extension. No spotifyglass dylib, no spoti.pw markers. |
| `Sptoify-No_Watch_App.ipa` | IPA | A SpoTi.pw-family IPA without Watch app; no Eevee components. |
| `com.spotipw_0.21.1.ipa` | IPA | spoti.pw 0.21.1 on **Spotify 9.1.78**; `Frameworks/spotifyglass.dylib` (3,137,328 B), CydiaSubstrate.framework present. |
| `com.spotipw_0.22.0.ipa` | IPA | spoti.pw 0.22.0 on **Spotify 9.1.84** (CFBundleShortVersionString 9.1.84, CFBundleVersion 918402223, MinOS 16.1, id com.spotify.client); `Frameworks/spotifyglass.dylib` (1,747,536 B) + **Eevee already merged**: `Frameworks/EeveeSpotify.dylib` (sha256 `44502470…412ed7b` — *different* from the known-good 631d…), `Frameworks/{EeveeSwiftProtobuf,Orion,CydiaSubstrate}.framework`, `EeveeSpotify.bundle`, Eevee icons, spoti.pw PlugIns (Widget/Intents/Notif). |
| `com.spotipw_0.22.0_iphoneos-arm.deb` | .deb | The tweak deb itself (com.spotipw 0.22.0). |
| `tools/*.pl` | Perl | `build_deb.pl` (the **working** deterministic ar/tar writer with the exact header layout below), `deb_tree.pl`, `macho_dump.pl`, `macho_all.pl` (Mach-O load command dumpers). |

### Mach-O load commands — main `Spotify` executable of `com.spotipw_0.22.0.ipa`

Injection is by **LC_LOAD_DYLIB** into the main executable (Sideloadly/orchestrated), one command
each for:

```
@executable_path/Frameworks/spotifyglass.dylib
@executable_path/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf
@executable_path/Frameworks/Orion.framework/Orion
@executable_path/Frameworks/EeveeSpotify.dylib
@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate
```

`EeveeSpotify.dylib` itself has `LC_LOAD_DYLIB
@executable_path/Frameworks/Orion.framework/Orion` and a weak self-reference; the Orion +
EeveeSwiftProtobuf load commands in the main executable exist because Sideloadly inserts
dependencies of the injected dylib as load commands of the host binary. The unified build
reproduces exactly this set.

### The Eevee resource-bundle finding (answer to "why didn't icons show?")

Strings inside `EeveeSpotify.dylib` (`BundleHelper`):

```
/Library/Application Support/          ← path fragment the helper builds
[EeveeSpotify] ERROR: Could not find EeveeSpotify.bundle!
[EeveeSpotify] WARNING: Could not load en.lproj from bundle
[EeveeSpotify] Loaded bundle from filesystem:        (Application Support copy)
[EeveeSpotify] Loaded bundle from main bundle:       (Spotify.app copy fallback)
```

So Eevee's runtime bundle search order is:

1. **`<home>/Library/Application Support/EeveeSpotify.bundle`** — the path the jailbreak-style
   package layout maps to (`/var/jb/Library/Application Support/EeveeSpotify.bundle` on a
   rootful install; the dylib's `var/jb` rpath strings confirm the jailbreak lineage).
2. **`Spotify.app/EeveeSpotify.bundle`** — fallback "main bundle" copy.

The known-good working IPA therefore ships the bundle **inside the app** and it resolves via
fallback 2 — `Spotify.app/EeveeSpotify.bundle` **is** the location the working build actually
uses. The earlier "icons missing" build failed because its Eevee resources (icon PNGs +
`EeveeSpotify.bundle` content) were absent/incomplete, not because of a different directory:
- 142 Eevee icon PNGs must sit at the **app root** (`Spotify.app/*.png`, e.g.
  `EeveeCustom@2x.png`, `SpotifyMiku~ipad.png` …) — that is where Eevee's icon picker reads them;
- `EeveeSpotify.bundle/` must contain `Info.plist`, `github.png`, and all `.lproj` localization
  directories (the en.lproj/gfx content is byte-identical between the working IPA and the deb,
  verified by SHA-256).
- Optionally the bundle can additionally be installed at
  `Library/Application Support/EeveeSpotify.bundle` for the filesystem search path; the working
  IPA does not need it, but the unified build supports it via a flag.

### Debian packaging finding (the "Unknown archive type" trap)

`tools/build_deb.pl` writes the ar archive **directly** in the correct format — this is the
authoritative layout the generator must reproduce:

- global magic `!<arch>\n` (8 bytes),
- member headers are the 60-byte GNU format with name `name/` (trailing slash), mode `100644`
  (field at offset 42, octal), size decimal at offset 48, backtick-newline terminator at 58,
- members in order `debian-binary` (`2.0\n`), `control.tar.gz`, `data.tar.lzma`,
- data padded to even length,
- `control.tar.gz` reused verbatim from the original deb, `data.tar` written as ustar with
  fixed fields, compressed `xz --format=lzma -9`.
- The earlier failure was malformed headers (directories written as members `debian-binary/`
  etc., wrong modes); the patch-based 180-byte fix is no longer needed once the writer emits
  this layout natively.

## 4. Dependency map (what the unified build must satisfy)

| Dependency | Provided by | Where it ends up | Loaded by |
|---|---|---|---|
| `EeveeSpotify.dylib` | Eevee deb data (`var/jb/.../EeveeSpotify.dylib`) | `Spotify.app/Frameworks/EeveeSpotify.dylib` | main executable (LC_LOAD_DYLIB) |
| `EeveeSpotify.plist` filter | Eevee deb data | **not shipped in IPA** — filter satisfied by the explicit load command | — (kept in components for deb route) |
| `EeveeSwiftProtobuf.framework` | Eevee deb data | `Spotify.app/Frameworks/` | main exec + EeveeSpotify.dylib |
| `Orion.framework` | Eevee deb data | `Spotify.app/Frameworks/` | main exec + EeveeSpotify.dylib |
| `CydiaSubstrate.framework` | working IPA (0.22.0 IPA ships full framework incl. Commands/Headers/Libraries; deb-less) | `Spotify.app/Frameworks/` | main executable (LC_LOAD_DYLIB) |
| `spotifyglass.dylib` (spoti.pw) | Theos build of the tweak (or deb payload) | `Spotify.app/Frameworks/` | main executable (LC_LOAD_DYLIB) |
| `EeveeSpotify.bundle` + 142 icon PNGs | Eevee deb data | `Spotify.app/` root + bundle | Eevee BundleHelper (see §3) |
| Live Activity appex + AppGroups shim | spoti.pw `extension/` build | `PlugIns/SpotifyGlassLiveActivity.appex`, `Frameworks/SpotifyGlassAppGroups.dylib` | widget/app (LC_LOAD_WEAK_DYLIB) |

No dependency is provided by both Eevee and spoti.pw except **CydiaSubstrate** (spoti.pw's own
build needs the framework present because the deb route's SubstrateBootstrap expects it; Eevee
does not load it — no conflict once a single copy is placed) — the resolver treats a same-name
copy as a conflict unless SHA-256-identical, and otherwise picks by declared priority.

## 5. Current repository (pre-restructure) summary

- Everything tracked is the tweak source (see §2). No component extraction, no website, no
  release-index tooling existed.
- Untracked extras: `source-artifacts/` (binaries above), the `docs/spoti.pw-builds/` clone.
- `.gitignore` already excludes `*.ipa`, `out/`, tweak build dirs, `SGFlagList.m`.

## 6. Decisions this audit drives

1. Components are **extracted from the audited artifacts** (Eevee from the SelfContained-v2 deb;
   spoti.pw from the Theos build / 0.22.0 deb), never re-created from guesses.
2. One pipeline, one dependency resolver, one injection step producing **all five** load
   commands (§3) plus validation that every `@executable_path`/`@rpath` dependency exists in the
   final IPA.
3. Eevee resources ship at app root (icons) + `EeveeSpotify.bundle/` inside the app; the
   `var/jb/Library/MobileSubstrate/DynamicLibraries` pair is preserved inside the component for
   the deb route and drives the injection manifest, but is not shipped as dead weight in the IPA.
4. The Debian generator writes the exact ar layout of §3 natively and its tests assert magic,
   member names, order, offsets, sizes, modes, terminators, tar validity and LZMA validity.
5. The imported clone stays untouched under `docs/spoti.pw-builds/` as the reference tree.
