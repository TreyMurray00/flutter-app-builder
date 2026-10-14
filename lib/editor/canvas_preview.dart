import 'dart:io';

import 'package:flutter/material.dart';

import '../models/builder_document.dart';
import '../models/builder_action.dart';
import 'document_theme.dart';
import 'editor_drag_data.dart';
import '../services/project_store.dart';
import 'signature_pad.dart';

enum PreviewSize {
  phone('Phone', 390, 844),
  tablet('Tablet', 768, 1024),
  desktop('Desktop', 1100, 760);

  const PreviewSize(this.label, this.width, this.height);

  final String label;
  final double width;
  final double height;
}

class CanvasPreview extends StatelessWidget {
  const CanvasPreview({
    required this.document,
    required this.selectedNodeId,
    required this.size,
    required this.onSelect,
    required this.onDrop,
    this.root,
    this.onNavigate,
    this.onRunActions,
    this.activePageId = 'home',
    this.variableValues = const <String, Object?>{},
    this.widgetOverrides = const <String, Map<String, Object?>>{},
    this.projectPath,
    this.transformationController,
    this.viewportKey,
    this.panEnabled = false,
    this.drawerEdgeSwipeEnabled = false,
    this.onInteractionEnd,
    super.key,
  });

  final BuilderDocument document;
  final String selectedNodeId;
  final PreviewSize size;
  final ValueChanged<String> onSelect;
  final BuilderNode? root;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function(BuilderNode node)? onRunActions;
  final String activePageId;
  final Map<String, Object?> variableValues;
  final Map<String, Map<String, Object?>> widgetOverrides;
  final String? projectPath;
  final TransformationController? transformationController;
  final GlobalKey? viewportKey;
  final bool panEnabled;
  final bool drawerEdgeSwipeEnabled;
  final VoidCallback? onInteractionEnd;
  final void Function(
    EditorDragData data,
    String targetId,
    BuilderDropPosition position,
  )
  onDrop;

  BuilderNode get _previewRoot => root ?? document.root;

  @override
  Widget build(BuildContext context) {
    return DragTarget<EditorDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails:
          (DragTargetDetails<EditorDragData> details) =>
              onDrop(details.data, _previewRoot.id, BuilderDropPosition.inside),
      builder:
          (
            BuildContext context,
            List<EditorDragData?> candidateData,
            List<dynamic> rejectedData,
          ) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              border: Border.all(
                color:
                    candidateData.isNotEmpty
                        ? const Color(0xFF6750A4)
                        : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                const double outerPadding = 32;
                final double width =
                    (constraints.maxWidth - outerPadding)
                        .clamp(0.0, size.width)
                        .toDouble();
                final double height =
                    (constraints.maxHeight - outerPadding)
                        .clamp(0.0, size.height)
                        .toDouble();
                final bool phoneFrame = size == PreviewSize.phone;
                final Brightness brightness = switch (document
                    .appTheme
                    .brightness) {
                  'dark' => Brightness.dark,
                  'system' => MediaQuery.platformBrightnessOf(context),
                  _ => Brightness.light,
                };
                final ThemeData previewTheme = buildDocumentTheme(
                  document,
                  brightness,
                );
                return Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: InteractiveViewer(
                      key: viewportKey,
                      transformationController: transformationController,
                      minScale: .5,
                      maxScale: 4,
                      boundaryMargin: const EdgeInsets.all(4096),
                      panEnabled: panEnabled,
                      scaleEnabled: true,
                      onInteractionEnd: (_) => onInteractionEnd?.call(),
                      // Ctrl+scroll is handled by the editor; prevent the
                      // viewer's default unmodified wheel zoom.
                      scaleFactor: double.maxFinite,
                      trackpadScrollCausesScale: false,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: RepaintBoundary(
                          child: Container(
                            width: size.width,
                            height: size.height,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: previewTheme.scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(
                                phoneFrame ? 28 : 14,
                              ),
                              border: Border.all(
                                color: const Color(0xFFD8DBE4),
                              ),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x160F172A),
                                  blurRadius: 24,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: MediaQuery(
                              data: MediaQuery.of(
                                context,
                              ).copyWith(size: Size(size.width, size.height)),
                              child: KeyedSubtree(
                                key: ValueKey<String>(
                                  'preview-page-$activePageId',
                                ),
                                child: Theme(
                                  data: previewTheme,
                                  child: Material(
                                    color: previewTheme.scaffoldBackgroundColor,
                                    child: IgnorePointer(
                                      ignoring: panEnabled,
                                      child: _renderNode(_previewRoot),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
    );
  }

  Widget _renderNode(BuilderNode node) {
    node = _resolvedNode(node);
    late final Widget content;
    switch (node.type) {
      case 'scaffold':
        final BuilderNode? appBarNode = _firstChildOfType(node, 'appBar');
        final BuilderNode? floatingButtonNode =
            _firstChildOfType(node, 'floatingActionButton') ??
            _firstChildOfType(node, 'extendedFloatingActionButton');
        final BuilderNode? bottomAppBarNode = _firstChildOfType(
          node,
          'bottomAppBar',
        );
        final BuilderNode? navigationBarNode = _firstChildOfType(
          node,
          'navigationBar',
        );
        final BuilderNode? bottomSheetNode = _firstChildOfType(
          node,
          'bottomSheet',
        );
        final BuilderNode? drawerNode = _firstChildOfType(
          node,
          'navigationDrawer',
        );
        final Set<String> scaffoldSlotIds = <String>{
          if (appBarNode != null) appBarNode.id,
          if (floatingButtonNode != null) floatingButtonNode.id,
          if (bottomAppBarNode != null)
            bottomAppBarNode.id
          else if (navigationBarNode != null)
            navigationBarNode.id,
          if (bottomSheetNode != null) bottomSheetNode.id,
          if (drawerNode != null) drawerNode.id,
        };
        final List<BuilderNode> bodyNodes =
            node.children
                .where(
                  (BuilderNode child) => !scaffoldSlotIds.contains(child.id),
                )
                .toList();
        content = Scaffold(
          appBar: appBarNode == null ? null : _renderAppBar(appBarNode),
          // Alt temporarily enables native drawer gestures in the preview;
          // otherwise they compete with palette drops and canvas interaction.
          drawerEnableOpenDragGesture: drawerEdgeSwipeEnabled,
          floatingActionButton:
              floatingButtonNode == null
                  ? null
                  : _renderFloatingActionButton(floatingButtonNode),
          bottomNavigationBar:
              bottomAppBarNode != null
                  ? _renderNode(bottomAppBarNode)
                  : navigationBarNode == null
                  ? null
                  : _renderNode(navigationBarNode),
          bottomSheet:
              bottomSheetNode == null ? null : _renderNode(bottomSheetNode),
          drawer: drawerNode == null ? null : _renderNode(drawerNode),
          body: _childrenWidget(bodyNodes),
        );
        break;
      case 'column':
        content = Column(
          mainAxisAlignment: _mainAxisAlignment(
            node.properties['mainAxisAlignment'],
          ),
          crossAxisAlignment: _crossAxisAlignment(
            node.properties['crossAxisAlignment'],
          ),
          children: node.children.map(_renderNode).toList(),
        );
        break;
      case 'row':
        content = Row(
          mainAxisAlignment: _mainAxisAlignment(
            node.properties['mainAxisAlignment'],
          ),
          crossAxisAlignment: _crossAxisAlignment(
            node.properties['crossAxisAlignment'],
          ),
          children: node.children.map(_renderNode).toList(),
        );
        break;
      case 'expanded':
        content = _childrenWidget(node.children);
        break;
      case 'safeArea':
        content = SafeArea(
          top: node.properties['top'] != false,
          bottom: node.properties['bottom'] != false,
          left: node.properties['left'] != false,
          right: node.properties['right'] != false,
          minimum: EdgeInsets.all(
            _number(node.properties['minimum'], 0, 0, 1200),
          ),
          child: _childrenWidget(node.children),
        );
        break;
      case 'container':
        final Object? rawWidth = node.properties['width'];
        final Object? rawHeight = node.properties['height'];
        final Object? rawPadding = node.properties['padding'];
        final Object? rawRadius = node.properties['borderRadius'];
        final Object? rawColor = node.properties['backgroundColor'];
        final List<Widget> children = node.children.map(_renderNode).toList();
        content = Container(
          width: rawWidth is num ? rawWidth.toDouble().clamp(0, 1200) : 220,
          height: rawHeight is num ? rawHeight.toDouble().clamp(0, 1200) : 100,
          padding: _edgeInsets(
            node,
            'padding',
            fallback: rawPadding is num ? rawPadding.toDouble() : 12,
          ),
          alignment: _containerAlignment(node.properties['alignment']),
          decoration: BoxDecoration(
            color: Color(rawColor is int ? rawColor : 0xFFF1EFF8),
            borderRadius: BorderRadius.circular(
              rawRadius is num ? rawRadius.toDouble().clamp(0, 100) : 12,
            ),
          ),
          child: switch (children.length) {
            0 => const SizedBox.shrink(),
            1 => children.first,
            _ => Column(children: children),
          },
        );
        break;
      case 'padding':
        content = Padding(
          padding: _edgeInsets(node, 'padding', fallback: 16),
          child: _childrenWidget(node.children),
        );
        break;
      case 'componentGroup':
        content = _childrenWidget(node.children);
        break;
      case 'card':
        final int color = _integer(
          node.properties['backgroundColor'],
          0xFFFFFFFF,
        );
        final double radius = _number(
          node.properties['borderRadius'],
          12,
          0,
          100,
        );
        content = SizedBox(
          width: _number(node.properties['width'], 240, 0, 1200),
          height: _number(node.properties['height'], 140, 0, 1200),
          child: Card(
            color: Color(color),
            elevation: _number(node.properties['elevation'], 2, 0, 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Padding(
              padding: _edgeInsets(node, 'padding', fallback: 12),
              child: _childrenWidget(node.children),
            ),
          ),
        );
        break;
      case 'stack':
        content = SizedBox(
          width: _number(node.properties['width'], 260, 0, 1200),
          height: _number(node.properties['height'], 160, 0, 1200),
          child: Stack(
            alignment:
                _containerAlignment(node.properties['alignment']) ??
                Alignment.topLeft,
            fit:
                node.properties['fit'] == 'expand'
                    ? StackFit.expand
                    : StackFit.loose,
            children: node.children.map(_renderNode).toList(),
          ),
        );
        break;
      case 'listView':
        final Axis direction =
            node.properties['scrollDirection'] == 'horizontal'
                ? Axis.horizontal
                : Axis.vertical;
        final double gap = _number(node.properties['itemSpacing'], 8, 0, 120);
        content = SizedBox(
          width: _number(node.properties['width'], 300, 0, 1200),
          height: _number(node.properties['height'], 220, 0, 1200),
          child: ListView.separated(
            scrollDirection: direction,
            padding: EdgeInsets.zero,
            itemCount: node.children.length,
            separatorBuilder:
                (_, __) => SizedBox(
                  width: direction == Axis.horizontal ? gap : 0,
                  height: direction == Axis.vertical ? gap : 0,
                ),
            itemBuilder: (_, int index) => _renderNode(node.children[index]),
          ),
        );
        break;
      case 'gridView':
        final int count = _integer(
          node.properties['crossAxisCount'],
          2,
        ).clamp(1, 8);
        final double gap = _number(node.properties['itemSpacing'], 8, 0, 120);
        content = SizedBox(
          width: _number(node.properties['width'], 300, 0, 1200),
          height: _number(node.properties['height'], 220, 0, 1200),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
            ),
            padding: EdgeInsets.zero,
            itemCount: node.children.length,
            itemBuilder: (_, int index) => _renderNode(node.children[index]),
          ),
        );
        break;
      case 'pageView':
        content = SizedBox(
          width: _number(node.properties['width'], 300, 0, 1200),
          height: _number(node.properties['height'], 220, 0, 1200),
          child: PageView.builder(
            itemCount: node.children.length,
            itemBuilder: (_, int index) => _renderNode(node.children[index]),
          ),
        );
        break;
      case 'swipeableStack':
        content = SizedBox(
          width: _number(node.properties['width'], 300, 0, 1200),
          height: _number(node.properties['height'], 220, 0, 1200),
          child: _SwipeableStack(
            cards: node.children.map(_renderNode).toList(),
            identity: '$activePageId::${node.id}',
            visibleCount: _integer(
              node.properties['visibleCount'],
              3,
            ).clamp(1, 5),
            loop: node.properties['loop'] == true,
          ),
        );
        break;
      case 'text':
        final Object? rawFontSize = node.properties['fontSize'];
        final double fontSize =
            rawFontSize is num
                ? rawFontSize.toDouble().clamp(8, 96).toDouble()
                : 18;
        content = Builder(
          builder:
              (BuildContext context) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _resolveTemplate(
                    node.properties['text'] is String
                        ? node.properties['text']! as String
                        : 'Text',
                  ),
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight:
                        node.properties['fontWeight'] == 'bold'
                            ? FontWeight.bold
                            : FontWeight.normal,
                    color:
                        node.properties['color'] is int
                            ? Color(node.properties['color']! as int)
                            : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
        );
        break;
      case 'button':
        final String label =
            node.properties['label'] is String
                ? node.properties['label']! as String
                : 'Button';
        final String style =
            node.properties['style'] is String
                ? node.properties['style']! as String
                : 'filled';
        final List<Map<String, Object?>> actions = BuilderAction.forNode(node);
        final String route =
            node.properties['route'] is String
                ? (node.properties['route']! as String).trim()
                : '';
        final VoidCallback onPressed =
            actions.isNotEmpty && onRunActions != null
                ? () => onRunActions!(node)
                : route.isNotEmpty && onNavigate != null
                ? () => onNavigate!(route)
                : () => onSelect(node.id);
        content = switch (style) {
          'elevated' => ElevatedButton(
            onPressed: onPressed,
            child: Text(label),
          ),
          'outlined' => OutlinedButton(
            onPressed: onPressed,
            child: Text(label),
          ),
          'text' => TextButton(onPressed: onPressed, child: Text(label)),
          _ => FilledButton(onPressed: onPressed, child: Text(label)),
        };
        break;
      case 'extendedFloatingActionButton':
        content = _renderFloatingActionButton(node);
        break;
      case 'iconButton':
        final String tooltip = node.properties['tooltip'] as String? ?? '';
        final Widget icon = Icon(_icon(node.properties['iconName']));
        final VoidCallback onPressed = _onNodePressed(node);
        content = switch (node.properties['style']) {
          'filled' => IconButton.filled(
            tooltip: tooltip,
            icon: icon,
            onPressed: onPressed,
          ),
          'filledTonal' => IconButton.filledTonal(
            tooltip: tooltip,
            icon: icon,
            onPressed: onPressed,
          ),
          'outlined' => IconButton.outlined(
            tooltip: tooltip,
            icon: icon,
            onPressed: onPressed,
          ),
          _ => IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed),
        };
        break;
      case 'segmentedButton':
        final List<String> options = _commaSeparated(
          node.properties['options'],
          'Day,Week,Month',
        );
        final int selectedIndex =
            _integer(
              node.properties['selectedIndex'],
              0,
            ).clamp(0, options.length - 1).toInt();
        final bool multiSelect = node.properties['multiSelect'] == true;
        final List<String> selectedOptions =
            _commaSeparated(
              node.properties['selectedOptions'],
              options[selectedIndex],
            ).where(options.contains).toList();
        content = SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            for (int index = 0; index < options.length; index++)
              ButtonSegment<String>(
                value: options[index],
                label: Text(options[index]),
              ),
          ],
          multiSelectionEnabled: multiSelect,
          selected: <String>{
            if (multiSelect)
              ...(selectedOptions.isEmpty
                  ? <String>[options[selectedIndex]]
                  : selectedOptions)
            else
              options[selectedIndex],
          },
          onSelectionChanged: (_) => _onNodePressed(node)(),
        );
        break;
      case 'badge':
        content = Badge(
          label: Text(node.properties['label'] as String? ?? '3'),
          child:
              node.children.isEmpty
                  ? Icon(_icon(node.properties['iconName'] ?? 'notifications'))
                  : _childrenWidget(node.children),
        );
        break;
      case 'linearProgressIndicator':
        content = SizedBox(
          width: _number(node.properties['width'], 240, 20, 1200),
          child: LinearProgressIndicator(
            value: _number(node.properties['value'], 0.65, 0, 1),
            minHeight: _number(node.properties['minHeight'], 4, 1, 100),
          ),
        );
        break;
      case 'snackBar':
        final String actionLabel =
            (node.properties['actionLabel'] as String? ?? '').trim();
        content = SnackBar(
          content: Text(node.properties['message'] as String? ?? 'Message'),
          action:
              actionLabel.isEmpty
                  ? null
                  : SnackBarAction(
                    label: actionLabel,
                    onPressed: _onNodePressed(node),
                  ),
        );
        break;
      case 'alertDialog':
        final String cancelLabel =
            (node.properties['cancelLabel'] as String? ?? '').trim();
        content = AlertDialog(
          title: Text(node.properties['title'] as String? ?? 'Dialog'),
          content:
              node.children.isEmpty
                  ? Text(node.properties['message'] as String? ?? 'Message')
                  : _childrenWidget(node.children),
          actions: <Widget>[
            if (cancelLabel.isNotEmpty)
              TextButton(
                onPressed: _onNodePressed(node),
                child: Text(cancelLabel),
              ),
            FilledButton(
              onPressed: _onNodePressed(node),
              child: Text(node.properties['confirmLabel'] as String? ?? 'OK'),
            ),
          ],
        );
        break;
      case 'bottomSheet':
        content = BottomSheet(
          onClosing: () {},
          builder:
              (BuildContext context) => Padding(
                padding: const EdgeInsets.all(16),
                child:
                    node.children.isEmpty
                        ? ListTile(
                          title: Text(
                            node.properties['title'] as String? ??
                                'More options',
                          ),
                          subtitle: Text(
                            node.properties['message'] as String? ?? '',
                          ),
                        )
                        : _childrenWidget(node.children),
              ),
        );
        break;
      case 'listTile':
        final String subtitle =
            (node.properties['subtitle'] as String? ?? '').trim();
        content = ListTile(
          leading: Icon(_icon(node.properties['leadingIcon'])),
          title: Text(node.properties['title'] as String? ?? 'List item'),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          trailing: Icon(_icon(node.properties['trailingIcon'])),
          onTap: _onNodePressed(node),
        );
        break;
      case 'bottomAppBar':
        content = BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(node.properties['label'] as String? ?? 'Bottom app bar'),
              IconButton(
                tooltip: 'Add',
                icon: const Icon(Icons.add),
                onPressed: _onNodePressed(node),
              ),
            ],
          ),
        );
        break;
      case 'navigationBar':
        final List<String> destinations = _commaSeparated(
          node.properties['destinations'],
          'Home,Search,Settings',
        );
        final int selectedIndex =
            _integer(
              node.properties['selectedIndex'],
              0,
            ).clamp(0, destinations.length - 1).toInt();
        content = NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (_) => _onNodePressed(node)(),
          destinations: <NavigationDestination>[
            for (final String label in destinations)
              NavigationDestination(
                icon: const Icon(Icons.circle_outlined),
                selectedIcon: const Icon(Icons.circle),
                label: label,
              ),
          ],
        );
        break;
      case 'navigationDrawer':
        final List<String> destinations = _commaSeparated(
          node.properties['destinations'],
          'Home,Search,Settings',
        );
        final int selectedIndex =
            _integer(
              node.properties['selectedIndex'],
              0,
            ).clamp(0, destinations.length - 1).toInt();
        content = NavigationDrawer(
          selectedIndex: selectedIndex,
          onDestinationSelected: (_) => _onNodePressed(node)(),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
              child: Text('Navigation'),
            ),
            for (final String label in destinations)
              NavigationDrawerDestination(
                icon: const Icon(Icons.circle_outlined),
                selectedIcon: const Icon(Icons.circle),
                label: Text(label),
              ),
          ],
        );
        break;
      case 'navigationRail':
        final List<String> destinations = _commaSeparated(
          node.properties['destinations'],
          'Home,Search,Settings',
        );
        final int selectedIndex =
            _integer(
              node.properties['selectedIndex'],
              0,
            ).clamp(0, destinations.length - 1).toInt();
        content = NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (_) => _onNodePressed(node)(),
          destinations: <NavigationRailDestination>[
            for (final String label in destinations)
              NavigationRailDestination(
                icon: const Icon(Icons.circle_outlined),
                selectedIcon: const Icon(Icons.circle),
                label: Text(label),
              ),
          ],
        );
        break;
      case 'tabBar':
        final List<String> tabs = _commaSeparated(
          node.properties['tabs'],
          'Overview,Details,Reviews',
        );
        content = DefaultTabController(
          length: tabs.length,
          child: TabBar(
            onTap: (_) => _onNodePressed(node)(),
            tabs: <Widget>[for (final String tab in tabs) Tab(text: tab)],
          ),
        );
        break;
      case 'chip':
        content = ActionChip(
          label: Text(node.properties['label'] as String? ?? 'Chip'),
          onPressed: _onNodePressed(node),
        );
        break;
      case 'datePicker':
        content = Builder(
          builder:
              (BuildContext context) => TextButton.icon(
                onPressed: () async {
                  final DateTime? value = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (value != null) _onNodePressed(node)();
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  node.properties['label'] as String? ?? 'Select date',
                ),
              ),
        );
        break;
      case 'menu':
        final List<String> options = _commaSeparated(
          node.properties['options'],
          'Edit,Copy,Delete',
        );
        content = MenuAnchor(
          menuChildren: <Widget>[
            for (final String option in options)
              MenuItemButton(
                onPressed: _onNodePressed(node),
                child: Text(option),
              ),
          ],
          builder:
              (
                BuildContext context,
                MenuController controller,
                Widget? child,
              ) => FilledButton.tonal(
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: Text(node.properties['label'] as String? ?? 'Open menu'),
              ),
        );
        break;
      case 'radio':
        final List<String> options = _commaSeparated(
          node.properties['options'],
          'Option one,Option two',
        );
        final String selectedOption =
            node.properties['selectedOption'] as String? ?? options.first;
        content = RadioGroup<String>(
          groupValue:
              options.contains(selectedOption) ? selectedOption : options.first,
          onChanged: (_) => _onNodePressed(node)(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String option in options)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Radio<String>(value: option),
                    Text(option),
                  ],
                ),
            ],
          ),
        );
        break;
      case 'slider':
        final double min = _number(node.properties['min'], 0, -100000, 99999);
        final double max = _number(
          node.properties['max'],
          100,
          min + 0.001,
          100000,
        );
        content = SizedBox(
          width: _number(node.properties['width'], 240, 80, 1200),
          child: Slider(
            min: min,
            max: max,
            value: _number(node.properties['value'], 50, min, max),
            onChanged: (_) => _onNodePressed(node)(),
          ),
        );
        break;
      case 'timePicker':
        content = Builder(
          builder:
              (BuildContext context) => TextButton.icon(
                onPressed: () async {
                  final TimeOfDay? value = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (value != null) _onNodePressed(node)();
                },
                icon: const Icon(Icons.access_time),
                label: Text(
                  node.properties['label'] as String? ?? 'Select time',
                ),
              ),
        );
        break;
      case 'image':
        final String source =
            node.properties['source'] is String
                ? node.properties['source']! as String
                : '';
        final BoxFit fit = _boxFit(node.properties['fit']);
        content = SizedBox(
          width: _number(node.properties['width'], 180, 0, 1200),
          height: _number(node.properties['height'], 120, 0, 1200),
          child:
              source.trim().isEmpty
                  ? _imagePlaceholder()
                  : Image.file(
                    File(resolveProjectAssetPath(projectPath, source)),
                    fit: fit,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  ),
        );
        break;
      case 'icon':
        content = Icon(
          _icon(node.properties['iconName']),
          size: _number(node.properties['size'], 32, 8, 256),
          color: Color(_integer(node.properties['color'], 0xFF6750A4)),
        );
        break;
      case 'divider':
        content = Divider(
          height: _number(node.properties['height'], 24, 0, 1200),
          thickness: _number(node.properties['thickness'], 1, 0.1, 100),
          indent: _number(node.properties['indent'], 0, 0, 1200),
          endIndent: _number(node.properties['endIndent'], 0, 0, 1200),
          color: Color(_integer(node.properties['color'], 0xFFB8BEC9)),
        );
        break;
      case 'verticalDivider':
        content = SizedBox(
          height: _number(node.properties['height'], 48, 0, 1200),
          child: VerticalDivider(
            width: _number(node.properties['width'], 24, 0, 1200),
            thickness: _number(node.properties['thickness'], 1, 0.1, 100),
            indent: _number(node.properties['indent'], 0, 0, 1200),
            endIndent: _number(node.properties['endIndent'], 0, 0, 1200),
            color: Color(_integer(node.properties['color'], 0xFFB8BEC9)),
          ),
        );
        break;
      case 'textField':
        final String initialValue = _resolveTemplate(
          node.properties['initialValue'] as String? ?? '',
        );
        content = SizedBox(
          width: _number(node.properties['width'], 240, 0, 1200),
          child: TextFormField(
            key: ValueKey<String>(
              'preview-field-$activePageId-${node.id}-$initialValue',
            ),
            initialValue: initialValue,
            readOnly: true,
            decoration: InputDecoration(
              labelText: _resolveTemplate(
                node.properties['label'] as String? ?? 'Text field',
              ),
              hintText: _resolveTemplate(
                node.properties['hintText'] as String? ?? 'Enter text',
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
        break;
      case 'checkbox':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Checkbox(
              value: node.properties['value'] == true,
              onChanged: (_) => onSelect(node.id),
              activeColor: Color(
                _integer(node.properties['activeColor'], 0xFF6750A4),
              ),
            ),
            Text(node.properties['label'] as String? ?? 'Checkbox'),
          ],
        );
        break;
      case 'switch':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Switch(
              value: node.properties['value'] == true,
              onChanged: (_) => onSelect(node.id),
              activeThumbColor: Color(
                _integer(node.properties['activeColor'], 0xFF6750A4),
              ),
            ),
            Text(node.properties['label'] as String? ?? 'Switch'),
          ],
        );
        break;
      case 'signature':
        content = LocalSignaturePad(
          width: _number(node.properties['width'], 280, 40, 1200),
          height: _number(node.properties['height'], 160, 40, 1200),
          strokeWidth: _number(node.properties['strokeWidth'], 2, 0.5, 20),
          penColor: Color(_integer(node.properties['penColor'], 0xFF20242C)),
          backgroundColor: Color(
            _integer(node.properties['backgroundColor'], 0xFFFFFFFF),
          ),
        );
        break;
      case 'appBar':
      case 'floatingActionButton':
        content = const SizedBox.shrink();
        break;
      default:
        content = const SizedBox.shrink();
        break;
    }

    final bool isExpanded = node.type == 'expanded';
    Widget laidOutContent = content;
    final double? widthFactor =
        isExpanded ? null : _sizeFactor(node.properties['widthMode']);
    final double? heightFactor =
        isExpanded ? null : _sizeFactor(node.properties['heightMode']);
    if (widthFactor != null || heightFactor != null) {
      final Widget sizeChild = laidOutContent;
      laidOutContent = LayoutBuilder(
        builder:
            (BuildContext context, BoxConstraints constraints) => SizedBox(
              width:
                  widthFactor == null
                      ? null
                      : (constraints.maxWidth.isFinite
                              ? constraints.maxWidth
                              : MediaQuery.sizeOf(context).width) *
                          widthFactor,
              height:
                  heightFactor == null
                      ? null
                      : (constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : MediaQuery.sizeOf(context).height) *
                          heightFactor,
              child: sizeChild,
            ),
      );
    }
    if (!isExpanded &&
        node.type != 'container' &&
        node.type != 'padding' &&
        _hasInsets(node, 'padding')) {
      laidOutContent = Padding(
        padding: _edgeInsets(node, 'padding'),
        child: laidOutContent,
      );
    }
    final double opacity =
        isExpanded ? 1 : _number(node.properties['opacity'], 1, 0, 1);
    if (opacity < 1) {
      laidOutContent = Opacity(opacity: opacity, child: laidOutContent);
    }
    if (!isExpanded && _hasInsets(node, 'margin')) {
      laidOutContent = Padding(
        padding: _edgeInsets(node, 'margin'),
        child: laidOutContent,
      );
    }
    if (!isExpanded && node.properties['visible'] == false) {
      laidOutContent = Visibility(visible: false, child: laidOutContent);
    }

    final bool selected = node.id == selectedNodeId;
    final Widget selectableContent = GestureDetector(
      key: ValueKey<String>('preview-node-$activePageId-${node.id}'),
      behavior: HitTestBehavior.translucent,
      onTap: () => onSelect(node.id),
      child: laidOutContent,
    );

    Widget withSelectionBorder(bool isDropTarget) {
      final BoxDecoration decoration = BoxDecoration(
        border:
            selected || isDropTarget
                ? Border.all(
                  color:
                      isDropTarget
                          ? const Color(0xFF8B75C7)
                          : const Color(0xFF6750A4),
                  width: 2,
                )
                : null,
      );
      if (isExpanded) {
        return Expanded(
          flex: _integer(node.properties['flex'], 1).clamp(1, 100).toInt(),
          child: DecoratedBox(
            decoration: decoration,
            child: GestureDetector(
              key: ValueKey<String>('preview-node-$activePageId-${node.id}'),
              behavior: HitTestBehavior.translucent,
              onTap: () => onSelect(node.id),
              child: laidOutContent,
            ),
          ),
        );
      }
      return DecoratedBox(decoration: decoration, child: selectableContent);
    }

    if (!node.acceptsChildren) return withSelectionBorder(false);
    return DragTarget<EditorDragData>(
      onWillAcceptWithDetails: (DragTargetDetails<EditorDragData> details) {
        final EditorDragData data = details.data;
        if (data is PaletteObjectDrag) {
          return node.canAcceptChildType(data.type);
        }
        if (data case ExistingObjectDrag(:final nodeId)) {
          final BuilderNode? draggedNode = _previewRoot.findById(nodeId);
          return draggedNode != null &&
              node.canAcceptChild(draggedNode) &&
              nodeId != node.id &&
              !draggedNode.depthFirst().any(
                (BuilderNode descendant) => descendant.id == node.id,
              );
        }
        return false;
      },
      onAcceptWithDetails: (DragTargetDetails<EditorDragData> details) {
        onDrop(details.data, node.id, BuilderDropPosition.inside);
      },
      builder:
          (
            BuildContext context,
            List<EditorDragData?> candidateData,
            List<dynamic> rejectedData,
          ) => withSelectionBorder(candidateData.isNotEmpty),
    );
  }

  BuilderNode _resolvedNode(BuilderNode node) {
    final Map<String, Object?> properties = <String, Object?>{
      ...node.properties,
    };
    final Object? rawBindings = node.properties['bindings'];
    if (rawBindings is Map) {
      for (final MapEntry<Object?, Object?> entry in rawBindings.entries) {
        final String property = entry.key.toString();
        final Object? value =
            entry.value is String
                ? variableValues[entry.value! as String]
                : null;
        if (value != null) {
          properties[property] =
              <String>{
                    'text',
                    'label',
                    'hintText',
                    'initialValue',
                  }.contains(property)
                  ? value.toString()
                  : value;
        }
      }
    }
    final String runtimeKey = EditorRuntimeKey.of(activePageId, node.id);
    properties.addAll(widgetOverrides[runtimeKey] ?? const <String, Object?>{});
    return node.copyWith(properties: properties);
  }

  String _resolveTemplate(String template) {
    final RegExp token = RegExp(r'\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)');
    return template.replaceAllMapped(token, (Match match) {
      final String key = (match[1] ?? match[2] ?? '').trim();
      BuilderVariable? variable;
      for (final BuilderVariable candidate in document.variables) {
        if (candidate.id == key || candidate.name == key) {
          variable = candidate;
          break;
        }
      }
      if (variable == null) return match[0] ?? '';
      return (variableValues[variable.id] ?? variable.initialValue).toString();
    });
  }

  Widget _childrenWidget(List<BuilderNode> children) {
    final List<Widget> widgets = children.map(_renderNode).toList();
    return switch (widgets.length) {
      0 => const SizedBox.shrink(),
      1 => widgets.first,
      _ => Column(mainAxisSize: MainAxisSize.min, children: widgets),
    };
  }

  double? _sizeFactor(Object? value) => switch (value) {
    'max' => 1,
    'quarter' => 0.25,
    'half' => 0.5,
    'threeQuarter' => 0.75,
    _ => null,
  };

  BuilderNode? _firstChildOfType(BuilderNode parent, String type) {
    for (final BuilderNode child in parent.children) {
      if (child.type == type) return child;
    }
    return null;
  }

  PreferredSizeWidget _renderAppBar(BuilderNode node) => PreferredSize(
    preferredSize: const Size.fromHeight(kToolbarHeight),
    child: GestureDetector(
      onTap: () => onSelect(node.id),
      child: AppBar(
        title: Text(node.properties['title'] as String? ?? 'App Bar'),
        backgroundColor: Color(
          _integer(node.properties['backgroundColor'], 0xFF6750A4),
        ),
        foregroundColor: Color(
          _integer(node.properties['foregroundColor'], 0xFFFFFFFF),
        ),
        elevation: _number(node.properties['elevation'], 2, 0, 24),
      ),
    ),
  );

  Widget _renderFloatingActionButton(BuilderNode node) {
    final VoidCallback onPressed = _onNodePressed(node);
    final Color backgroundColor = Color(
      _integer(node.properties['backgroundColor'], 0xFF6750A4),
    );
    final Color foregroundColor = Color(
      _integer(node.properties['foregroundColor'], 0xFFFFFFFF),
    );
    if (node.type == 'extendedFloatingActionButton') {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        icon: Icon(_icon(node.properties['iconName'])),
        label: Text(node.properties['label'] as String? ?? 'Create'),
      );
    }
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: Icon(_icon(node.properties['iconName'])),
    );
  }

  VoidCallback _onNodePressed(BuilderNode node) =>
      BuilderAction.forNode(node).isNotEmpty && onRunActions != null
          ? () => onRunActions!(node)
          : () => onSelect(node.id);

  List<String> _commaSeparated(Object? value, String fallback) {
    final String source =
        value is String && value.trim().isNotEmpty ? value : fallback;
    final List<String> items =
        source
            .split(',')
            .map((String item) => item.trim())
            .where((String item) => item.isNotEmpty)
            .toList();
    return items.isEmpty ? fallback.split(',') : items;
  }

  Widget _imagePlaceholder() => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF0F2F5),
      border: Border.all(color: const Color(0xFFD5DAE2)),
    ),
    child: const Center(
      child: Icon(Icons.image_outlined, size: 34, color: Color(0xFF929AAA)),
    ),
  );

  BoxFit _boxFit(Object? value) => switch (value) {
    'contain' => BoxFit.contain,
    'fill' => BoxFit.fill,
    'fitWidth' => BoxFit.fitWidth,
    'fitHeight' => BoxFit.fitHeight,
    'none' => BoxFit.none,
    'scaleDown' => BoxFit.scaleDown,
    _ => BoxFit.cover,
  };

  IconData _icon(Object? value) => switch (value) {
    'home' => Icons.home,
    'search' => Icons.search,
    'favorite' => Icons.favorite,
    'settings' => Icons.settings,
    'person' => Icons.person,
    'add' => Icons.add,
    'check' => Icons.check,
    'menu' => Icons.menu,
    'arrowForward' => Icons.arrow_forward,
    'notifications' => Icons.notifications_outlined,
    _ => Icons.star,
  };

  MainAxisAlignment _mainAxisAlignment(Object? value) => switch (value) {
    'center' => MainAxisAlignment.center,
    'end' => MainAxisAlignment.end,
    'spaceBetween' => MainAxisAlignment.spaceBetween,
    _ => MainAxisAlignment.start,
  };

  CrossAxisAlignment _crossAxisAlignment(Object? value) => switch (value) {
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.start,
  };

  EdgeInsets _edgeInsets(
    BuilderNode node,
    String prefix, {
    double fallback = 0,
  }) {
    final double legacy = _number(node.properties[prefix], fallback, 0, 1200);
    double side(String suffix) => _number(
      node.properties['${prefix}${_capitalized(suffix)}'],
      legacy,
      0,
      1200,
    );
    return EdgeInsets.fromLTRB(
      side('left'),
      side('top'),
      side('right'),
      side('bottom'),
    );
  }

  bool _hasInsets(BuilderNode node, String prefix) {
    for (final String side in <String>['Top', 'Right', 'Bottom', 'Left']) {
      if (_number(node.properties['$prefix$side'], 0, 0, 1200) != 0) {
        return true;
      }
    }
    return _number(node.properties[prefix], 0, 0, 1200) != 0;
  }

  double _number(Object? value, double fallback, double min, double max) =>
      value is num && value.isFinite
          ? value.toDouble().clamp(min, max).toDouble()
          : fallback;

  int _integer(Object? value, int fallback) =>
      value is num && value.isFinite ? value.round() : fallback;

  String _capitalized(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';

  Alignment? _containerAlignment(Object? value) => switch (value) {
    'topLeft' => Alignment.topLeft,
    'topCenter' => Alignment.topCenter,
    'topRight' => Alignment.topRight,
    'centerLeft' => Alignment.centerLeft,
    'center' => Alignment.center,
    'centerRight' => Alignment.centerRight,
    'bottomLeft' => Alignment.bottomLeft,
    'bottomCenter' => Alignment.bottomCenter,
    'bottomRight' => Alignment.bottomRight,
    _ => null,
  };
}

class EditorRuntimeKey {
  const EditorRuntimeKey._();

  static String of(String pageId, String nodeId) => '$pageId::$nodeId';
}

class _SwipeableStack extends StatefulWidget {
  const _SwipeableStack({
    required this.cards,
    required this.identity,
    required this.visibleCount,
    required this.loop,
  });

  final List<Widget> cards;
  final String identity;
  final int visibleCount;
  final bool loop;

  @override
  State<_SwipeableStack> createState() => _SwipeableStackState();
}

class _SwipeableStackState extends State<_SwipeableStack> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const Center(child: Text('Add cards to swipe'));
    }
    final int count = widget.cards.length;
    final int active = _index % count;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        for (int depth = widget.visibleCount - 1; depth > 0; depth--)
          if (count > depth)
            Positioned.fill(
              top: depth * 9,
              bottom: 0,
              left: depth * 7,
              right: depth * 7,
              child: IgnorePointer(
                child: Transform.scale(
                  scale: 1 - depth * .045,
                  alignment: Alignment.topCenter,
                  child: const Card(
                    color: const Color(0xFFE7EAF0),
                    elevation: 1,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
        Positioned.fill(
          child: GestureDetector(
            key: ValueKey<String>('swipe-card-${widget.identity}-$active'),
            onHorizontalDragEnd: (DragEndDetails details) {
              final double velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 80) return;
              setState(() {
                if (_index + 1 < count || widget.loop) _index++;
              });
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'swipe-content-${widget.identity}-$active',
                ),
                child: Card(
                  elevation: 3,
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox.expand(child: widget.cards[active]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
