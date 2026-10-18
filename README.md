# DotAppImage

DotAppImage is an experimental Linux packaging project exploring a
directory-based `.app` experience backed by AppImages. A bundle keeps its
AppImage payload, metadata, icon, and assets together, while a launcher runs
the payload.

The repository contains two independent Swift packages:

| Directory | Purpose |
| --- | --- |
| [`DotAppImage/`](./DotAppImage/) | CLI for building Type 2 AppImages from prepared AppDirs, wrapping existing AppImages in `.app` bundles, and launching bundles. |
| [`TestApp/`](./TestApp/) | Small [Shaft](https://github.com/ShaftUI/Shaft) desktop app and AppDir template used to exercise the workflow. |

## Requirements

- Linux
- Swift 6.3 or newer for the DotAppImage CLI
- For `dotappimage build`: `mksquashfs` and a Type 2 AppImage runtime matching the target architecture
- For TestApp: Shaft's Linux development dependencies for SDL3 and Skia

On Fedora Atomic and other immutable Linux distributions, use Distrobox with
Podman (or Toolbx) to install TestApp's development dependencies in a
container rather than layering them onto the host.

## Quick start

Build and test the CLI:

```sh
swift test --package-path DotAppImage
swift run --package-path DotAppImage dotappimage --help
```

Create a bundle from an existing AppImage:

```sh
swift run --package-path DotAppImage dotappimage bundle \
  --name "Sample App" \
  --identifier "dev.example.sample" \
  --version "1.0.0" \
  --appimage ./Sample.AppImage \
  --output ./Sample.app
```

Launch the bundle:

```sh
swift run --package-path DotAppImage dotappimage open ./Sample.app
```

Register and remove the bundle for the current user:

```sh
dotappimage install ./Sample.app
dotappimage uninstall ./Sample.app
```

`bundle` works with an existing AppImage; building an AppImage is a separate
step. See the [CLI guide](./DotAppImage/README.md) for command details and the
[TestApp guide](./TestApp/README.md) for the complete example workflow.

## Current scope

DotAppImage builds a Type 2 image from an AppDir that the app developer has
already assembled. It does not discover or bundle shared-library
dependencies. The current TestApp example still relies on host SDL, graphics,
font, and desktop libraries, so a successful build does not imply that the
image is portable to other Linux systems.

The generated `.app` bundle contains an AppImage and metadata. Installation
adds a symlink to the bundle's desktop entry under
`$XDG_DATA_HOME/applications` (or `~/.local/share/applications` when
`XDG_DATA_HOME` is unset). The bundle must remain at the same path while
installed. The `dotappimage` executable must be available in the desktop
session's `PATH`.

## Contributing

Choose the package that owns the behavior you are changing. Add or update
focused tests with code changes, run that package's test suite, and update its
README when commands or requirements change. Keep generated AppDirs, AppImages,
and `.app` bundles in `.build/` rather than checking them in.

For changes to the CLI:

```sh
swift test --package-path DotAppImage
```

For changes to the GUI example, build it in an environment with Shaft's Linux
development dependencies:

```sh
swift build --package-path TestApp
```
