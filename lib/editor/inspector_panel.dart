import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/builder_action.dart';
import '../models/builder_document.dart';
import 'color_picker_dialog.dart';

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    required this.node,
    required this.seedColor,
    required this.onSetProperty,
    required this.onSetProperties,
    required this.onSetSeedColor,
    required this.onDeleteNode,
    this.onCreateVariable,
    this.pages = const <BuilderPage>[],
    this.variables = const <BuilderVariable>[],
    super.key,
  });

  final BuilderNode? node;
  final int seedColor;
  final void Function(String nodeId, String key, Object? value) onSetProperty;
  final void Function(String nodeId, Map<String, Object?> values)
  onSetProperties;
  final ValueChanged<int> onSetSeedColor;
  final VoidCallback onDeleteNode;
  final VoidCallback? onCreateVariable;
  final List<BuilderPage> pages;
  final List<BuilderVariable> variables;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  static const List<String> _sides = <String>['top', 'right', 'bottom', 'left'];

  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _linkedSpacing = <String, bool>{
    'padding': true,
    'margin': true,
  };
  String _query = '';

  @override
  void didUpdateWidget(covariant InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final BuilderNode? oldNode = oldWidget.node;
    final BuilderNode? newNode = widget.node;
    if (oldNode == null || newNode == null || oldNode.id != newNode.id) return;

    for (final String key in <String>{
      ...oldNode.properties.keys,
      ...newNode.properties.keys,
    }) {
      if (oldNode.properties[key] != newNode.properties[key]) {
        _syncController(newNode, key, newNode.properties[key]);
      }
    }
    for (final String prefix in <String>['padding', 'margin']) {
      for (final String side in _sides) {
        final double oldValue = _spacingValue(oldNode, prefix, side);
        final double newValue = _spacingValue(newNode, prefix, side);
        if (oldValue != newValue) {
          _syncController(newNode, '$prefix${_capitalized(side)}', newValue);
        }
      }
    }
  }

  void _syncController(BuilderNode node, String property, Object? value) {
    final TextEditingController? controller =
        _controllers[_fieldKey(node.id, property)];
    final String nextValue = _valueText(value);
    if (controller != null && controller.text != nextValue) {
      controller.value = TextEditingValue(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BuilderNode? node = widget.node;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: _InspectorHeading(title: 'Properties', icon: Icons.tune),
              ),
              if (node != null && node.type != 'scaffold')
                IconButton(
                  tooltip: 'Delete selected object',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDeleteNode,
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (node == null)
            const Text(
              'Select an object on the canvas or in the widget tree to edit it.',
              style: TextStyle(color: Color(0xFF737B8A), fontSize: 12),
            )
          else ...<Widget>[
            _selectedObjectCard(node),
            const SizedBox(height: 10),
            _searchField(),
            const SizedBox(height: 5),
            ..._propertiesFor(node),
          ],
          if (_matches('theme primary color')) ...<Widget>[
            const Divider(height: 20),
            ExpansionTile(
              key: const ValueKey<String>('inspector-theme'),
              initiallyExpanded: _query.isNotEmpty,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              leading: const Icon(
                Icons.palette_outlined,
                size: 17,
                color: Color(0xFF6E7482),
              ),
              title: const Text('Theme'),
              children: <Widget>[
                _fieldLabel('Primary color'),
                const SizedBox(height: 8),
                ColorPickerField(
                  color: Color(widget.seedColor),
                  onChanged:
                      (Color value) => widget.onSetSeedColor(value.toARGB32()),
                ),
                const SizedBox(height: 7),
                Text(
                  '#${widget.seedColor.toRadixString(16).substring(2).toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFF737B8A),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchField() => TextField(
    key: const ValueKey<String>('property-search'),
    controller: _searchController,
    onChanged:
        (String value) => setState(() => _query = value.trim().toLowerCase()),
    decoration: _inputDecoration(hintText: 'Search properties...').copyWith(
      prefixIcon: const Icon(Icons.search, size: 17),
      prefixIconConstraints: const BoxConstraints(minWidth: 35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
    ),
    style: const TextStyle(fontSize: 11),
  );

  Widget _selectedObjectCard(BuilderNode node) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E6EB)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.widgets_outlined,
            size: 17,
            color: Color(0xFF6750A4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _typeLabel(node.type),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            node.id,
            style: const TextStyle(fontSize: 9, color: Color(0xFF8A909D)),
          ),
        ],
      ),
    );
  }

  List<Widget> _propertiesFor(BuilderNode node) {
    final List<Widget> sections = <Widget>[];
    void add(
      String title,
      String searchTerms,
      List<Widget> children, {
      bool expanded = false,
    }) {
      if (_matches('$title $searchTerms')) {
        sections.add(
          _section(node, title, children, initiallyExpanded: expanded),
        );
      }
    }

    add(
      'Visibility',
      'visible opacity conditional',
      _visibilityProperties(node),
      expanded: true,
    );
    add(
      'Variable bindings',
      'app state variable bind text label visibility opacity size',
      _bindingsProperties(node),
    );
    add('Padding', 'top right bottom left spacing inset', <Widget>[
      _spacingEditor(node, 'padding'),
    ], expanded: node.type == 'container');
    add('Margin', 'top right bottom left spacing outside', <Widget>[
      _spacingEditor(node, 'margin'),
    ], expanded: node.type == 'container');

    if (node.type == 'container') {
      add(
        'Size',
        'width height dimensions',
        _containerSizeProperties(node),
        expanded: true,
      );
      add(
        'Alignment',
        'align child position',
        _containerAlignmentProperties(node),
      );
      add(
        'Decoration',
        'radius corner fill background color',
        _containerStyleProperties(node),
      );
    }
    if (<String>{'card', 'padding'}.contains(node.type)) {
      add(
        'Size',
        'width height dimensions',
        _sizeProperties(node),
        expanded: true,
      );
      if (node.type == 'card') {
        add(
          'Decoration',
          'radius corner fill background color elevation',
          _cardProperties(node),
        );
      }
      if (node.type == 'padding' && node.children.isNotEmpty) {
        add(
          'Children',
          'nested child objects layout',
          _childrenSummary(node),
          expanded: true,
        );
      }
    }
    if (<String>{
      'stack',
      'listView',
      'gridView',
      'pageView',
      'swipeableStack',
    }.contains(node.type)) {
      add(
        'Size',
        'width height dimensions',
        _sizeProperties(node),
        expanded: true,
      );
      if (node.type == 'stack')
        add('Layout', 'alignment fit stack children', _stackProperties(node));
      if (node.type == 'listView')
        add('List', 'scroll direction spacing', _listProperties(node));
      if (node.type == 'gridView')
        add('Grid', 'cross axis count spacing', _gridProperties(node));
      if (node.type == 'swipeableStack')
        add('Swipeable Stack', 'loop visible cards', _swipeProperties(node));
      if (node.children.isNotEmpty)
        add(
          'Children',
          'nested child objects layout',
          _childrenSummary(node),
          expanded: true,
        );
    }
    if (node.type == 'image') {
      add(
        'Image',
        'source file path local asset dimensions size fit',
        _imageProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'icon') {
      add(
        'Icon',
        'icon symbol size color',
        _iconProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'divider' || node.type == 'verticalDivider') {
      add(
        'Divider',
        'thickness color indent spacing width height',
        _dividerProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'signature') {
      add(
        'Signature',
        'width height pen stroke background color',
        _signatureProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'textField') {
      add(
        'Content',
        'label hint placeholder',
        _textFieldProperties(node),
        expanded: true,
      );
      add('Size', 'width dimensions', <Widget>[
        _numberField(node, 'width', label: 'Width', fallback: 240),
      ]);
    }
    if (node.type == 'checkbox' || node.type == 'switch') {
      add(
        'Content',
        'label value active color',
        _toggleProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'appBar') {
      add('Content', 'title text', <Widget>[
        _fieldLabel('Title'),
        const SizedBox(height: 5),
        _textField(node, 'title', hintText: 'App bar title'),
      ], expanded: true);
      add(
        'Style',
        'background foreground color elevation',
        _appBarProperties(node),
      );
    }
    if (node.type == 'floatingActionButton') {
      add(
        'Icon',
        'symbol icon',
        _floatingButtonProperties(node),
        expanded: true,
      );
      add(
        'Style',
        'background foreground color',
        _floatingButtonStyleProperties(node),
      );
      add(
        'Actions',
        'on tap navigate snackbar alert dialog back',
        _actionsProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'text') {
      add(
        'Content',
        'text string',
        _textContentProperties(node),
        expanded: true,
      );
      add(
        'Typography',
        'font size weight text color',
        _textStyleProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'button') {
      add(
        'Content',
        'button label title',
        _buttonContentProperties(node),
        expanded: true,
      );
      add(
        'Style',
        'filled outlined text button style',
        _buttonStyleProperties(node),
        expanded: true,
      );
      add(
        'Actions',
        'on tap navigate snackbar alert dialog back',
        _actionsProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'column' || node.type == 'row') {
      add(
        'Alignment',
        'main axis cross axis horizontal vertical',
        _flexProperties(node),
        expanded: true,
      );
    }
    if (node.type == 'container' && node.children.isNotEmpty) {
      add('Children', 'nested child objects layout', <Widget>[
        Text(
          'This container holds ${node.children.length} child object(s).',
          style: const TextStyle(
            color: Color(0xFF737B8A),
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ], expanded: true);
    }
    if (sections.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'No properties match this search.',
            style: TextStyle(color: Color(0xFF737B8A), fontSize: 11),
          ),
        ),
      ];
    }
    return sections;
  }

  Widget _section(
    BuilderNode node,
    String title,
    List<Widget> children, {
    bool initiallyExpanded = false,
  }) => ExpansionTile(
    key: ValueKey<String>('inspector-${node.id}-$title'),
    initiallyExpanded: initiallyExpanded || _query.isNotEmpty,
    tilePadding: const EdgeInsets.symmetric(horizontal: 3),
    childrenPadding: const EdgeInsets.fromLTRB(5, 0, 5, 12),
    visualDensity: VisualDensity.compact,
    iconColor: const Color(0xFF747B89),
    collapsedIconColor: const Color(0xFF747B89),
    title: Text(
      title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    children: children,
  );

  List<Widget> _visibilityProperties(BuilderNode node) => <Widget>[
    SwitchListTile.adaptive(
      key: ValueKey<String>('${node.id}-visible'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Visible', style: TextStyle(fontSize: 11)),
      value: node.properties['visible'] != false,
      onChanged:
          (bool value) => widget.onSetProperty(node.id, 'visible', value),
    ),
    Row(
      children: <Widget>[
        const SizedBox(
          width: 58,
          child: Text('Opacity', style: TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            key: ValueKey<String>('${node.id}-opacity-slider'),
            value: _number(node.properties['opacity'], 1, 0, 1),
            onChanged:
                (double value) =>
                    widget.onSetProperty(node.id, 'opacity', value),
          ),
        ),
        SizedBox(
          width: 52,
          child: _compactNumberField(node, 'opacity', fallback: 1, max: 1),
        ),
      ],
    ),
  ];

  Widget _spacingEditor(BuilderNode node, String prefix) {
    final bool linked = _linkedSpacing[prefix] ?? true;
    Widget sideField(String side) => SizedBox(
      width: 68,
      child: TextField(
        key: ValueKey<String>('${node.id}-$prefix${_capitalized(side)}'),
        controller: _controllerFor(
          node,
          '$prefix${_capitalized(side)}',
          fallback: _spacingValue(node, prefix, side),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
        decoration: _inputDecoration(hintText: _sideLabel(side)).copyWith(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 8,
          ),
        ),
        onChanged: (String text) {
          final double? value = double.tryParse(text);
          if (value == null || !value.isFinite) return;
          _setSpacing(node, prefix, side, value.clamp(0, 1200));
        },
      ),
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E4EA)),
      ),
      child: Column(
        children: <Widget>[
          Center(child: sideField('top')),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              sideField('left'),
              IconButton(
                tooltip:
                    linked ? 'Unlink spacing values' : 'Link spacing values',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                padding: EdgeInsets.zero,
                onPressed:
                    () => setState(() => _linkedSpacing[prefix] = !linked),
                icon: Icon(
                  linked ? Icons.link : Icons.link_off,
                  size: 16,
                  color:
                      linked
                          ? const Color(0xFF6750A4)
                          : const Color(0xFF737B8A),
                ),
              ),
              sideField('right'),
            ],
          ),
          const SizedBox(height: 6),
          Center(child: sideField('bottom')),
          const SizedBox(height: 5),
          Text(
            linked ? 'All sides linked' : 'Top · Right · Bottom · Left',
            style: const TextStyle(fontSize: 9, color: Color(0xFF828997)),
          ),
        ],
      ),
    );
  }

  void _setSpacing(BuilderNode node, String prefix, String side, double value) {
    final Map<String, Object?> values = <String, Object?>{};
    if (_linkedSpacing[prefix] ?? true) {
      for (final String linkedSide in _sides) {
        values['$prefix${_capitalized(linkedSide)}'] = value;
      }
    } else {
      values['$prefix${_capitalized(side)}'] = value;
    }
    widget.onSetProperties(node.id, values);
  }

  double _spacingValue(BuilderNode node, String prefix, String side) {
    final Object? value = node.properties['$prefix${_capitalized(side)}'];
    if (value is num && value.isFinite) return value.toDouble().clamp(0, 1200);
    return _number(node.properties[prefix], 0, 0, 1200);
  }

  List<Widget> _containerSizeProperties(BuilderNode node) => <Widget>[
    Row(
      children: <Widget>[
        Expanded(
          child: _numberField(node, 'width', label: 'Width', fallback: 220),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _numberField(node, 'height', label: 'Height', fallback: 100),
        ),
      ],
    ),
  ];

  List<Widget> _sizeProperties(BuilderNode node) => <Widget>[
    Row(
      children: <Widget>[
        Expanded(
          child: _numberField(node, 'width', label: 'Width', fallback: 300),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _numberField(node, 'height', label: 'Height', fallback: 220),
        ),
      ],
    ),
  ];

  List<Widget> _cardProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Corner radius'),
    const SizedBox(height: 5),
    _numberField(node, 'borderRadius', label: 'Radius', fallback: 12),
    const SizedBox(height: 10),
    _fieldLabel('Elevation'),
    const SizedBox(height: 5),
    _numberField(node, 'elevation', label: 'Elevation', fallback: 2),
    const SizedBox(height: 10),
    _fieldLabel('Card color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['backgroundColor'], 0xFFFFFFFF)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'backgroundColor',
            value.toARGB32(),
          ),
    ),
  ];

  List<Widget> _childrenSummary(BuilderNode node) => <Widget>[
    Text(
      'This ${_typeLabel(node.type).toLowerCase()} holds ${node.children.length} child object(s).',
      style: const TextStyle(
        color: Color(0xFF737B8A),
        fontSize: 11,
        height: 1.4,
      ),
    ),
  ];

  List<Widget> _stackProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Stack alignment'),
    const SizedBox(height: 5),
    _alignmentDropdown(node, 'alignment'),
    const SizedBox(height: 10),
    _fieldLabel('Sizing'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('stack-fit-${node.id}'),
      initialValue: node.properties['fit'] == 'expand' ? 'expand' : 'loose',
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'loose', child: Text('Loose')),
        DropdownMenuItem(value: 'expand', child: Text('Expand')),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'fit', value);
      },
    ),
  ];

  List<Widget> _listProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Scroll direction'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('list-direction-${node.id}'),
      initialValue:
          node.properties['scrollDirection'] == 'horizontal'
              ? 'horizontal'
              : 'vertical',
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'vertical', child: Text('Vertical')),
        DropdownMenuItem(value: 'horizontal', child: Text('Horizontal')),
      ],
      onChanged: (String? value) {
        if (value != null)
          widget.onSetProperty(node.id, 'scrollDirection', value);
      },
    ),
    const SizedBox(height: 10),
    _numberField(node, 'itemSpacing', label: 'Item spacing', fallback: 8),
  ];

  List<Widget> _gridProperties(BuilderNode node) => <Widget>[
    _numberField(node, 'crossAxisCount', label: 'Columns', fallback: 2),
    const SizedBox(height: 10),
    _numberField(node, 'itemSpacing', label: 'Cell spacing', fallback: 8),
  ];

  List<Widget> _swipeProperties(BuilderNode node) => <Widget>[
    _numberField(node, 'visibleCount', label: 'Visible cards', fallback: 3),
    SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Loop cards', style: TextStyle(fontSize: 11)),
      value: node.properties['loop'] == true,
      onChanged: (bool value) => widget.onSetProperty(node.id, 'loop', value),
    ),
  ];

  List<Widget> _imageProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Local image path'),
    const SizedBox(height: 5),
    _textField(node, 'source', hintText: r'C:\path\to\image.png'),
    const SizedBox(height: 10),
    _fieldLabel('Image fit'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('image-fit-${node.id}'),
      initialValue: _fitValue(node.properties['fit']),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'cover', child: Text('Cover')),
        DropdownMenuItem(value: 'contain', child: Text('Contain')),
        DropdownMenuItem(value: 'fill', child: Text('Fill')),
        DropdownMenuItem(value: 'fitWidth', child: Text('Fit width')),
        DropdownMenuItem(value: 'fitHeight', child: Text('Fit height')),
        DropdownMenuItem(value: 'scaleDown', child: Text('Scale down')),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'fit', value);
      },
    ),
    const SizedBox(height: 10),
    ..._sizeProperties(node),
  ];

  List<Widget> _iconProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Icon'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('icon-name-${node.id}'),
      initialValue: _iconName(node.properties['iconName']),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'star', child: Text('Star')),
        DropdownMenuItem(value: 'home', child: Text('Home')),
        DropdownMenuItem(value: 'search', child: Text('Search')),
        DropdownMenuItem(value: 'favorite', child: Text('Favorite')),
        DropdownMenuItem(value: 'settings', child: Text('Settings')),
        DropdownMenuItem(value: 'person', child: Text('Person')),
        DropdownMenuItem(value: 'add', child: Text('Add')),
        DropdownMenuItem(value: 'check', child: Text('Check')),
        DropdownMenuItem(value: 'menu', child: Text('Menu')),
        DropdownMenuItem(value: 'arrowForward', child: Text('Arrow forward')),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'iconName', value);
      },
    ),
    const SizedBox(height: 10),
    _numberField(node, 'size', label: 'Size', fallback: 32),
    const SizedBox(height: 10),
    _fieldLabel('Color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['color'], 0xFF6750A4)),
      onChanged:
          (Color value) =>
              widget.onSetProperty(node.id, 'color', value.toARGB32()),
    ),
  ];

  List<Widget> _dividerProperties(BuilderNode node) => <Widget>[
    Row(
      children: <Widget>[
        Expanded(
          child: _numberField(
            node,
            'thickness',
            label: 'Thickness',
            fallback: 1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _numberField(
            node,
            node.type == 'divider' ? 'height' : 'width',
            label: node.type == 'divider' ? 'Height' : 'Width',
            fallback: 24,
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    Row(
      children: <Widget>[
        Expanded(
          child: _numberField(node, 'indent', label: 'Indent', fallback: 0),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _numberField(
            node,
            'endIndent',
            label: 'End indent',
            fallback: 0,
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    _fieldLabel('Color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['color'], 0xFFB8BEC9)),
      onChanged:
          (Color value) =>
              widget.onSetProperty(node.id, 'color', value.toARGB32()),
    ),
  ];

  List<Widget> _signatureProperties(BuilderNode node) => <Widget>[
    ..._sizeProperties(node),
    const SizedBox(height: 10),
    _numberField(node, 'strokeWidth', label: 'Stroke width', fallback: 2),
    const SizedBox(height: 10),
    _fieldLabel('Pen color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['penColor'], 0xFF20242C)),
      onChanged:
          (Color value) =>
              widget.onSetProperty(node.id, 'penColor', value.toARGB32()),
    ),
    const SizedBox(height: 10),
    _fieldLabel('Canvas color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['backgroundColor'], 0xFFFFFFFF)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'backgroundColor',
            value.toARGB32(),
          ),
    ),
  ];

  List<Widget> _textFieldProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Initial value'),
    const SizedBox(height: 5),
    _textField(node, 'initialValue'),
    const SizedBox(height: 10),
    _fieldLabel('Label'),
    const SizedBox(height: 5),
    _textField(node, 'label'),
    const SizedBox(height: 10),
    _fieldLabel('Hint text'),
    const SizedBox(height: 5),
    _textField(node, 'hintText'),
    const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Text(
        r'Insert app variables with ${variableName} or $variableName.',
        style: TextStyle(fontSize: 10, color: Color(0xFF737B8A)),
      ),
    ),
  ];

  List<Widget> _toggleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Label'),
    const SizedBox(height: 5),
    _textField(node, 'label'),
    SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Initially selected', style: TextStyle(fontSize: 11)),
      value: node.properties['value'] == true,
      onChanged: (bool value) => widget.onSetProperty(node.id, 'value', value),
    ),
    _fieldLabel('Active color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['activeColor'], 0xFF6750A4)),
      onChanged:
          (Color value) =>
              widget.onSetProperty(node.id, 'activeColor', value.toARGB32()),
    ),
  ];

  List<Widget> _appBarProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Background color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['backgroundColor'], 0xFF6750A4)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'backgroundColor',
            value.toARGB32(),
          ),
    ),
    const SizedBox(height: 10),
    _fieldLabel('Foreground color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['foregroundColor'], 0xFFFFFFFF)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'foregroundColor',
            value.toARGB32(),
          ),
    ),
    const SizedBox(height: 10),
    _numberField(node, 'elevation', label: 'Elevation', fallback: 2),
  ];

  List<Widget> _floatingButtonProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Icon'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('fab-icon-${node.id}'),
      initialValue: _iconName(node.properties['iconName']),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'add', child: Text('Add')),
        DropdownMenuItem(value: 'check', child: Text('Check')),
        DropdownMenuItem(value: 'home', child: Text('Home')),
        DropdownMenuItem(value: 'search', child: Text('Search')),
        DropdownMenuItem(value: 'favorite', child: Text('Favorite')),
        DropdownMenuItem(value: 'settings', child: Text('Settings')),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'iconName', value);
      },
    ),
  ];

  List<Widget> _floatingButtonStyleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Background color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['backgroundColor'], 0xFF6750A4)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'backgroundColor',
            value.toARGB32(),
          ),
    ),
    const SizedBox(height: 10),
    _fieldLabel('Foreground color'),
    const SizedBox(height: 6),
    ColorPickerField(
      color: Color(_integer(node.properties['foregroundColor'], 0xFFFFFFFF)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'foregroundColor',
            value.toARGB32(),
          ),
    ),
  ];

  Widget _alignmentDropdown(BuilderNode node, String property) =>
      DropdownButtonFormField<String>(
        key: ValueKey<String>('${property}-${node.id}'),
        initialValue: _containerAlignment(node.properties[property]),
        decoration: _inputDecoration(),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'topLeft', child: Text('Top left')),
          DropdownMenuItem(value: 'topCenter', child: Text('Top center')),
          DropdownMenuItem(value: 'topRight', child: Text('Top right')),
          DropdownMenuItem(value: 'centerLeft', child: Text('Center left')),
          DropdownMenuItem(value: 'center', child: Text('Center')),
          DropdownMenuItem(value: 'centerRight', child: Text('Center right')),
          DropdownMenuItem(value: 'bottomLeft', child: Text('Bottom left')),
          DropdownMenuItem(value: 'bottomCenter', child: Text('Bottom center')),
          DropdownMenuItem(value: 'bottomRight', child: Text('Bottom right')),
        ],
        onChanged: (String? value) {
          if (value != null) widget.onSetProperty(node.id, property, value);
        },
      );

  String _fitValue(Object? value) =>
      const <String>{
            'cover',
            'contain',
            'fill',
            'fitWidth',
            'fitHeight',
            'scaleDown',
          }.contains(value)
          ? value! as String
          : 'cover';
  String _iconName(Object? value) =>
      const <String>{
            'star',
            'home',
            'search',
            'favorite',
            'settings',
            'person',
            'add',
            'check',
            'menu',
            'arrowForward',
          }.contains(value)
          ? value! as String
          : 'star';

  List<Widget> _containerAlignmentProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Child alignment'),
    const SizedBox(height: 6),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('alignment-${node.id}'),
      initialValue: _containerAlignment(node.properties['alignment']),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'topLeft', child: Text('Top left')),
        DropdownMenuItem(value: 'topCenter', child: Text('Top center')),
        DropdownMenuItem(value: 'topRight', child: Text('Top right')),
        DropdownMenuItem(value: 'centerLeft', child: Text('Center left')),
        DropdownMenuItem(value: 'center', child: Text('Center')),
        DropdownMenuItem(value: 'centerRight', child: Text('Center right')),
        DropdownMenuItem(value: 'bottomLeft', child: Text('Bottom left')),
        DropdownMenuItem(value: 'bottomCenter', child: Text('Bottom center')),
        DropdownMenuItem(value: 'bottomRight', child: Text('Bottom right')),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'alignment', value);
      },
    ),
  ];

  List<Widget> _containerStyleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Corner radius'),
    const SizedBox(height: 6),
    _numberField(node, 'borderRadius', label: 'Radius', fallback: 12),
    const SizedBox(height: 12),
    _fieldLabel('Fill color'),
    const SizedBox(height: 7),
    ColorPickerField(
      color: Color(_integer(node.properties['backgroundColor'], 0xFFF1EFF8)),
      onChanged:
          (Color value) => widget.onSetProperty(
            node.id,
            'backgroundColor',
            value.toARGB32(),
          ),
    ),
  ];

  List<Widget> _textContentProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Text'),
    const SizedBox(height: 6),
    _textField(node, 'text', hintText: 'Enter text', minLines: 2, maxLines: 4),
    const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Text(
        r'Insert app variables with ${variableName} or $variableName.',
        style: TextStyle(fontSize: 10, color: Color(0xFF737B8A)),
      ),
    ),
  ];

  List<Widget> _textStyleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Font size'),
    const SizedBox(height: 6),
    DropdownButtonFormField<double>(
      key: ValueKey<String>('fontSize-${node.id}'),
      initialValue: _fontSize(node),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<double>>[
        DropdownMenuItem<double>(value: 14, child: Text('14 px')),
        DropdownMenuItem<double>(value: 16, child: Text('16 px')),
        DropdownMenuItem<double>(value: 18, child: Text('18 px')),
        DropdownMenuItem<double>(value: 20, child: Text('20 px')),
        DropdownMenuItem<double>(value: 24, child: Text('24 px')),
        DropdownMenuItem<double>(value: 26, child: Text('26 px')),
        DropdownMenuItem<double>(value: 32, child: Text('32 px')),
        DropdownMenuItem<double>(value: 40, child: Text('40 px')),
        DropdownMenuItem<double>(value: 48, child: Text('48 px')),
      ],
      onChanged: (double? value) {
        if (value != null) widget.onSetProperty(node.id, 'fontSize', value);
      },
    ),
    const SizedBox(height: 12),
    _fieldLabel('Weight'),
    const SizedBox(height: 6),
    SegmentedButton<String>(
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'regular', label: Text('Regular')),
        ButtonSegment<String>(value: 'bold', label: Text('Bold')),
      ],
      selected: <String>{
        node.properties['fontWeight'] == 'bold' ? 'bold' : 'regular',
      },
      onSelectionChanged: (Set<String> selected) {
        widget.onSetProperty(node.id, 'fontWeight', selected.first);
      },
    ),
    const SizedBox(height: 12),
    _fieldLabel('Text color'),
    const SizedBox(height: 7),
    ColorPickerField(
      color: Color(_integer(node.properties['color'], 0xFF303644)),
      onChanged:
          (Color value) =>
              widget.onSetProperty(node.id, 'color', value.toARGB32()),
    ),
  ];

  List<Widget> _buttonContentProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Button label'),
    const SizedBox(height: 6),
    _textField(node, 'label', hintText: 'Button label'),
  ];

  List<Widget> _actionsProperties(BuilderNode node) {
    final List<Map<String, Object?>> actions = BuilderAction.forNode(node);
    return <Widget>[
      if (actions.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'No actions yet. Add a step to define what happens when this widget is pressed.',
            style: TextStyle(
              color: Color(0xFF737B8A),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      for (int index = 0; index < actions.length; index++)
        _actionCard(node, actions[index], index),
      Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<String>(
          tooltip: 'Add action',
          onSelected: (String type) {
            final List<Map<String, Object?>> next =
                List<Map<String, Object?>>.of(BuilderAction.forNode(node));
            int sequence = next.length + 1;
            final Set<String> ids =
                next
                    .map(
                      (Map<String, Object?> action) =>
                          action['id'] as String? ?? '',
                    )
                    .toSet();
            String id = '${node.id}_action_$sequence';
            while (ids.contains(id)) {
              sequence++;
              id = '${node.id}_action_$sequence';
            }
            next.add(BuilderAction.create(id, type));
            widget.onSetProperty(node.id, 'actions', next);
          },
          itemBuilder:
              (BuildContext context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'navigate',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.open_in_new, size: 17),
                    title: Text('Navigate to page'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'snackbar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.notifications_outlined, size: 17),
                    title: Text('Show snackbar'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'dialog',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.chat_bubble_outline, size: 17),
                    title: Text('Show alert dialog'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'back',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.arrow_back, size: 17),
                    title: Text('Navigate back'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'setVariable',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined, size: 17),
                    title: Text('Set app variable'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'incrementVariable',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.add_circle_outline, size: 17),
                    title: Text('Increment number variable'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'toggleVariable',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.toggle_on_outlined, size: 17),
                    title: Text('Toggle boolean variable'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'updateWidget',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.widgets_outlined, size: 17),
                    title: Text('Update another widget'),
                  ),
                ),
              ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9F8),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.add, size: 15, color: Color(0xFF6750A4)),
                SizedBox(width: 5),
                Text(
                  'Add action',
                  style: TextStyle(
                    color: Color(0xFF6750A4),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _bindingsProperties(BuilderNode node) {
    final Map<String, Object?> bindings = _bindingsFor(node);
    final List<Widget> rows = <Widget>[];
    if (widget.variables.isEmpty) {
      rows.addAll(<Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 7),
          child: Text(
            'Create an app variable to bind this widget to changing state.',
            style: TextStyle(fontSize: 10, color: Color(0xFF737B8A)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onCreateVariable,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create app variable'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 5),
      ]);
    }
    if (node.type == 'text') {
      rows.add(_bindingDropdown(node, bindings, 'text', 'Text', 'text'));
    }
    if (node.type == 'button' ||
        node.type == 'textField' ||
        node.type == 'checkbox' ||
        node.type == 'switch') {
      rows.add(_bindingDropdown(node, bindings, 'label', 'Label', 'text'));
    }
    if (node.type == 'textField') {
      rows.add(
        _bindingDropdown(
          node,
          bindings,
          'initialValue',
          'Initial value',
          'text',
        ),
      );
    }
    rows.add(_bindingDropdown(node, bindings, 'visible', 'Visible', 'boolean'));
    rows.add(_bindingDropdown(node, bindings, 'opacity', 'Opacity', 'number'));
    if (rows.isEmpty) {
      rows.add(const Text('No bindable properties for this widget.'));
    }
    return rows;
  }

  Map<String, Object?> _bindingsFor(BuilderNode node) {
    final Object? raw = node.properties['bindings'];
    if (raw is! Map) return <String, Object?>{};
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        entry.key.toString(): entry.value,
    };
  }

  Widget _bindingDropdown(
    BuilderNode node,
    Map<String, Object?> bindings,
    String property,
    String label,
    String type,
  ) {
    final List<BuilderVariable> options =
        widget.variables
            .where(
              (BuilderVariable item) => switch (type) {
                'text' => true,
                'number' => <String>{
                  'number',
                  'integer',
                  'double',
                }.contains(item.type),
                _ => item.type == type,
              },
            )
            .toList();
    final String? rawSelected = bindings[property] as String?;
    final String selected =
        options.any((BuilderVariable item) => item.id == rawSelected)
            ? rawSelected!
            : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 1, bottom: 4),
            child: Text(
              '$label from app variable',
              style: const TextStyle(
                color: Color(0xFF737B8A),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(
              'binding-${node.id}-$property-$selected-${options.length}',
            ),
            initialValue: selected,
            isExpanded: true,
            decoration: _inputDecoration(),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Use fixed value'),
              ),
              ...options.map(
                (BuilderVariable variable) => DropdownMenuItem<String>(
                  value: variable.id,
                  child: Text(variable.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (String? value) {
              final Map<String, Object?> next = Map<String, Object?>.of(
                bindings,
              );
              if (value == null || value.isEmpty) {
                next.remove(property);
              } else {
                next[property] = value;
              }
              widget.onSetProperty(
                node.id,
                'bindings',
                next.isEmpty ? null : next,
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _variableActionFields(
    BuilderNode node,
    String actionId,
    Map<String, Object?> action,
    String type,
  ) {
    final String wantedType = switch (type) {
      'incrementVariable' => 'number',
      'toggleVariable' => 'boolean',
      _ => '',
    };
    final List<BuilderVariable> variables =
        widget.variables
            .where(
              (BuilderVariable variable) =>
                  wantedType.isEmpty ||
                  (wantedType == 'number'
                      ? <String>{
                        'number',
                        'integer',
                        'double',
                      }.contains(variable.type)
                      : variable.type == wantedType),
            )
            .toList();
    final String currentId = action['variableId'] as String? ?? '';
    final BuilderVariable? variable = variables
        .cast<BuilderVariable?>()
        .firstWhere(
          (BuilderVariable? item) => item?.id == currentId,
          orElse: () => null,
        );
    return <Widget>[
      DropdownButtonFormField<String>(
        key: ValueKey<String>(
          'action-variable-$actionId-$currentId-${variables.length}',
        ),
        initialValue:
            variables.any((BuilderVariable item) => item.id == currentId)
                ? currentId
                : '',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'App variable'),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Choose a variable'),
          ),
          ...variables.map(
            (BuilderVariable item) => DropdownMenuItem<String>(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (String? value) {
          if (value == null) return;
          final BuilderVariable? selected = _firstOrNull<BuilderVariable>(
            variables.where((BuilderVariable item) => item.id == value),
          );
          _setActionValues(node, actionId, <String, Object?>{
            'variableId': value,
            if (type == 'setVariable' && selected != null)
              'value': selected.initialValue,
          });
        },
      ),
      if (type == 'setVariable' && variable != null) ...<Widget>[
        const SizedBox(height: 8),
        if (variable.type == 'boolean')
          DropdownButtonFormField<bool>(
            key: ValueKey<String>('action-bool-$actionId-${action['value']}'),
            initialValue: action['value'] == true,
            decoration: _inputDecoration(labelText: 'New value'),
            items: const <DropdownMenuItem<bool>>[
              DropdownMenuItem<bool>(value: true, child: Text('True')),
              DropdownMenuItem<bool>(value: false, child: Text('False')),
            ],
            onChanged: (bool? value) {
              if (value != null)
                _setActionValue(node, actionId, 'value', value);
            },
          )
        else if (<String>{
          'number',
          'integer',
          'double',
        }.contains(variable.type))
          _actionNumberField(node, actionId, action, 'value', 'New value')
        else
          _actionTextField(
            node,
            actionId,
            action,
            'value',
            variable.type == 'json' || variable.type == 'stringList'
                ? 'New value (JSON)'
                : 'New value',
            maxLines:
                variable.type == 'json' || variable.type == 'stringList'
                    ? 4
                    : 1,
          ),
      ],
      if (type == 'incrementVariable') ...<Widget>[
        const SizedBox(height: 8),
        _actionNumberField(node, actionId, action, 'amount', 'Increment by'),
      ],
    ];
  }

  List<Widget> _updateWidgetActionFields(
    BuilderNode source,
    String actionId,
    Map<String, Object?> action,
  ) {
    final String pageId = action['targetPageId'] as String? ?? 'home';
    final BuilderPage? page = _firstOrNull<BuilderPage>(
      widget.pages.where((BuilderPage item) => item.id == pageId),
    );
    final List<BuilderNode> targets =
        page?.root.depthFirst().toList() ?? <BuilderNode>[];
    final String targetId = action['targetNodeId'] as String? ?? '';
    final BuilderNode? target = _firstOrNull<BuilderNode>(
      targets.where((BuilderNode item) => item.id == targetId),
    );
    final List<String> properties = <String>[
      'visible',
      'opacity',
      if (target?.type == 'text') 'text',
      if (target?.type == 'textField') 'initialValue',
      if (<String>{
        'button',
        'textField',
        'checkbox',
        'switch',
      }.contains(target?.type))
        'label',
    ];
    final String property = action['property'] as String? ?? 'visible';
    return <Widget>[
      DropdownButtonFormField<String>(
        key: ValueKey<String>('action-target-page-$actionId-$pageId'),
        initialValue:
            widget.pages.any((BuilderPage item) => item.id == pageId)
                ? pageId
                : 'home',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Target page'),
        items:
            widget.pages
                .map(
                  (BuilderPage item) => DropdownMenuItem<String>(
                    value: item.id,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
        onChanged: (String? value) {
          if (value == null) return;
          final BuilderPage? nextPage = _firstOrNull<BuilderPage>(
            widget.pages.where((BuilderPage item) => item.id == value),
          );
          _setActionValues(source, actionId, <String, Object?>{
            'targetPageId': value,
            'targetNodeId': nextPage?.root.id ?? '',
            'property': 'visible',
            'value': true,
          });
        },
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey<String>('action-target-node-$actionId-$pageId-$targetId'),
        initialValue:
            targets.any((BuilderNode item) => item.id == targetId)
                ? targetId
                : '',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Target widget'),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Choose a widget'),
          ),
          ...targets.map(
            (BuilderNode item) => DropdownMenuItem<String>(
              value: item.id,
              child: Text(
                '${item.type} · ${item.id}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (String? value) {
          if (value != null) {
            final BuilderNode? nextTarget = _firstOrNull<BuilderNode>(
              targets.where((BuilderNode item) => item.id == value),
            );
            final String nextProperty =
                nextTarget?.type == 'text' ? 'text' : 'visible';
            _setActionValues(source, actionId, <String, Object?>{
              'targetNodeId': value,
              'property': nextProperty,
              'value': _defaultWidgetActionValue(nextTarget, nextProperty),
            });
          }
        },
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey<String>(
          'action-target-property-$actionId-$property-${properties.join('-')}',
        ),
        initialValue: properties.contains(property) ? property : 'visible',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Property to update'),
        items:
            properties
                .map(
                  (String item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(switch (item) {
                      'visible' => 'Visibility',
                      'opacity' => 'Opacity',
                      'text' => 'Text',
                      'initialValue' => 'Initial value',
                      _ => 'Label',
                    }),
                  ),
                )
                .toList(),
        onChanged: (String? value) {
          if (value != null) {
            _setActionValues(source, actionId, <String, Object?>{
              'property': value,
              'value': _defaultWidgetActionValue(target, value),
            });
          }
        },
      ),
      const SizedBox(height: 8),
      if (property == 'visible')
        DropdownButtonFormField<bool>(
          key: ValueKey<String>(
            'action-target-bool-$actionId-${action['value']}',
          ),
          initialValue: action['value'] == true,
          decoration: _inputDecoration(labelText: 'New value'),
          items: const <DropdownMenuItem<bool>>[
            DropdownMenuItem<bool>(value: true, child: Text('Visible')),
            DropdownMenuItem<bool>(value: false, child: Text('Hidden')),
          ],
          onChanged: (bool? value) {
            if (value != null)
              _setActionValue(source, actionId, 'value', value);
          },
        )
      else if (property == 'opacity')
        _actionNumberField(
          source,
          actionId,
          action,
          'value',
          'Opacity (0 to 1)',
          maximum: 1,
        )
      else
        _actionTextField(
          source,
          actionId,
          action,
          'value',
          property == 'text'
              ? 'Text value'
              : property == 'initialValue'
              ? 'Initial value'
              : 'Label value',
        ),
    ];
  }

  Widget _actionNumberField(
    BuilderNode node,
    String actionId,
    Map<String, Object?> action,
    String field,
    String label, {
    double maximum = 1000000,
  }) => TextFormField(
    key: ValueKey<String>('action-number-$actionId-$field'),
    initialValue: action[field]?.toString() ?? '0',
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    decoration: _inputDecoration(labelText: label),
    onChanged: (String value) {
      final double? parsed = double.tryParse(value);
      if (parsed != null)
        _setActionValue(
          node,
          actionId,
          field,
          parsed.clamp(-maximum, maximum).toDouble(),
        );
    },
  );

  T? _firstOrNull<T>(Iterable<T> values) {
    for (final T value in values) {
      return value;
    }
    return null;
  }

  Object _defaultWidgetActionValue(BuilderNode? target, String property) =>
      switch (property) {
        'visible' => true,
        'opacity' => 1.0,
        'text' => target?.properties['text']?.toString() ?? '',
        'label' => target?.properties['label']?.toString() ?? '',
        _ => '',
      };

  Widget _actionCard(BuilderNode node, Map<String, Object?> action, int index) {
    final String id =
        action['id'] is String
            ? action['id']! as String
            : '${node.id}_action_$index';
    final String type =
        BuilderAction.types.contains(action['type'])
            ? action['type']! as String
            : 'snackbar';
    return Container(
      key: ValueKey<String>('action-card-$id'),
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E4F4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF6750A4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _actionName(type),
                  style: const TextStyle(
                    color: Color(0xFF3D4350),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove action',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  final List<Map<String, Object?>> next =
                      BuilderAction.forNode(node)
                          .where(
                            (Map<String, Object?> item) => item['id'] != id,
                          )
                          .toList();
                  widget.onSetProperty(node.id, 'actions', next);
                },
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('action-type-$id-$type'),
            initialValue: type,
            isExpanded: true,
            decoration: _inputDecoration(),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'navigate',
                child: Text('Navigate to page'),
              ),
              DropdownMenuItem(value: 'snackbar', child: Text('Show snackbar')),
              DropdownMenuItem(
                value: 'dialog',
                child: Text('Show alert dialog'),
              ),
              DropdownMenuItem(value: 'back', child: Text('Navigate back')),
              DropdownMenuItem(
                value: 'setVariable',
                child: Text('Set app variable'),
              ),
              DropdownMenuItem(
                value: 'incrementVariable',
                child: Text('Increment number variable'),
              ),
              DropdownMenuItem(
                value: 'toggleVariable',
                child: Text('Toggle boolean variable'),
              ),
              DropdownMenuItem(
                value: 'updateWidget',
                child: Text('Update another widget'),
              ),
            ],
            onChanged: (String? nextType) {
              if (nextType == null) return;
              final List<Map<String, Object?>> next = BuilderAction.forNode(
                node,
              );
              final int actionIndex = next.indexWhere(
                (Map<String, Object?> item) => item['id'] == id,
              );
              if (actionIndex < 0) return;
              next[actionIndex] = BuilderAction.create(id, nextType);
              widget.onSetProperty(node.id, 'actions', next);
            },
          ),
          if (type == 'navigate') ...<Widget>[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('action-route-$id-${widget.pages.length}'),
              isExpanded: true,
              initialValue:
                  widget.pages.any(
                        (BuilderPage page) => page.route == action['route'],
                      )
                      ? action['route']! as String
                      : '',
              decoration: _inputDecoration(labelText: 'Target page'),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Choose a page'),
                ),
                ...widget.pages.map(
                  (BuilderPage page) => DropdownMenuItem<String>(
                    value: page.route,
                    child: Text(
                      '${page.name}  ·  ${page.route}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (String? route) {
                if (route != null) _setActionValue(node, id, 'route', route);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(
                'action-behavior-$id-${action['behavior']}',
              ),
              isExpanded: true,
              initialValue:
                  action['behavior'] == 'replace' ? 'replace' : 'push',
              decoration: _inputDecoration(labelText: 'Navigation'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'push', child: Text('Push page')),
                DropdownMenuItem(
                  value: 'replace',
                  child: Text('Replace current page'),
                ),
              ],
              onChanged: (String? behavior) {
                if (behavior != null) {
                  _setActionValue(node, id, 'behavior', behavior);
                }
              },
            ),
          ],
          if (type == 'snackbar') ...<Widget>[
            const SizedBox(height: 8),
            _actionTextField(node, id, action, 'message', 'Snackbar message'),
          ],
          if (type == 'dialog') ...<Widget>[
            const SizedBox(height: 8),
            _actionTextField(node, id, action, 'title', 'Dialog title'),
            const SizedBox(height: 7),
            _actionTextField(
              node,
              id,
              action,
              'message',
              'Dialog message',
              maxLines: 3,
            ),
          ],
          if (type == 'back')
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'Returns to the previous page in the preview or running app.',
                style: TextStyle(color: Color(0xFF737B8A), fontSize: 10),
              ),
            ),
          if (type == 'setVariable' ||
              type == 'incrementVariable' ||
              type == 'toggleVariable')
            ..._variableActionFields(node, id, action, type),
          if (type == 'updateWidget')
            ..._updateWidgetActionFields(node, id, action),
        ],
      ),
    );
  }

  Widget _actionTextField(
    BuilderNode node,
    String id,
    Map<String, Object?> action,
    String field,
    String label, {
    int maxLines = 1,
  }) => TextFormField(
    key: ValueKey<String>('action-field-${node.id}-$id-$field'),
    initialValue:
        action[field] is String
            ? action[field]! as String
            : action[field] is List || action[field] is Map
            ? jsonEncode(action[field])
            : action[field]?.toString() ?? '',
    maxLines: maxLines,
    decoration: _inputDecoration(labelText: label),
    onChanged: (String value) => _setActionValue(node, id, field, value),
  );

  void _setActionValue(BuilderNode node, String id, String key, Object? value) {
    _setActionValues(node, id, <String, Object?>{key: value});
  }

  void _setActionValues(
    BuilderNode node,
    String id,
    Map<String, Object?> values,
  ) {
    final List<Map<String, Object?>> actions = BuilderAction.forNode(node);
    final int index = actions.indexWhere(
      (Map<String, Object?> action) => action['id'] == id,
    );
    if (index < 0) return;
    actions[index] = <String, Object?>{...actions[index], ...values};
    widget.onSetProperty(node.id, 'actions', actions);
  }

  String _actionName(String type) => switch (type) {
    'navigate' => 'Navigate to page',
    'snackbar' => 'Show snackbar',
    'dialog' => 'Show alert dialog',
    'back' => 'Navigate back',
    'setVariable' => 'Set app variable',
    'incrementVariable' => 'Increment number variable',
    'toggleVariable' => 'Toggle boolean variable',
    'updateWidget' => 'Update another widget',
    _ => 'Action',
  };

  List<Widget> _buttonStyleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Style'),
    const SizedBox(height: 6),
    SegmentedButton<String>(
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'filled', label: Text('Filled')),
        ButtonSegment<String>(value: 'outlined', label: Text('Outline')),
        ButtonSegment<String>(value: 'text', label: Text('Text')),
      ],
      selected: <String>{_buttonStyle(node)},
      onSelectionChanged: (Set<String> selected) {
        widget.onSetProperty(node.id, 'style', selected.first);
      },
    ),
  ];

  List<Widget> _flexProperties(BuilderNode node) => <Widget>[
    Text(
      node.type == 'row'
          ? 'Children are arranged horizontally.'
          : 'Children are arranged vertically.',
      style: const TextStyle(
        color: Color(0xFF737B8A),
        fontSize: 11,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 12),
    _fieldLabel('Main axis'),
    const SizedBox(height: 6),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('mainAxis-${node.id}'),
      initialValue: _alignmentValue(node.properties['mainAxisAlignment']),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(value: 'start', child: Text('Start')),
        DropdownMenuItem<String>(value: 'center', child: Text('Center')),
        DropdownMenuItem<String>(value: 'end', child: Text('End')),
        DropdownMenuItem<String>(
          value: 'spaceBetween',
          child: Text('Space between'),
        ),
      ],
      onChanged: (String? value) {
        if (value != null) {
          widget.onSetProperty(node.id, 'mainAxisAlignment', value);
        }
      },
    ),
    const SizedBox(height: 12),
    _fieldLabel('Cross axis'),
    const SizedBox(height: 6),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('crossAxis-${node.id}'),
      initialValue: _crossAlignmentValue(node.properties['crossAxisAlignment']),
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(value: 'start', child: Text('Start')),
        DropdownMenuItem<String>(value: 'center', child: Text('Center')),
        DropdownMenuItem<String>(value: 'end', child: Text('End')),
      ],
      onChanged: (String? value) {
        if (value != null) {
          widget.onSetProperty(node.id, 'crossAxisAlignment', value);
        }
      },
    ),
  ];

  Widget _textField(
    BuilderNode node,
    String property, {
    String? hintText,
    int minLines = 1,
    int maxLines = 1,
  }) => TextField(
    key: ValueKey<String>('${node.id}-$property'),
    controller: _controllerFor(node, property),
    minLines: minLines,
    maxLines: maxLines,
    onChanged: (String value) => widget.onSetProperty(node.id, property, value),
    decoration: _inputDecoration(hintText: hintText),
  );

  Widget _numberField(
    BuilderNode node,
    String property, {
    required String label,
    required double fallback,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _fieldLabel(label),
      const SizedBox(height: 5),
      _compactNumberField(node, property, fallback: fallback),
    ],
  );

  Widget _compactNumberField(
    BuilderNode node,
    String property, {
    required double fallback,
    double max = 1200,
  }) => TextField(
    key: ValueKey<String>('${node.id}-$property'),
    controller: _controllerFor(node, property, fallback: fallback),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 11),
    onChanged: (String value) {
      final double? parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) {
        widget.onSetProperty(node.id, property, parsed.clamp(0, max));
      }
    },
    decoration: _inputDecoration(),
  );

  TextEditingController _controllerFor(
    BuilderNode node,
    String property, {
    Object? fallback,
  }) => _controllers.putIfAbsent(
    _fieldKey(node.id, property),
    () => TextEditingController(
      text: _valueText(node.properties[property] ?? fallback),
    ),
  );

  String _fieldKey(String nodeId, String property) => '$nodeId::$property';

  String _valueText(Object? value) {
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    if (value is num) return value.toString();
    return value is String ? value : '';
  }

  Widget _fieldLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: Color(0xFF525968),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _inputDecoration({String? hintText, String? labelText}) =>
      InputDecoration(
        hintText: hintText,
        labelText: labelText,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0xFFDDE0E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0xFFDDE0E8)),
        ),
      );

  bool _matches(String terms) =>
      _query.isEmpty || terms.toLowerCase().contains(_query);

  double _fontSize(BuilderNode node) {
    final Object? raw = node.properties['fontSize'];
    final double size = raw is num ? raw.toDouble() : 18;
    const List<double> options = <double>[14, 16, 18, 20, 24, 26, 32, 40, 48];
    return options.reduce(
      (double a, double b) => (a - size).abs() <= (b - size).abs() ? a : b,
    );
  }

  double _number(Object? value, double fallback, double min, double max) =>
      value is num && value.isFinite
          ? value.toDouble().clamp(min, max).toDouble()
          : fallback;

  String _buttonStyle(BuilderNode node) {
    final Object? style = node.properties['style'];
    return style == 'outlined' || style == 'text' ? style! as String : 'filled';
  }

  String _alignmentValue(Object? value) => switch (value) {
    'center' => 'center',
    'end' => 'end',
    'spaceBetween' => 'spaceBetween',
    _ => 'start',
  };

  String _crossAlignmentValue(Object? value) => switch (value) {
    'center' => 'center',
    'end' => 'end',
    _ => 'start',
  };

  String _containerAlignment(Object? value) => switch (value) {
    'topLeft' ||
    'topCenter' ||
    'topRight' ||
    'centerLeft' ||
    'center' ||
    'centerRight' ||
    'bottomLeft' ||
    'bottomCenter' ||
    'bottomRight' => value! as String,
    _ => 'topLeft',
  };

  String _capitalized(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';

  String _sideLabel(String side) => switch (side) {
    'top' => 'T',
    'right' => 'R',
    'bottom' => 'B',
    _ => 'L',
  };

  int _integer(Object? value, int fallback) => value is int ? value : fallback;

  String _typeLabel(String type) => switch (type) {
    'scaffold' => 'Scaffold',
    'column' => 'Column',
    'row' => 'Row',
    'container' => 'Container',
    'stack' => 'Stack',
    'listView' => 'ListView',
    'gridView' => 'GridView',
    'pageView' => 'PageView',
    'swipeableStack' => 'Swipeable Stack',
    'card' => 'Card',
    'padding' => 'Padding',
    'image' => 'Image',
    'icon' => 'Icon',
    'divider' => 'Divider',
    'verticalDivider' => 'Vertical Divider',
    'signature' => 'Signature',
    'appBar' => 'AppBar',
    'floatingActionButton' => 'Floating Action Button',
    'textField' => 'TextField',
    'checkbox' => 'Checkbox',
    'switch' => 'Switch',
    'button' => 'Button',
    'text' => 'Text',
    _ => type,
  };
}

class _InspectorHeading extends StatelessWidget {
  const _InspectorHeading({required this.title, required this.icon});

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
