# TestApp

A small Linux desktop app built with [Shaft](https://github.com/ShaftUI/Shaft)
to test DotAppImage's AppDir, AppImage, and `.app` bundle workflows.

## Build and run

```sh
swift run
```

Shaft uses SDL3 and Skia on Linux. Follow Shaft's current Linux setup
instructions for native development dependencies. On Fedora Atomic desktops,
Toolbx or Distrobox can provide build dependencies inside a container.

## Create an AppDir

After building, SwiftPM places the executable at `.build/debug/TestApp`.
Copy the checked-in AppDir template and add the executable:

```sh
cp -R AppDir .build/TestApp.AppDir
mkdir -p .build/TestApp.AppDir/usr/bin
cp .build/debug/TestApp .build/TestApp.AppDir/usr/bin/TestApp
```

Then build and bundle it, supplying an AppImage Type 2 runtime for the target
architecture:

```sh
swift run --package-path ../DotAppImage dotappimage build \
  --appdir .build/TestApp.AppDir \
  --runtime /path/to/runtime-x86_64 \
  --output .build/TestApp.AppImage

swift run --package-path ../DotAppImage dotappimage bundle \
  --name "DotAppImage TestApp" \
  --identifier "dev.dotappimage.testapp" \
  --version "0.1.0" \
  --appimage .build/TestApp.AppImage \
  --icon AppDir/TestApp.svg \
  --output .build/TestApp.app
```

Run the resulting bundle with `.build/TestApp.app/AppRun`. This initial test
app exercises building and launching on the development system; it does not
yet assemble a portable dependency-complete AppDir.
