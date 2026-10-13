import 'package:flutter/material.dart';

import '../models/builder_document.dart';
import 'editor_drag_data.dart';
import 'editor_palette.dart';
import 'widget_catalog.dart';

class WidgetTreePanel extends StatefulWidget {
  const WidgetTreePanel({
    required this.root,
    required this.selectedNodeId,
    required this.onSelect,
    required this.onAddObject,
    required this.onDrop,
    this.componentGroups = const <BuilderComponentGroup>[],
    this.onAddGroup,
    super.key,
  });

  final BuilderNode root;
  final String selectedNodeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onAddObject;
  final void Function(
    EditorDragData data,
    String targetId,
    BuilderDropPosition position,
  )
  onDrop;
  final List<BuilderComponentGroup> componentGroups;
  final ValueChanged<BuilderComponentGroup>? onAddGroup;

  @override
  State<WidgetTreePanel> createState() => _WidgetTreePanelState();
}

class _WidgetTreePanelState extends State<WidgetTreePanel> {
  final TextEditingController _search = TextEditingController();
  bool _showTree = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    _appendRows(rows, widget.root, 0, isRoot: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _PanelHeading(
                title: _showTree ? 'Widget tree' : 'Widget Palette',
                icon:
                    _showTree
                        ? Icons.account_tree_outlined
                        : Icons.widgets_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Widget Palette',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _showTree = false),
              icon: Icon(
                Icons.widgets_outlined,
                size: 18,
                color:
                    _showTree
                        ? EditorPalette.mutedText(context)
                        : EditorPalette.primary(context),
              ),
            ),
            IconButton(
              tooltip: 'Widget tree',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _showTree = true),
              icon: Icon(
                Icons.account_tree_outlined,
                size: 18,
                color:
                    _showTree
                        ? EditorPalette.primary(context)
                        : EditorPalette.mutedText(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _showTree ? _treeView(rows) : _widgetsView()),
      ],
    );
  }

  Widget _widgetsView() => Column(
    children: <Widget>[
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: 'Search for a widget…',
          isDense: true,
          filled: true,
          fillColor: EditorPalette.surfaceRaised(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            _commonGrid(),
            _componentGroups(),
            _categoryGrid(
              WidgetCategory.layout,
              'Layout Elements',
              Icons.dashboard_outlined,
            ),
            _categoryGrid(
              WidgetCategory.base,
              'Base Elements',
              Icons.widgets_outlined,
            ),
            _categoryGrid(
              WidgetCategory.form,
              'Form Elements',
              Icons.check_box_outlined,
            ),
            _categoryGrid(
              WidgetCategory.page,
              'Page Elements',
              Icons.web_asset_outlined,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Drag onto the canvas or drop into a layout to nest it.',
                style: TextStyle(
                  color: EditorPalette.mutedText(context),
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _treeView(List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        'Drag to reorder or nest',
        style: TextStyle(fontSize: 10, color: EditorPalette.mutedText(context)),
      ),
      const SizedBox(height: 8),
      Expanded(child: ListView(padding: EdgeInsets.zero, children: rows)),
    ],
  );

  Widget _categoryGrid(WidgetCategory category, String title, IconData icon) {
    final String query = _search.text.trim().toLowerCase();
    final List<WidgetCatalogItem> items =
        widgetCatalog
            .where(
              (WidgetCatalogItem item) =>
                  item.category == category &&
                  (query.isEmpty ||
                      item.keywords.toLowerCase().contains(query)),
            )
            .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: ValueKey<String>(
        'widget-category-${category.name}-${query.isNotEmpty}',
      ),
      initiallyExpanded: query.isNotEmpty || category == WidgetCategory.layout,
      tilePadding: const EdgeInsets.symmetric(horizontal: 2),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: EditorPalette.mutedText(context)),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      children: <Widget>[_itemGrid(items)],
    );
  }

  Widget _componentGroups() {
    if (widget.componentGroups.isEmpty) return const SizedBox.shrink();
    final String query = _search.text.trim().toLowerCase();
    final List<BuilderComponentGroup> groups = widget.componentGroups
        .where(
          (BuilderComponentGroup group) =>
              query.isEmpty || group.name.toLowerCase().contains(query),
        )
        .toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: ValueKey<String>('component-groups-${query.isNotEmpty}'),
      initiallyExpanded: query.isNotEmpty,
      tilePadding: const EdgeInsets.symmetric(horizontal: 2),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Row(
        children: <Widget>[
          Icon(
            Icons.dashboard_customize_outlined,
            size: 15,
            color: EditorPalette.mutedText(context),
          ),
          const SizedBox(width: 7),
          const Text(
            'Reusable Groups',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      children: groups
          .map(
            (BuilderComponentGroup group) => ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 7),
              leading: Icon(
                Icons.dashboard_customize_outlined,
                size: 17,
                color: EditorPalette.primary(context),
              ),
              title: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.add_circle_outline, size: 17),
              onTap: () => widget.onAddGroup?.call(group),
            ),
          )
          .toList(),
    );
  }

  Widget _commonGrid() {
    final String query = _search.text.trim().toLowerCase();
    const Set<String> commonTypes = <String>{
      'text',
      'column',
      'row',
      'container',
      'image',
      'button',
    };
    final List<WidgetCatalogItem> items =
        widgetCatalog
            .where(
              (WidgetCatalogItem item) =>
                  commonTypes.contains(item.type) &&
                  (query.isEmpty ||
                      item.keywords.toLowerCase().contains(query)),
            )
            .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: ValueKey<String>('widget-category-common-${query.isNotEmpty}'),
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 2),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Row(
        children: <Widget>[
          Icon(
            Icons.star_border,
            size: 15,
            color: EditorPalette.mutedText(context),
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'Commonly Used Elements',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      children: <Widget>[_itemGrid(items)],
    );
  }

  Widget _itemGrid(List<WidgetCatalogItem> items) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      const double gap = 8;
      final int columns = constraints.maxWidth >= 360 ? 3 : 2;
      final double tileWidth =
          (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children:
            items
                .map(
                  (WidgetCatalogItem item) => _CatalogTile(
                    item: item,
                    width: tileWidth,
                    onPressed: () => widget.onAddObject(item.type),
                  ),
                )
                .toList(),
      );
    },
  );

  void _appendRows(
    List<Widget> rows,
    BuilderNode node,
    int depth, {
    required bool isRoot,
  }) {
    if (!isRoot) {
      rows.add(
        _TreeDropZone(
          onDrop:
              (EditorDragData data) =>
                  widget.onDrop(data, node.id, BuilderDropPosition.before),
        ),
      );
    }
    rows.add(
      Padding(
        padding: EdgeInsets.only(left: depth * 14.0),
        child: _DraggableTreeRow(
          node: node,
          selected: node.id == widget.selectedNodeId,
          onSelect: () => widget.onSelect(node.id),
          onDrop:
              (EditorDragData data) =>
                  widget.onDrop(data, node.id, BuilderDropPosition.inside),
        ),
      ),
    );
    for (final BuilderNode child in node.children) {
      _appendRows(rows, child, depth + 1, isRoot: false);
    }
    if (!isRoot) {
      rows.add(
        _TreeDropZone(
          onDrop:
              (EditorDragData data) =>
                  widget.onDrop(data, node.id, BuilderDropPosition.after),
        ),
      );
    }
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: EditorPalette.mutedText(context)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: EditorPalette.text(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DraggableTreeRow extends StatelessWidget {
  const _DraggableTreeRow({
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onDrop,
  });

  final BuilderNode node;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<EditorDragData> onDrop;

  @override
  Widget build(BuildContext context) {
    final WidgetCatalogItem? catalog = catalogItemFor(node.type);
    final (IconData, Color) identity = switch (node.type) {
      'scaffold' => (Icons.web_asset_outlined, const Color(0xFF4F71BA)),
      _ => (catalog?.icon ?? Icons.widgets_outlined, const Color(0xFF398B78)),
    };
    final Widget row = Material(
      color:
          selected
              ? EditorPalette.primaryContainer(context)
              : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(identity.$1, size: 16, color: identity.$2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label(node),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        selected
                            ? EditorPalette.primary(context)
                            : EditorPalette.text(context),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.drag_indicator,
                size: 16,
                color: Colors.blueGrey.shade300,
              ),
            ],
          ),
        ),
      ),
    );

    final Widget draggable = Draggable<EditorDragData>(
      data: ExistingObjectDrag(node.id),
      feedback: Material(
        elevation: 8,
        color: EditorPalette.surface(context),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 190,
          child: ListTile(
            dense: true,
            leading: Icon(identity.$1, color: identity.$2),
            title: Text(_label(node), overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.32, child: row),
      child: row,
    );

    if (!node.acceptsChildren) return draggable;
    return DragTarget<EditorDragData>(
      onWillAcceptWithDetails:
          (DragTargetDetails<EditorDragData> details) =>
              details.data is PaletteObjectDrag ||
              (details.data is ExistingObjectDrag &&
                  (details.data as ExistingObjectDrag).nodeId != node.id),
      onAcceptWithDetails:
          (DragTargetDetails<EditorDragData> details) => onDrop(details.data),
      builder: (
        BuildContext context,
        List<EditorDragData?> candidateData,
        List<dynamic> rejectedData,
      ) {
        final bool highlighted = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color:
                highlighted
                    ? EditorPalette.primaryContainer(context)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  highlighted
                      ? EditorPalette.primary(context)
                      : Colors.transparent,
              width: 1,
            ),
          ),
          child: draggable,
        );
      },
    );
  }

  String _label(BuilderNode node) {
    if (node.type == 'componentGroup' &&
        node.properties['groupName'] is String) {
      return node.properties['groupName']! as String;
    }
    final String? title = switch (node.type) {
      'text' =>
        node.properties['text'] is String
            ? node.properties['text']! as String
            : 'Text',
      'button' =>
        node.properties['label'] is String
            ? node.properties['label']! as String
            : 'Button',
      _ => null,
    };
    if (title != null) return '${_typeLabel(node.type)} · $title';
    return _typeLabel(node.type);
  }

  String _typeLabel(String type) => switch (type) {
    'scaffold' => 'Scaffold',
    'componentGroup' => 'Component Group',
    _ => catalogItemFor(type)?.label ?? type,
  };
}

class _TreeDropZone extends StatelessWidget {
  const _TreeDropZone({required this.onDrop});

  final ValueChanged<EditorDragData> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<EditorDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails:
          (DragTargetDetails<EditorDragData> details) => onDrop(details.data),
      builder:
          (
            BuildContext context,
            List<EditorDragData?> candidateData,
            List<dynamic> rejectedData,
          ) => Container(
            height: 7,
            decoration: BoxDecoration(
              color:
                  candidateData.isNotEmpty
                      ? EditorPalette.primary(context)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.item,
    required this.width,
    required this.onPressed,
  });

  final WidgetCatalogItem item;
  final double width;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget button = Tooltip(
      message: 'Add ${item.label}',
      child: SizedBox(
        width: width,
        height: 88,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: EditorPalette.text(context),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            side: BorderSide(color: EditorPalette.border(context)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                item.icon,
                size: 30,
                color: EditorPalette.mutedText(context),
              ),
              const SizedBox(height: 7),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Draggable<EditorDragData>(
      data: PaletteObjectDrag(item.type),
      feedback: Material(
        color: EditorPalette.primary(context),
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(item.icon, size: 16, color: EditorPalette.surface(context)),
              const SizedBox(width: 8),
              Text(
                'New ${item.label}',
                style: TextStyle(color: EditorPalette.surface(context)),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: button),
      child: button,
    );
  }
}
