# Agent guidance

For requests to create or change an app with Local Flutter Builder, read [`SKILL.md`](SKILL.md) first. The project manifest (`.appbuilder.json`) is the editable design source; use the CLI to create, validate, inspect, and export it.

Keep generated Flutter output in the destination the user requested. The builder repository contains the editor and generator, so do not replace its own `lib/` with an app being created.

For changes to the builder itself, follow the existing Flutter and Dart conventions and preserve compatibility with saved project schema versions.
