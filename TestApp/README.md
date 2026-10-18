# TestApp

TestApp is a small [Shaft](https://github.com/ShaftUI/Shaft) desktop
application used to test DotAppImage with a real GUI executable. It is a
development fixture, not a portable end-user application: its AppDir currently
uses host SDL, graphics, font, and desktop libraries.

## Build and run the application

Install the Linux development dependencies required by Shaft's SDL3 and Skia
backends, following [Shaft's setup instructions](https://github.com/ShaftUI/Shaft).
Then build and run TestApp:

```sh
swift build
swift run
```

On Fedora Atomic or another immutable Linux distribution, use Distrobox with
Podman (or Toolbx) for these development dependencies instead of layering them
onto the host.

When running under Wayland with an X11 display available, the AppDir launcher
defaults SDL to its X11 video driver to work around the current Shaft/Skia
Wayland rendering issue. An explicitly set `SDL_VIDEODRIVER` takes precedence.
The launcher also adds the bundled Swift libraries to the dynamic loader's
search path when they are present.

## Build an AppDir

Run these commands from the `TestApp/` directory after building the app. The
AppDir is the directory that will become the root of the AppImage filesystem:

```sh
cp -R AppDir .build/TestApp.AppDir
mkdir -p .build/TestApp.AppDir/usr/bin
cp .build/debug/TestApp .build/TestApp.AppDir/usr/bin/TestApp
cp -a .build/x86_64-unknown-linux-gnu/debug/Shaft_CSkiaResource.resources \
  .build/TestApp.AppDir/usr/bin/
```

Swift executables also need the runtime libraries from the same Swift toolchain
used to build them. Set `SWIFT_TOOLCHAIN_USR` to that toolchain's `usr`
directory, then copy the libraries into the AppDir. For example, adjust this
path for the Swift toolchain installed on your system:

```sh
export SWIFT_TOOLCHAIN_USR=/path/to/swift-toolchain/usr
mkdir -p .build/TestApp.AppDir/usr/lib/swift/linux
cp -a "$SWIFT_TOOLCHAIN_USR/lib/swift/linux/." \
  .build/TestApp.AppDir/usr/lib/swift/linux/
```

The AppDir template's `AppRun` starts `usr/bin/TestApp`. This is distinct from
the launcher created at the root of a generated `.app` bundle: that bundle
launcher starts its `Contents/Linux/AppImage` payload.

## Build, bundle, and launch

Obtain a trusted AppImage Type 2 runtime for the target architecture. Then
build an AppImage from the prepared AppDir:

```sh
swift run --package-path ../DotAppImage dotappimage build \
  --appdir .build/TestApp.AppDir \
  --runtime /path/to/runtime-x86_64 \
  --output .build/TestApp.AppImage
```

Wrap the image in a `.app` directory bundle:

```sh
swift run --package-path ../DotAppImage dotappimage bundle \
  --name "DotAppImage TestApp" \
  --identifier "dev.dotappimage.testapp" \
  --version "0.1.0" \
  --appimage .build/TestApp.AppImage \
  --icon AppDir/TestApp.svg \
  --output .build/TestApp.app
```

Launch it through DotAppImage:

```sh
swift run --package-path ../DotAppImage dotappimage open .build/TestApp.app
```

To add the app to the current user's desktop applications menu, first make
sure the `dotappimage` executable is installed in the desktop session's
`PATH`, then run:

```sh
dotappimage install .build/TestApp.app
```

Remove the desktop entry without deleting the bundle:

```sh
dotappimage uninstall .build/TestApp.app
```

The `.build/` directory is SwiftPM's ignored build-output directory and keeps
generated AppDirs, AppImages, and bundles out of source control.

## Packaging limitations

The sample bundles Swift runtime libraries and Shaft's resource bundle, but
does not collect SDL, graphics, font, or other system-library dependencies.
The resulting AppImage is useful for testing the build and bundle commands on
the development system; it is not expected to run portably across Linux
distributions yet.
