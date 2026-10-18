# Project Guidelines

AppSmith is a Linux packaging tool and test project. It builds Type 2
AppImages from prepared AppDirs and wraps existing AppImages in `.app`
directory bundles. `TestApp/` is a small Shaft GUI app for exercising those
workflows on a real desktop.

## Repository layout

```text
AppSmith/   Swift CLI package and its tests
TestApp/       Shaft GUI package and AppDir template
Stash/         Owner's private notes and reference material
```

The two Swift packages build independently. Keep the CLI usable with existing
AppImages; AppImage building and `.app` bundling are separate commands.
`appsmith build` packages an AppDir. It does not assemble the AppDir or
collect the app's shared-library dependencies.

## Golden rule

### never crash (outrank feature work)

Malformed inputs, missing files or tools,
permission problems, and failed subprocesses must produce an actionable error,
not terminate through a Swift trap. Do not add a crash path; fix existing
crash paths before building on them.

- Avoid force unwraps, `try!`, forced casts, implicitly unwrapped optionals,
  `fatalError`, `precondition`, and `assert`-based control flow in shipped
  sources. Validate assumptions and propagate typed or otherwise explicit
  errors.
- Treat AppDirs, AppImages, runtimes, assets, and filesystem paths as external
  input. Check file types, paths, permissions, sizes, and format requirements
  before use. Do not silently substitute defaults for invalid input.
- Check subprocess launch and exit status. Include useful diagnostics when an
  external tool fails; do not report success after partial work.
- Build outputs in temporary locations and publish them only when complete.
  On failure, clean up temporary files and report cleanup failures rather than
  hiding them.
- Add a focused regression test for each crash or invalid-input fix. Keep
  failures isolated and never let one bad input leave a partial final bundle
  or image.

## Code and tests

- Follow the repository's Swift conventions and nearby code. Prefer clear,
  small operations, typed errors, and explicit validation.
- Use Swift Testing (`import Testing`, `@Test`) for new tests. Cover successful
  CLI/build/bundle behavior and important invalid-input and subprocess errors.
- Add comments only when they clarify a non-obvious invariant or public
  contract. Document public APIs where the code is intended for reuse.
- Keep the READMEs accurate when commands, bundle layout, dependencies, or
  setup steps change.
- Do not add application payloads, credentials, or unrelated build artifacts
  to the repository.

## Build and validation

Run checks for the package you changed:

```sh
swift test --package-path AppSmith
swift build -c release --package-path AppSmith
swift build --package-path TestApp
```

Shaft's Linux build requires native development headers and libraries for its
SDL3/Skia backend. If the user is on a Fedora Atomic or other Atomic distro,
suggest using Distrobox paired with Podman for `TestApp` development rather
than layering build dependencies onto the host. If those dependencies are
unavailable, report the limitation; do not claim TestApp built or ran.

Before finishing, inspect `git diff --check`, review the complete diff, and
report the commands that passed and any checks blocked by missing dependencies.

## Commit attribution

If Kilo authored the changes, append `Co-authored-by: Kilo <kilo@local>` to
the commit message, in the same area as other `Co-authored-by` trailers. Do
not invent or impose attribution when Kilo did not author the changes.
