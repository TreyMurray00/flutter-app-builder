/// Separates file-level imports from the statements entered for a custom
/// function. Imports are accepted only before the first Dart statement.
class CustomFunctionSource {
  const CustomFunctionSource({required this.imports, required this.body});

  final List<String> imports;
  final String body;

  factory CustomFunctionSource.parse(String source) {
    final List<String> imports = <String>[];
    final List<String> statements = <String>[];
    bool beforeStatements = true;
    for (final String line in source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')) {
      final String trimmed = line.trim();
      if (beforeStatements &&
          trimmed.startsWith('import ') &&
          trimmed.endsWith(';')) {
        imports.add(trimmed);
        continue;
      }
      if (trimmed.isNotEmpty && !trimmed.startsWith('//')) {
        beforeStatements = false;
      }
      statements.add(line);
    }
    return CustomFunctionSource(imports: imports, body: statements.join('\n'));
  }
}
