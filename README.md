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

## Agent and CLI workflow

Agents can create and export projects without operating the desktop editor. Read [`SKILL.md`](SKILL.md) for the manifest workflow and supported widgets. The versioned JSON format is described by [`schema/appbuilder.schema.json`](schema/appbuilder.schema.json), with a working [example project](examples/hello_world.appbuilder.json).

```powershell
dart run bin/app_builder.dart init .\my_app.appbuilder.json --name "My App"
dart run bin/app_builder.dart validate .\my_app.appbuilder.json --json
dart run bin/app_builder.dart inspect .\my_app.appbuilder.json --json
dart run bin/app_builder.dart database .\my_app.appbuilder.json add-collection --id tasks --name Tasks
dart run bin/app_builder.dart database .\my_app.appbuilder.json add-field --collection tasks --id title --name Title --required
dart run bin/app_builder.dart database .\my_app.appbuilder.json list --json
dart run bin/app_builder.dart export .\my_app.appbuilder.json --output .\my_app
```

The CLI consumes the same project model and Dart generator as the editor. The `database` command can add and remove collections, typed fields, relationships, and seed records in the manifest; run `dart run bin/app_builder.dart help` for its options. Export creates a new Flutter project directory using the locally installed Flutter SDK; the destination must not already exist. It scaffolds platform files with `flutter create --no-pub` and does not resolve packages.

Exported apps use Flutter's official `material_ui` package and require Flutter 3.47 or later (Dart 3.13 or later).

## Prototype workflow

1. Select a widget in the left tree or preview canvas to show its properties in the inspector.
2. Drag a component from **Add to canvas** onto the canvas or into a compatible widget in the tree. Clicking a component adds it to the selected layout (or the first Column). The layout palette includes **Scroll View**, **Center**, **Align**, **Wrap**, **Sized Box**, **Aspect Ratio**, **Clip RRect**, **Flexible**, and **Spacer**. Save component subtrees as reusable groups, then insert them again from the **Reusable Groups** palette section.
3. Drag tree rows onto a Column, Row, Container, or Scaffold to nest them. Drop on the narrow highlighted lines above or below a row to reorder it among its siblings.
4. Search the inspector's collapsible property groups. Edit per-side padding and margin with linked or independent edges, visibility, opacity, size, alignment, typography, colors, corner radius, and button style. Responsive sizing can fill available width or height, or use quarter, half, and three-quarter parent dimensions. Color fields support the visual picker and HEX, RGB, HSL, and alpha input.
5. Use the inspector's **Theme** section to set the app's seed color, light/dark/device appearance, font family, corner radius, background, and text color. Import `.ttf` or `.otf` files to preview and bundle fonts with the exported Flutter project.
6. Save any selected component and its descendants as a reusable group with **Save as reusable group**. Inserting a saved group creates an editable copy; resize the group wrapper in the inspector.
7. Create Dart classes, enums, and typedefs through **Resources → Data types**. These declarations are available to custom functions and exported apps. Use JSON variables and `fromJson()` / `toJson()` in custom functions to convert between maps and your Dart types.
8. Create on-device data collections through **Resources → Database**. Define typed fields, primary and unique keys, and relationships between foreign-key fields and parent keys; many-to-many models use a join collection. Record JSON uses field IDs as keys. Configure **Load database records** with related collections, left or inner joins, field conditions, AND/OR matching, sorting, and a row limit. Joined rows are nested under the selected result key: one-to-one joins return an object or `null`, and one-to-many joins return a list. Conditions and sorting can use fields from the base or joined collection; sorting a one-to-many result uses its lowest or highest related value. Queries support direct relationships from their base collection. Optionally provide starter records as a JSON array. Add a **Database List** widget and choose its collection to repeat child widgets for each record. Use `${record.fieldId}` in text and `${record._id}` as the record ID in row actions. Bind a text field to a string app variable to collect input. Add **Save database record**, **Update database record**, **Load database records**, or **Delete database record** actions to interactive components. An insert adds a row to the repeated list, an update refreshes that row's displayed values, and a delete removes it. The preview simulates collection changes in memory; exported apps persist records locally with Sembast (IndexedDB on web). Starter records are inserted once for each collection on first launch.
9. Add actions to buttons and other interactive widgets. Actions can use if/else branches, repeat a nested action list up to 1,000 times, send GET, POST, PUT, PATCH, and DELETE requests, or call reusable custom functions. Use app variables in record JSON, such as `{"title":"$newTodo"}`, and use `${record.fieldId}` in actions inside a Database List item. Custom functions can use typed Dart statements or built-in action steps. Typed functions run in the canvas preview using an interpreter with common Dart core, math, and JSON APIs; use `getVariable`, `setVariable`, `showMessage`, `navigateTo`, `back`, and `print` to interact with the canvas preview. Choose **Flutter Preview** to run the current project in the full Flutter runtime, where custom functions can use Material widgets and `BuildContext` APIs. Material is imported automatically; leading import lines in a custom function are moved to the generated file's import section. Flutter Preview launches a temporary export on a selected Flutter device, window, or browser, and removes the temporary files after you stop it. HTTP responses can be saved to an app variable. Use `${variableId}` or `$variableName` in request URLs, headers, and bodies to insert app state.
10. Save a new `.appbuilder.json` project by choosing its folder; the file name is based on the project name. Open existing projects through the native file picker.
11. Set optional phone, tablet, and desktop property overrides in the inspector. Preview the current breakpoint by changing the canvas viewport size; generated apps select the matching overrides at runtime.
12. Choose **Validate project** to check routes, widget nesting, actions, assets, accessibility labels, and generated Dart syntax before export. Select a reported issue to jump to its page or widget.
13. Choose **Export Flutter App**, then select a parent folder. The builder creates the Flutter project in a new subfolder based on the project name, using the local Flutter CLI to create Android, iOS, web, Windows, macOS, and Linux runners before writing the app source, manifest, readme, smoke test, and copied image and font assets.
14. Open **Run / Build** after export to resolve packages online or from the local cache, run on a connected device, analyze the generated app, or build a selected target. The workflow defaults to offline package resolution.

Keyboard shortcuts include Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z for undo and redo, Ctrl/Cmd+D to duplicate, Ctrl/Cmd+C/X/V to copy/cut/paste widget subtrees, Delete to remove, and Up/Down to navigate the selected tree when the canvas or tree has focus. At narrow window sizes, the component and inspector panels open as compact dialogs.

When you save a project, referenced images and bundled fonts are copied into a neighboring asset folder and stored with relative paths, so the project can move with its assets. Saved projects also keep a recovery copy after edits; reopening a project restores that copy when it is newer than the main file. The first save still sets the project folder.

The builder project manifest is versioned JSON. Generated apps use Flutter Material widgets and do not depend on a proprietary runtime package. HTTP actions run only when the user triggers them in the preview or running app. Exported projects include the `http` package when an HTTP action is configured or typed custom code references `http.`. Exported projects with database collections include `sembast`, `sembast_web`, `path_provider`, and `path`. The editor uses `provider` for state, `file_selector` for project folders, and `dart_eval` to interpret custom functions in preview.
