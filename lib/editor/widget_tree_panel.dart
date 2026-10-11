import 'package:flutter/material.dart';

import '../models/builder_document.dart';
import 'editor_drag_data.dart';
import 'widget_catalog.dart';

class WidgetTreePanel extends StatefulWidget {
  const WidgetTreePanel({
    required this.root,
    required this.selectedNodeId,
    required this.onSelect,
    required this.onAddObject,
    required this.onDrop,
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
                        ? const Color(0xFF7B8390)
                        : const Color(0xFF6750A4),
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
                        ? const Color(0xFF6750A4)
                        : const Color(0xFF7B8390),
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
          fillColor: const Color(0xFFF5F6F8),
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
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Drag onto the canvas or drop into a layout to nest it.',
                style: TextStyle(
                  color: Color(0xFF737B8A),
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
      const Text(
        'Drag to reorder or nest',
        style: TextStyle(fontSize: 10, color: Color(0xFF737B8A)),
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
          Icon(icon, size: 15, color: const Color(0xFF657080)),
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
      title: const Row(
        children: <Widget>[
          Icon(Icons.star_border, size: 15, color: Color(0xFF657080)),
          SizedBox(width: 7),
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
        Icon(icon, size: 16, color: const Color(0xFF6E7482)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF3C4351),
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
      color: selected ? const Color(0xFFEDE9F8) : Colors.transparent,
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
                            ? const Color(0xFF493584)
                            : const Color(0xFF424958),
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
        color: Colors.white,
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
            color: highlighted ? const Color(0xFFEDE9F8) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted ? const Color(0xFF6750A4) : Colors.transparent,
              width: 1,
            ),
          ),
          child: draggable,
        );
      },
    );
  }

  String _label(BuilderNode node) {
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
                      ? const Color(0xFF6750A4)
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
            foregroundColor: const Color(0xFF454D5B),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            side: const BorderSide(color: Color(0xFFDCE0E7)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(item.icon, size: 30, color: const Color(0xFF778394)),
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
        color: const Color(0xFF6750A4),
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(item.icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'New ${item.label}',
                style: const TextStyle(color: Colors.white),
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
