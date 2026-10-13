import 'package:flutter/material.dart';

import '../models/builder_document.dart';

ThemeData buildDocumentTheme(BuilderDocument document, Brightness brightness) {
  final BuilderTheme settings = document.appTheme;
  final ColorScheme base = ColorScheme.fromSeed(
    seedColor: Color(document.seedColor),
    brightness: brightness,
  );
  final ColorScheme colors = base.copyWith(
    surface:
        settings.backgroundColor == null
            ? base.surface
            : Color(settings.backgroundColor!),
    onSurface:
        settings.textColor == null
            ? base.onSurface
            : Color(settings.textColor!),
  );
  final RoundedRectangleBorder shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(settings.cornerRadius),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    fontFamily:
        settings.fontFamily.trim().isEmpty ? null : settings.fontFamily.trim(),
    cardTheme: CardThemeData(shape: shape),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(settings.cornerRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: shape),
    ),
  );
}
