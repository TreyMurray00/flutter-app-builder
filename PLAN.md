# Local Flutter App Builder — Product and Technical Plan

## Product goal

Build a desktop visual app builder inspired by FlutterFlow that lets one person design, preview, run, and export real Flutter applications entirely on their own computer. Projects remain ordinary folders the user owns. No account, hosted editor, cloud database, mandatory network call, telemetry, or vendor lock-in is part of the product.

### Working assumptions

- The builder is a local desktop application for Windows, macOS, and Linux.
- Generated applications use Flutter and Dart and can target Flutter-supported platforms when the matching local SDKs are installed.
- The user provides Flutter and any platform toolchains. The builder detects them and explains what is missing; it does not download SDKs or packages in the background.
- “Completely local” applies to the builder and its core workflow. The first release generates apps with local state and assets only. Optional network-backed app features are a later, explicit choice.
- The product is a visual starting point for code-owning developers. Generated code is readable and editable; arbitrary hand-edited code is not silently overwritten by future visual edits.

## Who it is for

Indie developers, students, and small teams who want a visual way to lay out Flutter screens and connect basic interactions, while keeping their source code and build process local and under their control.

## Core workflow

1. Create a project in a chosen local folder, or open an existing builder project.
2. Add pages and place components from a palette onto a responsive canvas.
3. Select a component to edit its properties, styling, layout, and actions.
4. Preview common phone, tablet, and desktop widths from the saved design model.
5. Run the generated Flutter project using a locally installed Flutter SDK and a local simulator/device.
6. Export or continue editing the generated Flutter source in any code editor.

## MVP scope

### Include

- A multi-page project with a page tree and navigation routes.
- Drag-and-drop widget palette and a nested widget tree with selection, reorder, duplicate, and delete.
- A properties panel for common layout, typography, color, spacing, alignment, and decoration options.
- A canvas with phone, tablet, and desktop breakpoints; resize preview without changing the saved project.
- Components: Scaffold, SafeArea, Container, Column, Row, Stack, Expanded, Padding, Text, Icon, Image, Button, TextField, Card, Divider, and ListView.
- Theme tokens for colors, text styles, and corner radii.
- Basic interactions: navigate, go back, show snackbar, update local app/page state, and validate required text input.
- Import images and fonts from the local filesystem and copy them into the project.
- Project save/open, autosave, undo/redo, and a recoverable local backup.
- Flutter code generation, code view/open-folder action, and local run/build commands with visible logs.
- A setup screen that reports Flutter, Dart, and target toolchain availability without downloading anything.

### Leave for later

- Cloud authentication, hosted databases, online project sync, collaboration, marketplace, and analytics.
- Arbitrary custom Dart widgets rendered inside the visual editor.
- A visual backend/schema designer, API client, or package marketplace.
- One-click publishing, signing, store uploads, or remote builds.
- Full round-trip import and visual editing of arbitrary Flutter repositories.
- AI-generated screens or code.

## Recommended implementation stack

### Primary recommendation

- **Builder UI and runtime:** Flutter stable for Windows, macOS, and Linux; Dart 3. Flutter officially supports native desktop builds on those three platforms. Using Flutter for the editor keeps canvas rendering in Flutter's layout and rendering system, close to the generated apps' actual platform and widget behavior.
- **Application architecture:** Feature-oriented MVVM with UI and data layers, repositories for project files/toolchain/preferences, and small services for filesystem and process work. Keep domain/use-case layers only for workflows that need them.
- **Editor state:** Typed immutable project/page/widget models. Use command-based edits (`insert`, `move`, `update property`, `delete`) with an undo/redo history. Use `ChangeNotifier`/`Listenable` or `ValueNotifier` at document and selected-subtree boundaries so one property edit does not rebuild the entire editor. Use `provider` for dependency injection; avoid introducing multiple state-management systems.
- **Persistence:** Versioned JSON manifest plus normal asset files, saved with temp-file-and-rename writes and a rotating recovery copy. Start without SQLite; add it only if measured project indexing or history needs call for it.
- **Desktop integration:** `file_selector` for native open/save/import dialogs; Dart `dart:io` for project-local filesystem work. Keep the initial plugin list small and verify that each plugin supports all desktop targets the product claims.
- **Flutter toolchain:** Detect a user-selected or discovered Flutter SDK and invoke it by absolute executable path. Use `dart:io Process.start` asynchronously with an argument list, explicit working directory, streamed stdout/stderr, retained exit code, and cancellation. Do not shell-concatenate commands or run the process synchronously.
- **Code generation:** A typed widget registry and deterministic Dart emitter, with one emitter per supported widget/action. Escape user strings as Dart literals, then run the local `dart format` and `flutter analyze` commands. Track generated-file checksums and refuse silent overwrite of hand-edited generated files.
- **Generated app:** Ordinary Flutter/Dart source with the Flutter SDK and Flutter's built-in Material/Cupertino libraries only in the first release. The editor itself may use a small pinned plugin set; the apps it generates should not require a proprietary runtime package.
- **Quality tools:** Pin one exact Flutter stable release for each builder release; use `flutter_lints`, `flutter_test`, and CI builds on each supported desktop OS. Add fixture projects for generation and preview parity.

Flutter's architecture guidance recommends distinct UI/data layers, views and view models, repositories, immutable models, and unidirectional data flow. It conditionally recommends `ChangeNotifier`/`Listenable`, making them a reasonable low-dependency fit for the editor. Dart's `Process.start` supports asynchronous streams and explicit working directories for running the local Flutter CLI. [Architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) · [Dart `Process.start`](https://api.dart.dev/dart-io/Process/start.html)

### Code generation and editor boundaries

- Define a typed component registry: each node type declares editor controls, validation, preview rendering, and code-generation behavior.
- Render the canvas from the same node model that code generation consumes, avoiding separate design and output interpretations.
- Generate deterministic Dart source: stable formatting, stable IDs, predictable ordering, and no timestamp churn.
- Keep generated Flutter source idiomatic and understandable. Do not hide app logic in an opaque binary or require a proprietary runtime package.
- Start with full generation from the model. Add per-file ownership and drift detection before adding complex round-trip editing.

### Project model

Store a versioned design document (for example, `appbuilder.json`) with:

- Project metadata and schema version.
- Pages and navigation order.
- A stable-ID node tree per page, with widget type, typed properties, child IDs, layout constraints, and optional action bindings.
- Theme tokens and breakpoints.
- Local app state declarations and asset references.
- Generator version and per-file ownership metadata.

Keep content and generated source separate. The design document is authoritative for files explicitly marked as generated. Before replacing a generated file, compare it with the last generated checksum; if it changed by hand, preserve it and show a clear conflict/reconciliation choice. Prefer extension points such as custom Dart files and named custom-code hooks over regenerating user-owned files.

### Local execution boundaries

- Store projects only in the folder selected by the user, plus documented local app settings/cache locations.
- No sign-in, network calls, telemetry, or remote assets in the builder's core workflow.
- Do not execute code from an opened project automatically. Running a project is a deliberate user action and displays the command and target.
- Show whether a build action can invoke package resolution or access the network. Default MVP builds to local SDK dependencies and offline behavior where supported.
- Provide project export as a plain directory and optional archive; provide a manifest and assets that are independently readable.

Flutter's official setup flow expects Flutter to be installed before project creation, and its project architecture guidance emphasizes separating UI and data responsibilities. These fit a local toolchain check and a model-driven editor. [Create a Flutter app](https://docs.flutter.dev/reference/create-new-app) · [Flutter app architecture](https://docs.flutter.dev/app-architecture/guide)

## Editor layout

```text
┌──────────────────────────────────────────────────────────────────┐
│ Project / undo / redo / device size / preview / run / build       │
├─────────────┬──────────────────────────────┬───────────────────────┤
│ Components  │                              │ Properties / Actions │
│ Pages       │       Responsive canvas     │ Theme / bindings     │
│ Widget tree │                              │                       │
├─────────────┴──────────────────────────────┴───────────────────────┤
│ Build and run output / diagnostics / toolchain status             │
└──────────────────────────────────────────────────────────────────┘
```

## Delivery plan

### Phase 0 — Validate foundations

- Confirm the target operating systems and supported Flutter targets.
- Prototype the versioned design model, a small component registry, canvas rendering, and deterministic Dart generation.
- Check that Flutter toolchain detection works without network access.
- Decide how generated-file drift is shown before expanding the component set.

**Exit condition:** A tiny project can be created, saved, reopened, rendered on the canvas, generated into a Flutter project, and run locally from the same model.

### Phase 1 — Usable visual editor

- Build the desktop shell, project lifecycle, autosave, undo/redo, page list, component palette, widget tree, and property inspector.
- Implement the MVP component set and responsive preview sizes.
- Add local image/font import and theme tokens.

**Exit condition:** A user can produce a polished static multi-page layout without editing Dart.

### Phase 2 — Interaction and generated Flutter app

- Add routes, basic actions, local state, and form validation to the model and preview.
- Generate an idiomatic, runnable Flutter app with matching behavior.
- Add code view/open-folder and file ownership/drift warnings.

**Exit condition:** A simple interactive app behaves consistently in preview and in the generated Flutter project.

### Phase 3 — Local run/build workflow

- Add toolchain discovery, target selection, run/stop, build commands, and streaming diagnostics.
- Handle missing SDKs, unavailable devices, build errors, cancellation, and offline dependency failures in plain language.
- Document local project backups and recovery.

**Exit condition:** A fresh install with a preinstalled toolchain can build and launch a sample app with no builder account or hosted service.

### Phase 4 — Stabilize and expand

- Add schema migrations, accessibility controls, keyboard workflows, and larger-project performance improvements.
- Expand components and custom code extension points based on actual use.
- Consider a local plugin mechanism only after the core component registry is stable.

**Exit condition:** Projects survive upgrades and can be moved, backed up, and built outside the visual editor.

## Main risks and responses

| Risk | Response |
|---|---|
| Visual preview differs from Flutter output | Use one typed model and component registry for canvas rendering and source generation; compare representative screens during development. |
| Hand edits are overwritten | Track generated ownership and checksums; stop and surface a conflict before replacing changed files. |
| “Offline” still triggers dependency downloads | Keep the default generator dependency-light, disclose any dependency resolution, and make unavailable local packages a clear build diagnostic. |
| Platform builds require additional SDKs | Detect each toolchain separately and show exactly which local install is required for each target. |
| The builder becomes too broad | Ship layout, navigation, local state, and local assets first; defer remote backend integrations and full repository import. |

## First concrete milestone

Implement a proof of concept with three widgets (`Scaffold`, `Column`, `Text`), one page, one theme token, a JSON project file, a live canvas, and deterministic Dart output. Verify that the generated project runs with the locally installed Flutter SDK while network access is disabled. Use this to settle the schema and generator boundaries before building the full editor.

## References

- [Flutter: Create a new app](https://docs.flutter.dev/reference/create-new-app)
- [Flutter: App architecture guide](https://docs.flutter.dev/app-architecture/guide)
- [SQLite file format](https://www.sqlite.org/fileformat.html) — relevant only if future project indexing justifies adding a local database.
