# DotAppImage

This repository contains two independent Swift packages:

- [`DotAppImage/`](./DotAppImage/) builds Type 2 AppImages from prepared AppDirs
  and wraps existing AppImages in Linux `.app` directory bundles.
- [`TestApp/`](./TestApp/) is a small [Shaft](https://github.com/ShaftUI/Shaft)
  desktop application used to exercise the build and bundle workflow.

Build the CLI from its package directory:

```sh
cd DotAppImage
swift test
swift run dotappimage --help
```

Build and run the GUI test app:

```sh
cd TestApp
swift run
```

Shaft uses SDL3 and Skia on Linux. Building it requires the native Linux
development dependencies documented by [Shaft](https://github.com/ShaftUI/Shaft).
On immutable distributions such as Fedora Atomic desktops, a development
container such as Toolbx or Distrobox can provide these dependencies without
layering them onto the host system.
