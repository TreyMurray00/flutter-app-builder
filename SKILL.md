---
name: local-flutter-builder
description: Create, edit, validate, inspect, and export Flutter apps using Local Flutter Builder project manifests and CLI.
---

# Local Flutter Builder app creation

Use this workflow when building an app with this repository's builder.

## Workflow

1. Create a project manifest with `dart run bin/app_builder.dart init <path>.appbuilder.json --name "App name"`, or edit an existing manifest.
2. Read the current manifest schema at [`schema/appbuilder.schema.json`](schema/appbuilder.schema.json) and use [`examples/hello_world.appbuilder.json`](examples/hello_world.appbuilder.json) as a concrete starting point.
3. Author the app in the manifest. Keep widget IDs unique within each page. Use stable IDs so actions can continue to target widgets after edits.
4. Run `dart run bin/app_builder.dart validate <manifest> --json`. Fix every error. Warnings identify widget children that may be ignored.
5. Use `dart run bin/app_builder.dart inspect <manifest> --json` to check the resulting page tree, state, and resources.
6. Export with `dart run bin/app_builder.dart export <manifest> --output <new-directory>`. The output directory must not already exist. Export uses the locally installed Flutter SDK and does not run `pub get`.
7. To compile or launch the generated app, change into the exported directory and use the user's installed Flutter toolchain, for example `flutter analyze` or `flutter run -d <device>`. Package resolution may access pub.dev unless the user requests offline operation.

Use absolute paths or quote paths containing spaces. The CLI accepts `--json` for machine-readable output on `init`, `validate`, `inspect`, and `export`.

## Project format

The design file is JSON with a `schemaVersion`, app `name`, `theme`, a home `root` widget, and optional `pages`, `variables`, `customFunctions`, `customDataStructures`, `componentGroups`, `databaseCollections`, and `initialPageId`. `root` and each page's `root` are recursive nodes:

```json
{
  "id": "home_column",
  "type": "column",
  "properties": { "mainAxisAlignment": "start", "crossAxisAlignment": "start" },
  "children": [
    { "id": "title", "type": "text", "properties": { "text": "Hello", "fontSize": 28 }, "children": [] }
  ]
}
```

Widget types supported by the generator are `scaffold`, `column`, `row`, `container`, `stack`, `listView`, `gridView`, `pageView`, `swipeableStack`, `card`, `padding`, `componentGroup`, `text`, `button`, `image`, `icon`, `divider`, `verticalDivider`, `textField`, `checkbox`, `switch`, `signature`, `appBar`, and `floatingActionButton`. Properties are JSON values; the generator reads the same property names used by the visual inspector. Unknown or malformed widget configurations are reported by `validate` when they prevent code generation.

The home page lives in the top-level `root`. Additional pages use `{ "id", "name", "route", "root" }` entries in `pages`. The home page ID is `home`. Routes must be unique. Node IDs should be unique on a page; actions use IDs to address variables, pages, widgets, functions, and database collections.

Assets such as images use paths relative to the manifest file. Keep those files beside the manifest or in a subfolder. Validation checks that referenced image files exist, and export copies them into the generated app.

For actions, put a list in a widget's `properties.actions`. Each action has an `id` and `type`; the supported types are `navigate`, `snackbar`, `dialog`, `back`, `setVariable`, `incrementVariable`, `toggleVariable`, `updateWidget`, `conditional`, `loop`, `httpRequest`, `databaseInsert`, `databaseQuery`, `databaseDelete`, and `customFunction`. Refer to [`lib/models/builder_action.dart`](lib/models/builder_action.dart) for the canonical defaults and nested action fields.

## CLI reference

```text
dart run bin/app_builder.dart init <file> [--name <name>] [--json]
dart run bin/app_builder.dart validate <file> [--json]
dart run bin/app_builder.dart inspect <file> [--json]
dart run bin/app_builder.dart export <file> --output <new-directory> [--json]
```

Exit status is `0` on success, `2` when validation finds project errors, `64` for invalid CLI usage, and `1` for an execution failure. In JSON mode, validation prints one object with `ok`, `path`, and `issues`; inspect prints a project summary; export prints `ok`, output `path`, and captured Flutter scaffold output. Failures print a JSON object with `ok: false` and an `error` or `issues` field.

When the builder's schema version changes, update the JSON schema and this guide. Keep the example manifest valid with the current CLI.
