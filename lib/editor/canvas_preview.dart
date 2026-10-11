import 'dart:io';

import 'package:flutter/material.dart';

import '../models/builder_document.dart';
import '../models/builder_action.dart';
import 'editor_drag_data.dart';
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
                const double outerPadding = 48;
                final double width =
                    (constraints.maxWidth - outerPadding)
                        .clamp(240, size.width)
                        .toDouble();
                final double height =
                    (constraints.maxHeight - outerPadding)
                        .clamp(340, size.height)
                        .toDouble();
                final bool phoneFrame = size == PreviewSize.phone;
                return Center(
                  child: Container(
                    width: width,
                    height: height,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(phoneFrame ? 28 : 14),
                      border: Border.all(color: const Color(0xFFD8DBE4)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x160F172A),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<String>('preview-page-$activePageId'),
                      child: Theme(
                        data: ThemeData(
                          useMaterial3: true,
                          colorScheme: ColorScheme.fromSeed(
                            seedColor: Color(document.seedColor),
                          ),
                        ),
                        child: Material(
                          color: Colors.white,
                          child: _renderNode(_previewRoot),
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
        final BuilderNode? floatingButtonNode = _firstChildOfType(
          node,
          'floatingActionButton',
        );
        final List<BuilderNode> bodyNodes =
            node.children
                .where(
                  (BuilderNode child) =>
                      child.type != 'appBar' &&
                      child.type != 'floatingActionButton',
                )
                .toList();
        content = Scaffold(
          backgroundColor: Colors.white,
          appBar: appBarNode == null ? null : _renderAppBar(appBarNode),
          floatingActionButton:
              floatingButtonNode == null
                  ? null
                  : _renderFloatingActionButton(floatingButtonNode),
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
          child: GridView.count(
            crossAxisCount: count,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            padding: EdgeInsets.zero,
            children: node.children.map(_renderNode).toList(),
          ),
        );
        break;
      case 'pageView':
        content = SizedBox(
          width: _number(node.properties['width'], 300, 0, 1200),
          height: _number(node.properties['height'], 220, 0, 1200),
          child: PageView(children: node.children.map(_renderNode).toList()),
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
        content = Padding(
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
              color: Color(
                node.properties['color'] is int
                    ? node.properties['color']! as int
                    : 0xFF303644,
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
          'outlined' => OutlinedButton(
            onPressed: onPressed,
            child: Text(label),
          ),
          'text' => TextButton(onPressed: onPressed, child: Text(label)),
          _ => FilledButton(onPressed: onPressed, child: Text(label)),
        };
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
                    File(source),
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

    Widget laidOutContent = content;
    if (node.type != 'container' &&
        node.type != 'padding' &&
        _hasInsets(node, 'padding')) {
      laidOutContent = Padding(
        padding: _edgeInsets(node, 'padding'),
        child: laidOutContent,
      );
    }
    final double opacity = _number(node.properties['opacity'], 1, 0, 1);
    if (opacity < 1) {
      laidOutContent = Opacity(opacity: opacity, child: laidOutContent);
    }
    if (_hasInsets(node, 'margin')) {
      laidOutContent = Padding(
        padding: _edgeInsets(node, 'margin'),
        child: laidOutContent,
      );
    }
    if (node.properties['visible'] == false) {
      laidOutContent = Visibility(visible: false, child: laidOutContent);
    }

    final bool selected = node.id == selectedNodeId;
    final Widget selectableContent = GestureDetector(
      key: ValueKey<String>('preview-node-$activePageId-${node.id}'),
      behavior: HitTestBehavior.translucent,
      onTap: () => onSelect(node.id),
      child: laidOutContent,
    );

    Widget withSelectionBorder(bool isDropTarget) => DecoratedBox(
      decoration: BoxDecoration(
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
      ),
      child: selectableContent,
    );

    if (!node.acceptsChildren) return withSelectionBorder(false);
    return DragTarget<EditorDragData>(
      onWillAcceptWithDetails: (DragTargetDetails<EditorDragData> details) {
        final EditorDragData data = details.data;
        if (data is PaletteObjectDrag) return true;
        if (data case ExistingObjectDrag(:final nodeId)) {
          final BuilderNode? draggedNode = _previewRoot.findById(nodeId);
          return draggedNode != null &&
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

  Widget _renderFloatingActionButton(BuilderNode node) => FloatingActionButton(
    onPressed:
        BuilderAction.forNode(node).isNotEmpty && onRunActions != null
            ? () => onRunActions!(node)
            : () => onSelect(node.id),
    backgroundColor: Color(
      _integer(node.properties['backgroundColor'], 0xFF6750A4),
    ),
    foregroundColor: Color(
      _integer(node.properties['foregroundColor'], 0xFFFFFFFF),
    ),
    child: Icon(_icon(node.properties['iconName'])),
  );

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
