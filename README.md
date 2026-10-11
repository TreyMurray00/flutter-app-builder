# Local Flutter Builder

A local-first visual editor for Flutter apps. It includes a nested widget tree, a responsive preview canvas, drag-and-drop layout editing, per-widget property controls, undo/redo, local JSON project files, and complete Flutter project export.

## Requirements

- Flutter stable with Dart 3.7 or newer.
- The Flutter packages in `pubspec.yaml` available in the local Pub cache. Initial dependency resolution may require access to pub.dev; the editor itself has no account or hosted service.
- Flutter available on `PATH` or through `FLUTTER_ROOT` to export a project.
- A desktop build toolchain for the operating system you want to run on.

On Windows, install Visual Studio with its **Desktop development with C++** workload before building a Windows binary.

## Run locally

The Windows, macOS, and Linux runner folders are included. From this directory, run:

```powershell
flutter pub get --offline
flutter run -d windows
```

Use `-d macos` or `-d linux` on the corresponding host. After package dependencies have been cached, Flutter supports local/offline work with the installed SDK and packages.

## Prototype workflow

1. Select a widget in the left tree or preview canvas to show its properties in the inspector.
2. Drag a component from **Add to canvas** onto the canvas or into a compatible widget in the tree. Clicking a component adds it to the selected layout (or the first Column).
3. Drag tree rows onto a Column, Row, Container, or Scaffold to nest them. Drop on the narrow highlighted lines above or below a row to reorder it among its siblings.
4. Search the inspector's collapsible property groups. Edit per-side padding and margin with linked or independent edges, visibility, opacity, size, alignment, typography, colors, corner radius, and button style. Color fields support the visual picker and HEX, RGB, HSL, and alpha input.
5. Save/open `.appbuilder.json` project files by entering their full local path.
6. Choose **Export Flutter App** and enter a new folder path. The builder uses the local Flutter CLI to create Android, iOS, web, Windows, macOS, and Linux runners, then writes the app source, manifest, readme, smoke test, and copied image assets.

The builder project manifest is versioned JSON. Generated apps use Flutter Material widgets and only the Flutter SDK plus `flutter_test`; they do not depend on a proprietary runtime package. The editor makes no network calls; the only external package is `provider`, used for local dependency injection.
