# DotAppImage

DotAppImage is a Linux CLI for creating `.app` directory bundles that carry an
AppImage as their Linux executable payload. It does not convert the bundle into
a single AppImage or collect shared libraries; those concerns belong to the
AppImage being wrapped.

## Create a bundle

Build with Swift 6.3 or newer, then run:

```sh
swift run dotappimage create \
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
