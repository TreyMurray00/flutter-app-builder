import 'package:flutter/material.dart';

class EditorPalette {
  const EditorPalette._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surface(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C1D24) : Colors.white;

  static Color surfaceRaised(BuildContext context) =>
      isDark(context) ? const Color(0xFF25262E) : const Color(0xFFF8F9FB);

  static Color surfaceInset(BuildContext context) =>
      isDark(context) ? const Color(0xFF2C2D36) : const Color(0xFFF3F4F7);

  static Color border(BuildContext context) =>
      isDark(context) ? const Color(0xFF3D3E48) : const Color(0xFFE1E4EA);

  static Color text(BuildContext context) =>
      isDark(context) ? const Color(0xFFE8E6EF) : const Color(0xFF3C4351);

  static Color mutedText(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8AAB5) : const Color(0xFF737B8A);

  static Color primary(BuildContext context) =>
      isDark(context) ? const Color(0xFFB8A5F5) : const Color(0xFF6750A4);

  static Color primaryContainer(BuildContext context) =>
      isDark(context) ? const Color(0xFF362F4B) : const Color(0xFFEDE9F8);

  static Color selectedContainer(BuildContext context) =>
      isDark(context) ? const Color(0xFF42395A) : const Color(0xFFD5CDEF);
}
