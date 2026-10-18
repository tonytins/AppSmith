# AppSmith roadmap: milestones and what's next

> **Last reviewed:** 2026-10-18 · **Last updated:** 2026-10-18 · **Change:** created · **Target:** Linux (Type 2 AppImage → macOS-style .app bundles)

> AppSmith wraps existing AppImages in `.app` directory bundles — it does not assemble AppDirs or collect shared-library dependencies. `TestApp/` is a separate Shaft GUI package used to exercise those workflows.

## Alpha gate

The stage gate: AppSmith's core workflows must each work end to end on Linux. Any `no`, or a `partial` that blocks the workflow, keeps AppSmith pre-alpha. Assessed 2026-10-18: a row blocks only when a typical user cannot complete the workflow at all on Linux for typical inputs; degraded fidelity or a missing sub-case is `partial, not blocking` (a beta item).

| Core workflow | Works end to end? | Evidence | Hours to pass |
|---|---|---|---|
| Build an AppImage from an AppDir | yes | `appsmith build` with `mksquashfs` and a Type 2 runtime; 16 tests pass | 0 |
| Bundle an AppImage into a `.app` directory | yes | `appsmith bundle` writes `Contents/Manifest.toml`, `AppRun`, desktop entry, icon/assets | 0 |
| Open a bundle through its AppRun | yes | `appsmith open <bundle>` launches the payload and forwards arguments | 0 |
| Install/uninstall desktop entry | yes | `appsmith install`/`uninstall` register or remove the user's applications menu entry | 0 |

**Result: alpha.** Every core workflow can be completed on Linux; AppSmith is ready for real work.

## Current focus

In order:

1. **Finish the manifest compatibility layer** — installer reader falls back from `Manifest.toml` → legacy `Manifest.json` → Apple property-list `Manifest.plist`; add tests covering TOML write/read, legacy JSON read, and plist read.
2. **TOML config file support** — `swift-configuration-toml`/`swift-tol` for config files (blocked until `CTomlPlusPlus` builds reliably via SwiftPM; JSON works today).
3. **TestApp integration** — BLOCKED: Shaft/Skia build dependencies unavailable (Skia artifact bundle missing). When deps are available (Distrobox/Podman), exercise `appsmith build`/`bundle`/`open` against `.build/TestApp.app`.

Decided against for now: self-installing updates and an update check at start (manual only); committing changes unless explicitly asked.

## Milestones

"Done" is the estimated share of that milestone's acceptance criteria that are met, not lines of code.

| M | Milestone | Plan size (h) | Done | Remaining (h) | Notes |
|---|---|---|---|---|---|
| M0 | Rename DotAppImage → AppSmith | 2–5 | 100% | 0 | Package, targets, executable, sources, tests, READMEs, install.sh, AGENTS.md, addons/gnome extension; `TestApp/` left as a separate package |
| M1 | Manifest format switch: JSON → TOML with backwards compatibility | 10–20 | 90% | 1–3 | Writer emits `Contents/Manifest.toml` (manual TOML encoder; swift-tol's C++ module doesn't build via SwiftPM here). Reader tries `.toml` → `.json` → `.plist`. Missing: plist-read test, TOML round-trip test |
| M2 | swift-configuration CLI argument defaults | 10–20 | 0% | 10–20 | Not intended — carried away. `Bundle` options were made optional and resolved via swift-configuration layering, but this scope-crept beyond the manifest compatibility work. Revert to required CLI options unless explicitly revisited; M2 remains open as a decision point, not committed work. |
| M3 | TestApp integration and smoke tests | 15–30 | 0% | 15–30 | Blocked: Shaft/Skia build dependencies unavailable (Skia artifact bundle missing). When deps are available (Distrobox/Podman), run: build TestApp → create .build/TestApp.AppDir → appsmith build → appsmith bundle → appsmith open .build/TestApp.app |
| M4 | 1.0 polish: docs, installers, packaging | 10–20 | 0% | 10–20 | README accuracy, `install.sh` verification, AppImage/deb/rpm/Flatpak notes, AGENTS.md build commands |

| | **Total** | **47–95** | **≈ 10%** | **≈ 36–56** |

## Upcoming milestones, ranked

| Rank | Next milestone | Closes | Estimate (h) | Status |
|---|---|---|---|---|
| 0 | Manifest compatibility tests (TOML read, JSON read, plist read) | M1 | 1–3 | ready |
| 1 | TestApp smoke test: build → bundle → open | M3 | 15–30 | blocked: Shaft/Skia deps |
| 2 | TOML config file support (when swift-tol builds) | M2 | 10–20 | blocked: CTomlPlusPlus |
| 3 | 1.0 polish: docs and installers | M4 | 10–20 | ready |

## Critical path

M0 → M1 → M2 had to happen in order, and did. M3 depends on M1's manifest compatibility being complete. M4 is independent and can run in parallel.

## Risks most likely to push estimates up

- `CTomlPlusPlus` C++ module not building via SwiftPM in this toolchain — blocks TOML config files and potentially TOML manifest write via `swift-configuration-toml`/`swift-tol`; manual TOML works as a fallback.
- Shaft's Linux build requires native SDL3/Skia headers; on Fedora Atomic, use Distrobox/Podman rather than layering build deps onto the host.
- External subprocesses (`mksquashfs`, desktop-file-install, `xdg-desktop-menu`) may be missing or fail — typed errors and actionable diagnostics required, no traps.
- Unmeasured fidelity: without an AppImage interop suite, quality gaps surface as user reports.

## Revision history

| Date | Change | Summary |
|---|---|---|
| 2026-10-18 | created | Created from Stash/Reference/Roadmap.md structure; M0–M2 marked done, M3–M4 upcoming |
| 2026-10-18 | minor | M2 reverted (not intended — carried away); config.json/env-var layering for CLI defaults removed from scope; totals and upcoming milestones updated |
| 2026-10-18 | minor | M3 investigated: Shaft/Skia build deps unavailable (Skia artifact bundle missing); config tests fixed to avoid global env-var state (concurrent test isolation); all 19 tests pass |

## Footnote

^1 The `~/.config/appsmith/config.json` config file and `APPSMITH_*` environment variable support for CLI argument defaults (M2) was not intended — carried away during implementation. It has been reverted from the roadmap's scope. `Bundle` options remain required CLI arguments unless explicitly revisited.
