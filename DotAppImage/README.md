# DotAppImage CLI

DotAppImage is a Linux command-line tool for creating Type 2 AppImages from
prepared AppDirs and wrapping existing AppImages in `.app` directory
bundles. Building and bundling are separate operations, so an existing
AppImage can be bundled without rebuilding its payload.

## Requirements

- Swift 6.3 or newer
- Linux
- For `build`, `mksquashfs` in `PATH` and a Type 2 AppImage runtime for the
  target architecture

Run the CLI with SwiftPM from the repository root:

```sh
swift run --package-path DotAppImage dotappimage --help
```

## Build an AppImage

First prepare an AppDir containing the application, its resources, required
libraries, and an executable `AppRun` at the AppDir root. The AppRun script is
the entry point used when the generated image starts.

```text
Sample.AppDir/
├── AppRun
├── Sample.desktop
├── Sample.png
└── usr/
    ├── bin/
    │   └── Sample
    └── lib/
        └── ...
```

Then build the image:

```sh
swift run --package-path DotAppImage dotappimage build \
  --appdir ./Sample.AppDir \
  --runtime ./runtime-x86_64 \
  --output ./Sample.AppImage
```

The command creates a SquashFS filesystem with `mksquashfs`, appends it to the
supplied Type 2 runtime, and marks the result executable. Use a trusted runtime
that matches the target architecture. The AppDir and its dependencies are the
application developer's responsibility. DotAppImage refuses to overwrite an
existing output.

## Bundle an existing AppImage

```sh
swift run --package-path DotAppImage dotappimage bundle \
  --name "Sample App" \
  --identifier "dev.example.sample" \
  --version "1.0.0" \
  --appimage ./Sample.AppImage \
  --icon ./sample.png \
  --asset ./defaults.json \
  --output ./Sample.app
```

`--icon` and `--asset` are optional. Repeat `--asset` to add more files or
directories. Asset names must be unique in the bundle. The command does not
replace an existing output bundle.

## Open a bundle

Launch a bundle using the CLI:

```sh
swift run --package-path DotAppImage dotappimage open ./Sample.app
```

`open` checks that the path is a directory containing an executable `AppRun`,
then starts it without waiting for the application to exit. A bundle can also
be launched directly:

```sh
./Sample.app/AppRun
```

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

`Contents/Manifest.json` is the versioned metadata source. Manifest paths are
relative to the bundle root. The desktop entry is generated with absolute
launcher and icon paths based on the output location; if the bundle is moved,
those paths are stale. The command does not install the bundle or register the
desktop entry with the user's desktop environment.

## Develop and test

```sh
swift test --package-path DotAppImage
swift build -c release --package-path DotAppImage
```

Tests use Swift Testing and cover CLI parsing, AppImage assembly, bundle
contents, and launcher behavior.
