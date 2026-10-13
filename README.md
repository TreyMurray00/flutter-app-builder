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
2. Drag a component from **Add to canvas** onto the canvas or into a compatible widget in the tree. Clicking a component adds it to the selected layout (or the first Column). Save component subtrees as reusable groups, then insert them again from the **Reusable Groups** palette section.
3. Drag tree rows onto a Column, Row, Container, or Scaffold to nest them. Drop on the narrow highlighted lines above or below a row to reorder it among its siblings.
4. Search the inspector's collapsible property groups. Edit per-side padding and margin with linked or independent edges, visibility, opacity, size, alignment, typography, colors, corner radius, and button style. Responsive sizing can fill available width or height, or use quarter, half, and three-quarter parent dimensions. Color fields support the visual picker and HEX, RGB, HSL, and alpha input.
5. Use the inspector's **Theme** section to set the app's seed color, light/dark/device appearance, font family, corner radius, background, and text color. The preview and exported app share these settings. Custom font families must be installed or bundled separately in the exported Flutter project.
6. Save any selected component and its descendants as a reusable group with **Save as reusable group**. Inserting a saved group creates an editable copy; resize the group wrapper in the inspector.
7. Create Dart classes, enums, and typedefs through **Resources → Data types**. These declarations are available to custom functions and exported apps. Use JSON variables and `fromJson()` / `toJson()` in custom functions to convert between maps and your Dart types.
8. Create on-device data collections through **Resources → Database**. Optionally provide starter records as a JSON array. Add **Save record**, **Load records**, or **Delete record** actions to interactive components or custom functions. Load records into a JSON variable. Record IDs appear as `_id` and can be used by delete actions. The preview simulates collections in memory; exported apps persist them locally with Sembast (IndexedDB on web). Starter records are inserted once for each collection on first launch.
9. Add actions to buttons and other interactive widgets. Actions can use if/else branches, repeat a nested action list up to 1,000 times, send GET, POST, PUT, PATCH, and DELETE requests, or call reusable custom functions. Custom functions can use typed Dart statements or built-in action steps. Typed functions run in the preview using an interpreter with common Dart core, math, and JSON APIs; use `getVariable`, `setVariable`, `showMessage`, `navigateTo`, `back`, and `print` to interact with the preview. External packages and direct Flutter context APIs are available only in exported apps. HTTP responses can be saved to an app variable. Use `${variableId}` or `$variableName` in request URLs, headers, and bodies to insert app state.
10. Save a new `.appbuilder.json` project by choosing its folder; the file name is based on the project name. Open existing projects through the native file picker.
11. Choose **Export Flutter App**, then select a parent folder. The builder creates the Flutter project in a new subfolder based on the project name, using the local Flutter CLI to create Android, iOS, web, Windows, macOS, and Linux runners before writing the app source, manifest, readme, smoke test, and copied image assets.

The builder project manifest is versioned JSON. Generated apps use Flutter Material widgets and do not depend on a proprietary runtime package. HTTP actions run only when the user triggers them in the preview or running app. Exported projects include the `http` package when an HTTP action is configured or typed custom code references `http.`. Exported projects with database collections include `sembast`, `sembast_web`, `path_provider`, and `path`. The editor uses `provider` for state, `file_selector` for project folders, and `dart_eval` to interpret custom functions in preview.
