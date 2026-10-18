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
- For `dependencies`, `lddtree` from the `pax-utils` package

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

## Inspect ELF dependencies

Before preparing or shipping an AppDir, inspect an executable's recursive
dynamic dependencies:

```sh
swift run --package-path DotAppImage dotappimage dependencies \
  --appdir ./Sample.AppDir \
  --executable usr/bin/Sample
```

Install `pax-utils` to provide `lddtree` (for example, `sudo dnf install
pax-utils` on Fedora or `sudo apt install pax-utils` on Debian/Ubuntu).
`--executable` may be relative to the AppDir or an absolute path inside it.
The report separates dependencies found in the AppDir, dependencies resolved
from the build host, and unresolved libraries. It also lists same-named
dependency files found in the AppDir, even when the host resolver selects
another path; those files may need to be added to the launcher's library
search path.

This is a static ELF dependency report, not a portability guarantee. It uses
the host's library search configuration to resolve dependencies. Libraries
loaded dynamically at runtime, such as plugins opened with `dlopen`, are not
discovered. Host-resolved libraries are not automatically copied into the
AppDir.

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

Arguments after the bundle path are forwarded to the AppRun launcher.

## Install and uninstall a bundle

Install the bundle's desktop entry for the current user:

```sh
dotappimage install ./Sample.app
```

This creates a symlink to the `.desktop` file inside the bundle under
`$XDG_DATA_HOME/applications`, or `~/.local/share/applications` if
`XDG_DATA_HOME` is not set. The desktop entry uses the bundled name, icon, and
metadata, and launches the app using `dotappimage open`. Make sure the
`dotappimage` executable is on the desktop session's `PATH`.

Remove the registration without deleting the bundle:

```sh
dotappimage uninstall ./Sample.app
```

The commands do not overwrite unrelated desktop entries. Keep the bundle at
the same path while it is installed; its desktop entry contains absolute paths
to the bundle and icon.

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
bundle and icon paths based on the output location; if the bundle is moved,
those paths are stale.

## Develop and test

```sh
swift test --package-path DotAppImage
swift build -c release --package-path DotAppImage
```

Tests use Swift Testing and cover CLI parsing, AppImage assembly, bundle
contents, and launcher behavior.
