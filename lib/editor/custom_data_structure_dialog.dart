import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/dart.dart' as dart_language;

import '../models/builder_document.dart';

class CustomDataStructureDialog extends StatefulWidget {
  const CustomDataStructureDialog({
    required this.structures,
    this.structure,
    super.key,
  });

  final List<BuilderCustomDataStructure> structures;
  final BuilderCustomDataStructure? structure;

  @override
  State<CustomDataStructureDialog> createState() =>
      _CustomDataStructureDialogState();
}

class _CustomDataStructureDialogState extends State<CustomDataStructureDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.structure?.name ?? 'ExampleRecord',
  );
  late final CodeController _body = CodeController(
    text:
        widget.structure?.body ??
        'class ExampleRecord {\n  const ExampleRecord({required this.id});\n\n  final String id;\n}\n',
    language: dart_language.dart,
  );

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  String? get _validationError {
    final String name = _name.text.trim();
    if (name.isEmpty) return 'Enter a name for this data type.';
    final bool duplicate = widget.structures.any(
      (BuilderCustomDataStructure item) =>
          item.id != widget.structure?.id &&
          item.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) return 'A data type with that name already exists.';
    final String source = _body.text.trim();
    if (source.isEmpty) return 'Add a Dart class, enum, or type declaration.';
    final parsed = parseString(
      content: source,
      path: 'custom_data_structure.dart',
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) {
      return parsed.errors.first.message;
    }
    if (parsed.unit.directives.isNotEmpty) {
      return 'Add type declarations only; put no import or export statements here.';
    }
    if (parsed.unit.declarations.isEmpty) {
      return 'Add at least one class, enum, or typedef declaration.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? validationError = _validationError;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text(
        widget.structure == null ? 'Create data type' : 'Edit data type',
      ),
      content: SizedBox(
        width: 680,
        height: 490,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Data type name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            const Text(
              'Dart declarations',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: CodeField(
                  controller: _body,
                  minLines: 18,
                  maxLines: 22,
                  wrap: true,
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.45,
                  ),
                  gutterStyle: GutterStyle(
                    width: 42,
                    showFoldingHandles: false,
                    textStyle: TextStyle(
                      color: isDark
                          ? const Color(0xFFA8AAB5)
                          : const Color(0xFF737B8A),
                      fontSize: 10,
                    ),
                  ),
                  background: isDark
                      ? atomOneDarkTheme['root']?.backgroundColor ??
                          const Color(0xFF282C34)
                      : githubTheme['root']?.backgroundColor ?? Colors.white,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              validationError ??
                  'Custom functions can use these types. Store app data as JSON and convert with fromJson()/toJson(). Exported apps include the declarations.',
              style: TextStyle(
                color: validationError == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: validationError != null
              ? null
              : () => Navigator.pop(
                    context,
                    BuilderCustomDataStructure(
                      id:
                          widget.structure?.id ??
                          'custom_type_${DateTime.now().microsecondsSinceEpoch}',
                      name: _name.text.trim(),
                      body: _body.text.trim(),
                    ),
                  ),
          child: const Text('Save data type'),
        ),
      ],
    );
  }
}
