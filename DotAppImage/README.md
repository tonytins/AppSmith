# DotAppImage

DotAppImage is a Linux CLI for building Type 2 AppImages from prepared AppDirs
and wrapping AppImages in `.app` directory bundles. Building and bundling are
separate commands, so existing AppImages can be bundled without rebuilding.

## Build an AppImage

The `build` command requires an AppDir with an executable `AppRun`, an AppImage
Type 2 runtime ELF for the target architecture, and `mksquashfs` available in
`PATH`:

```sh
swift run dotappimage build \
  --appdir ./Sample.AppDir \
  --runtime ./runtime-x86_64 \
  --output ./Sample.AppImage
```

DotAppImage creates the SquashFS filesystem with `mksquashfs`, appends it to
the supplied runtime, and marks the resulting image executable. It does not
assemble the AppDir or collect the app's library dependencies. The runtime
must match the target architecture. Existing outputs are never overwritten.

## Bundle an existing AppImage

Build with Swift 6.3 or newer, then run:

```sh
swift run dotappimage bundle \
  --name "Sample App" \
  --identifier "dev.example.sample" \
  --version "1.0.0" \
  --appimage ./Sample.AppImage \
  --icon ./sample.png \
  --asset ./defaults.json \
  --output ./Sample.app
```

`--icon` and `--asset` are optional. Repeat `--asset` to include more files or
directories. Asset names must be unique within the bundle. The AppImage is
copied as `Contents/Linux/AppImage` and made executable. The tool refuses to
replace an existing output bundle.

Run the bundle directly with:

```sh
./Sample.app/AppRun
```

Or launch it through DotAppImage:

```sh
swift run dotappimage open ./Sample.app
```

The `open` command validates that the bundle contains an executable `AppRun`
and starts it without waiting for the app to exit.

The generated desktop entry is written inside the bundle. Its launch and icon
paths are absolute paths based on the output location at creation time; if the
bundle is moved, use `AppRun` directly or regenerate the bundle at its new
location.

## Bundle layout

```text
Sample.app/
├── AppRun
├── dev.example.sample.desktop
└── Contents/
    ├── Linux/
    │   └── AppImage
    ├── Manifest.json
    └── Resources/
        ├── AppIcon.png
        └── Assets/
            └── defaults.json
```

`Contents/Manifest.json` is the versioned, Linux-native metadata source. Paths
in the manifest are relative to the bundle root. The generated desktop entry
uses the app name, launcher path, and optional icon path.
