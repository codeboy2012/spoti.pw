# Spotipw/ — the upstream spoti.pw project

This folder is the [spoti.pw](https://github.com/skopevoj/spoti.pw) source tree by
Vojtěch Škopek ([skopevoj](https://github.com/skopevoj)), moved here **intact** so its
project identity, license obligations and internal relative paths stay exactly as
upstream ships them. Nothing in this folder is PwEevee build infrastructure.

## What's here

| Path | What it is |
|---|---|
| `tweak/` | the Theos tweak (Objective-C + Logos) — becomes `spotifyglass.dylib` |
| `extension/` | the Live Activity extension |
| `harness/` | macOS harnesses for exercising tweak engines outside Spotify |
| `vendor/` | vendored third-party code (libbs2b, WDL/EEL2 — own licenses preserved) |
| `scripts/` | upstream dev scripts (flag extraction, layer checks, pipeline) |
| `ipa/`, `plist/` | packaging inputs for upstream's own release flow |
| `Makefile`, `version.txt` | upstream build entry point and version |
| `LICENSE`, `CLA.md`, `CHANGELOG.md` | upstream legal + history |
| `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/` | upstream agent/dev guidance |
| `.github/`, `release-please-config.json` | upstream release tooling |
| `.gitattributes`, `.editorconfig`, `.signing.env.example` | upstream repo config |

## Rules

- **Do not restructure inside this folder.** Internal scripts reference `tweak/Sources`
  by relative path and assume the upstream layout.
- **Do not import from here into `PwEvevee/` or `Evevee Spotify/` build code.** The
  unified build consumes the *compiled* payload (`PwEvevee/components/spotipw/`), not
  this source tree.
- Upstream license (PolyForm Strict 1.0.0 for 0.22.0; GPL-3.0 for ≤ 0.21.1) applies to
  everything here; its vendored dependencies keep their own licenses.
- Building the tweak itself from source still follows upstream's docs
  (`docs/tweaks.md` at the repository root covers the architecture).
