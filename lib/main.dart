import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'editor/editor_controller.dart';
import 'editor/editor_screen.dart';
import 'services/dart_generator.dart';
import 'services/flutter_project_exporter.dart';
import 'services/project_store.dart';
import 'theme_mode_controller.dart';

void main() {
  runApp(const LocalBuilderApp());
}

class LocalBuilderApp extends StatelessWidget {
  const LocalBuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeModeController>(
          create: (_) => ThemeModeController(),
        ),
        ChangeNotifierProvider<EditorController>(
          create: (_) => EditorController(),
        ),
        Provider<ProjectStore>(create: (_) => ProjectStore()),
        Provider<DartGenerator>(create: (_) => DartGenerator()),
        Provider<FlutterProjectExporter>(
          create: (_) => FlutterProjectExporter(generator: DartGenerator()),
        ),
      ],
      child: Consumer<ThemeModeController>(
        builder:
            (
              BuildContext context,
              ThemeModeController appearance,
              Widget? child,
            ) => MaterialApp(
              title: 'Local Flutter Builder',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF6750A4),
                  brightness: Brightness.light,
                ),
                scaffoldBackgroundColor: const Color(0xFFF4F5F8),
                visualDensity: VisualDensity.standard,
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF8B75C7),
                  brightness: Brightness.dark,
                ),
                scaffoldBackgroundColor: const Color(0xFF17181E),
                dividerColor: const Color(0xFF3D3E48),
                visualDensity: VisualDensity.standard,
              ),
              themeMode: appearance.mode,
              home: const EditorScreen(),
            ),
      ),
    );
  }
}
