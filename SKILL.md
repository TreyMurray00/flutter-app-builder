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
4. Run `dart run bin/app_builder.dart validate <manifest> --json`. Fix every error. Warnings identify ignored children, missing accessibility labels, and other quality issues. Validation also parses generated Dart source before export.
5. Use `dart run bin/app_builder.dart inspect <manifest> --json` to check the resulting page tree, state, and resources.
6. Export with `dart run bin/app_builder.dart export <manifest> --output <new-directory>`. The output directory must not already exist. Export uses the locally installed Flutter SDK and does not run `pub get`.
7. To compile or launch the generated app, change into the exported directory and use the user's installed Flutter toolchain, for example `flutter analyze` or `flutter run -d <device>`. Package resolution may access pub.dev unless the user requests offline operation.

Use absolute paths or quote paths containing spaces. The CLI accepts `--json` for machine-readable output on `init`, `validate`, `inspect`, `database`, and `export`.

## Project format

The design file is JSON with a `schemaVersion`, app `name`, `theme`, a home `root` widget, and optional `pages`, `variables`, `customFunctions`, `customDataStructures`, `componentGroups`, `databaseCollections`, `databaseRelationships`, `fontAssets`, and `initialPageId`. `root` and each page's `root` are recursive nodes:

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

Widget types supported by the generator are `scaffold`, `safeArea`, `column`, `row`, `expanded`, `flexible`, `spacer`, `container`, `stack`, `listView`, `databaseList`, `singleChildScrollView`, `gridView`, `pageView`, `swipeableStack`, `card`, `padding`, `center`, `align`, `wrap`, `sizedBox`, `aspectRatio`, `clipRRect`, `componentGroup`, `text`, `button`, `image`, `icon`, `divider`, `verticalDivider`, `textField`, `checkbox`, `switch`, `signature`, `appBar`, `floatingActionButton`, `extendedFloatingActionButton`, `iconButton`, `segmentedButton`, `badge`, `linearProgressIndicator`, `snackBar`, `alertDialog`, `bottomSheet`, `listTile`, `bottomAppBar`, `navigationBar`, `navigationDrawer`, `navigationRail`, `tabBar`, `chip`, `datePicker`, `menu`, `radio`, `slider`, and `timePicker`. `Database List` repeats its child template for each record in its selected collection; use `${record.fieldId}` in text and action values, and `${record._id}` for the row ID. `Expanded`, `Flexible`, and `Spacer` must be placed directly under a `Row` or `Column`. Properties are JSON values; the generator reads the same property names used by the visual inspector. Unknown or malformed widget configurations are reported by `validate` when they prevent code generation.

Exported apps use Flutter's official `material_ui` package and require Flutter 3.47 or later (Dart 3.13 or later). The builder editor itself retains its existing SDK requirements.

The home page lives in the top-level `root`. Additional pages use `{ "id", "name", "route", "root" }` entries in `pages`. The home page ID is `home`. Routes must be unique. Node IDs should be unique on a page; actions use IDs to address variables, pages, widgets, functions, and database collections.

Assets such as images and bundled fonts use paths relative to the manifest file. Keep those files beside the manifest or in a subfolder. Validation checks that referenced assets exist, and export copies them into the generated app. A font asset contains `id`, `family`, `source`, and an optional numeric `weight` from 100 to 900.

Database collections may declare `fields` with stable `id` values, display `name`, `type` (`string`, `integer`, `number`, `boolean`, `date`, or `json`), and optional `required`, `primaryKey`, and `unique` flags. Record JSON keys use the field `id`; `seedRecords` remains an array of JSON objects. A `databaseRelationships` entry connects `fromCollectionId`/`fromFieldId` (the child foreign key) to `toCollectionId`/`toFieldId` (a primary-key or unique field on the parent). Related field types must match. A non-unique foreign key models many-to-one, its inverse is one-to-many, and a unique foreign key models one-to-one. Model many-to-many links with a join collection containing a foreign key to each side. Database queries can select direct relationships in either direction. Each join has a `relationshipId`, result `alias`, and `joinType` (`left` or `inner`); the result nests a single related object or `null` for one-to-one, and a list for one-to-many. Filter conditions may include `relationshipId` to target joined fields; omit it for the base collection. Sorting uses `sortRelationshipId` and `sortFieldId`; `sortAggregate` selects `min` or `max` for a one-to-many field. Direct joins only are supported (no multi-hop joins or grouping).

Responsive properties are stored on a node as `properties.responsiveOverrides`, keyed by `phone`, `tablet`, and `desktop`. Each breakpoint value is a map of property names to values, for example `{ "phone": { "fontSize": 18 }, "desktop": { "fontSize": 30 } }`. Preview and exported apps use phone at widths up to 600 logical pixels, tablet above 600 through 1024, and desktop above 1024. A missing override uses the node's base property. Responsive wrapping is not supported in special Scaffold slots or around `Expanded`.

For actions, put a list in a widget's `properties.actions`. Each action has an `id` and `type`; the supported types are `navigate`, `snackbar`, `dialog`, `back`, `setVariable`, `incrementVariable`, `toggleVariable`, `updateWidget`, `conditional`, `loop`, `httpRequest`, `databaseInsert`, `databaseUpdate`, `databaseQuery`, `databaseDelete`, and `customFunction`. Insert and update actions accept a JSON record or patch; update and delete actions accept a record ID. In a Database List item template, use `${record.fieldId}` and `${record._id}` in these values. Refer to [`lib/models/builder_action.dart`](lib/models/builder_action.dart) for the canonical defaults and nested action fields.

To build a database-backed list, create a collection and add a `Database List` widget bound to it. Add child widgets as the repeated item template, such as a `List Tile` whose title is `${record.title}`. Bind a text field to a string app variable in its inspector, then add a button with a `databaseInsert` action that uses that variable in its record JSON, for example `{"title":"$newTodo"}`. Buttons in the item template can use `databaseUpdate` with record ID `${record._id}` and a patch such as `{"completed":true}`, or `databaseDelete` with the same record ID. Inserts add rows, updates refresh their displayed values, and deletes remove rows. The editor preview refreshes after changes, and exported apps reload the collection from their local database.

A `databaseQuery` action can use `filters`, where each condition has a stable `id`, `fieldId`, `operator`, and optional `value`; set `relationshipId` to filter on a joined collection. `filterMode` is `all` (AND) or `any` (OR). `sortRelationshipId`, `sortFieldId`, `sortAggregate`, `sortDescending`, and `limit` configure sorting and maximum rows; `0` means no limit. Supported operators are `equals`, `notEquals`, `contains`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `isNull`, and `isNotNull`. Values are entered as text and converted according to the selected field type; `${variableId}` can insert an app variable.

## CLI reference

```text
dart run bin/app_builder.dart init <file> [--name <name>] [--json]
dart run bin/app_builder.dart validate <file> [--json]
dart run bin/app_builder.dart inspect <file> [--json]
dart run bin/app_builder.dart database <file> list [--json]
dart run bin/app_builder.dart database <file> add-collection --id <id> --name <name> [--json]
dart run bin/app_builder.dart database <file> add-field --collection <id> --id <id> --name <name> [--type <type>] [--required] [--primary-key] [--unique] [--json]
dart run bin/app_builder.dart database <file> add-relationship --id <id> --name <name> --from-collection <id> --from-field <id> --to-collection <id> --to-field <id> [--json]
dart run bin/app_builder.dart database <file> add-seed --collection <id> (--record <json-object> | --record-file <json-file>) [--json]
dart run bin/app_builder.dart database <file> remove-collection --id <id> [--json]
dart run bin/app_builder.dart database <file> remove-field --collection <id> --id <id> [--json]
dart run bin/app_builder.dart database <file> remove-relationship --id <id> [--json]
dart run bin/app_builder.dart database <file> remove-seed --collection <id> --index <zero-based-index> [--json]
dart run bin/app_builder.dart export <file> --output <new-directory> [--json]
```

Database commands edit the manifest in place, save a `.bak` copy, and reject changes that fail project validation. `list --json` includes complete collection definitions and seed records. Field types are `string`, `integer`, `number`, `boolean`, `date`, and `json`. `--record-file` avoids shell quoting when a seed record contains nested JSON. Remove relationships before removing their fields or collections; remove seed records before removing fields they use.

Exit status is `0` on success, `2` when validation finds project errors, `64` for invalid CLI usage, and `1` for an execution failure. In JSON mode, validation prints one object with `ok`, `path`, and `issues`; inspect prints a project summary; database mutations print `ok`, `path`, and `operation`; export prints `ok`, output `path`, and captured Flutter scaffold output. Failures print a JSON object with `ok: false` and an `error` or `issues` field.

When the builder's schema version changes, update the JSON schema and this guide. Keep the example manifest valid with the current CLI.
