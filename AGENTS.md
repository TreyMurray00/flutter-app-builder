# Agent guidance

For requests to create or change an app with Local Flutter Builder, read [`SKILL.md`](SKILL.md) first. The project manifest (`.appbuilder.json`) is the editable design source; use the CLI to create, validate, inspect, and export it.

Keep generated Flutter output in the destination the user requested. The builder repository contains the editor and generator, so do not replace its own `lib/` with an app being created.

For changes to the builder itself, follow the existing Flutter and Dart conventions and preserve compatibility with saved project schema versions. When adding or changing widgets, keep the model definitions, palette, inspector, child-placement rules, canvas preview, Dart generator, validator, JSON schema, `SKILL.md`, and README in sync.

Database-backed UI uses the `databaseList` widget to repeat its child template for each collection record. `${record.fieldId}` resolves a field and `${record._id}` resolves the record ID in widget text and action values. Keep insert, update, and delete behavior consistent between the in-memory editor preview and generated apps using the local database: inserts add rows, updates refresh their displayed values, and deletes remove rows. Data mutations must trigger a preview refresh so repeated rows stay in sync.
