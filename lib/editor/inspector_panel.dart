import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/dart.dart' as dart_language;

import '../models/builder_action.dart';
import '../models/builder_document.dart';
import '../models/builder_widget_definition.dart';
import '../services/database_query_support.dart';
import '../services/custom_function_source.dart';
import 'color_picker_dialog.dart';
import 'editor_palette.dart';

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    required this.node,
    required this.seedColor,
    required this.appTheme,
    required this.onSetProperty,
    required this.onSetProperties,
    required this.onSetSeedColor,
    required this.onSetAppTheme,
    required this.onDeleteNode,
    this.onCreateVariable,
    this.pages = const <BuilderPage>[],
    this.variables = const <BuilderVariable>[],
    this.customFunctions = const <BuilderCustomFunction>[],
    this.databaseCollections = const <BuilderDatabaseCollection>[],
    this.databaseRelationships = const <BuilderDatabaseRelationship>[],
    this.onSetCustomFunctions,
    this.onCreateComponentGroup,
    this.onPickImage,
    this.fontAssets = const <BuilderFontAsset>[],
    this.onImportFont,
    this.onRemoveFontAsset,
    super.key,
  });

  final BuilderNode? node;
  final int seedColor;
  final BuilderTheme appTheme;
  final void Function(String nodeId, String key, Object? value) onSetProperty;
  final void Function(String nodeId, Map<String, Object?> values)
  onSetProperties;
  final ValueChanged<int> onSetSeedColor;
  final ValueChanged<BuilderTheme> onSetAppTheme;
  final VoidCallback onDeleteNode;
  final VoidCallback? onCreateVariable;
  final List<BuilderPage> pages;
  final List<BuilderVariable> variables;
  final List<BuilderCustomFunction> customFunctions;
  final List<BuilderDatabaseCollection> databaseCollections;
  final List<BuilderDatabaseRelationship> databaseRelationships;
  final ValueChanged<List<BuilderCustomFunction>>? onSetCustomFunctions;
  final Future<void> Function(BuilderNode node)? onCreateComponentGroup;
  final Future<void> Function(BuilderNode node)? onPickImage;
  final List<BuilderFontAsset> fontAssets;
  final Future<BuilderFontAsset?> Function()? onImportFont;
  final ValueChanged<String>? onRemoveFontAsset;

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
  List<Map<String, Object?>>? _customFunctionActionsDraft;
  String? _customFunctionDraftId;
  StateSetter? _customFunctionDialogSetState;
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
            Text(
              'Select an object on the canvas or in the widget tree to edit it.',
              style: TextStyle(
                color: EditorPalette.mutedText(context),
                fontSize: 12,
              ),
            )
          else ...<Widget>[
            _selectedObjectCard(node),
            const SizedBox(height: 10),
            if (!<String>{
              'scaffold',
              'appBar',
              'floatingActionButton',
            }.contains(node.type)) ...<Widget>[
              OutlinedButton.icon(
                onPressed:
                    widget.onCreateComponentGroup == null
                        ? null
                        : () => widget.onCreateComponentGroup!(node),
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('Save as reusable group'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
            ],
            _searchField(),
            const SizedBox(height: 5),
            ..._propertiesFor(node),
          ],
          if (_matches(
            'theme primary color dark light font radius background text',
          )) ...<Widget>[
            const Divider(height: 20),
            ExpansionTile(
              key: const ValueKey<String>('inspector-theme'),
              initiallyExpanded: _query.isNotEmpty,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              leading: Icon(
                Icons.palette_outlined,
                size: 17,
                color: EditorPalette.mutedText(context),
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
                  style: TextStyle(
                    color: EditorPalette.mutedText(context),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 12),
                _fieldLabel('App appearance'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: widget.appTheme.brightness,
                  isExpanded: true,
                  decoration: _inputDecoration(),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'light', child: Text('Light')),
                    DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    DropdownMenuItem(
                      value: 'system',
                      child: Text('Follow device'),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) {
                      widget.onSetAppTheme(
                        widget.appTheme.copyWith(brightness: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'theme-font-${widget.appTheme.fontFamily}',
                  ),
                  initialValue: widget.appTheme.fontFamily,
                  isExpanded: true,
                  decoration: _inputDecoration(labelText: 'Font family'),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('System default'),
                    ),
                    ...<String>{
                      if (widget.appTheme.fontFamily.isNotEmpty)
                        widget.appTheme.fontFamily,
                      ...widget.fontAssets.map(
                        (BuilderFontAsset font) => font.family,
                      ),
                    }.map(
                      (String family) => DropdownMenuItem<String>(
                        value: family,
                        child: Text(family, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) {
                      widget.onSetAppTheme(
                        widget.appTheme.copyWith(fontFamily: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: 7),
                OutlinedButton.icon(
                  onPressed:
                      widget.onImportFont == null
                          ? null
                          : () async {
                            final BuilderFontAsset? font =
                                await widget.onImportFont!();
                            if (font != null) {
                              widget.onSetAppTheme(
                                widget.appTheme.copyWith(
                                  fontFamily: font.family,
                                ),
                              );
                            }
                          },
                  icon: const Icon(Icons.font_download_outlined, size: 16),
                  label: const Text('Import font file'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                ...widget.fontAssets.map(
                  (BuilderFontAsset font) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${font.family} · ${font.weight}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    subtitle: Text(
                      font.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorPalette.mutedText(context),
                        fontSize: 9,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove bundled font',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => widget.onRemoveFontAsset?.call(font.id),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _fieldLabel('Corner radius'),
                const SizedBox(height: 6),
                TextFormField(
                  key: ValueKey<String>(
                    'theme-radius-${widget.appTheme.cornerRadius}',
                  ),
                  initialValue: widget.appTheme.cornerRadius.toStringAsFixed(0),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _inputDecoration(hintText: '0–48'),
                  onFieldSubmitted: (String value) {
                    final double? radius = double.tryParse(value.trim());
                    if (radius != null) {
                      widget.onSetAppTheme(
                        widget.appTheme.copyWith(
                          cornerRadius: radius.clamp(0.0, 48.0).toDouble(),
                        ),
                      );
                    }
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom background'),
                  value: widget.appTheme.backgroundColor != null,
                  onChanged:
                      (bool enabled) => widget.onSetAppTheme(
                        enabled
                            ? widget.appTheme.copyWith(
                              backgroundColor:
                                  widget.appTheme.brightness == 'dark'
                                      ? 0xFF14151B
                                      : 0xFFFFFFFF,
                            )
                            : widget.appTheme.copyWith(
                              clearBackgroundColor: true,
                            ),
                      ),
                ),
                if (widget.appTheme.backgroundColor case final int color)
                  ColorPickerField(
                    color: Color(color),
                    onChanged:
                        (Color value) => widget.onSetAppTheme(
                          widget.appTheme.copyWith(
                            backgroundColor: value.toARGB32(),
                          ),
                        ),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom text color'),
                  value: widget.appTheme.textColor != null,
                  onChanged:
                      (bool enabled) => widget.onSetAppTheme(
                        enabled
                            ? widget.appTheme.copyWith(
                              textColor:
                                  widget.appTheme.brightness == 'dark'
                                      ? 0xFFFFFFFF
                                      : 0xFF20242C,
                            )
                            : widget.appTheme.copyWith(clearTextColor: true),
                      ),
                ),
                if (widget.appTheme.textColor case final int color)
                  ColorPickerField(
                    color: Color(color),
                    onChanged:
                        (Color value) => widget.onSetAppTheme(
                          widget.appTheme.copyWith(textColor: value.toARGB32()),
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
    final String label =
        node.type == 'componentGroup' && node.properties['groupName'] is String
            ? node.properties['groupName']! as String
            : _typeLabel(node.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: EditorPalette.surfaceRaised(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EditorPalette.border(context)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.widgets_outlined,
            size: 17,
            color: EditorPalette.primary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Tooltip(
              message: node.id,
              child: Text(
                node.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: EditorPalette.mutedText(context),
                ),
              ),
            ),
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

    final bool supportsNodeModifiers =
        !<String>{
          'appBar',
          'floatingActionButton',
          'expanded',
          'flexible',
          'spacer',
        }.contains(node.type);
    if (supportsNodeModifiers) {
      add(
        'Visibility',
        'visible opacity conditional',
        _visibilityProperties(node),
        expanded: true,
      );
      add(
        'Variable bindings',
        'app state variable bind text label hint visibility opacity size',
        _bindingsProperties(node),
      );
      add('Padding', 'top right bottom left spacing inset', <Widget>[
        _spacingEditor(node, 'padding'),
      ], expanded: node.type == 'container');
      add('Margin', 'top right bottom left spacing outside', <Widget>[
        _spacingEditor(node, 'margin'),
      ], expanded: node.type == 'container');
    }
    if (!<String>{
      'scaffold',
      'appBar',
      'floatingActionButton',
      'expanded',
      'flexible',
      'spacer',
    }.contains(node.type)) {
      add(
        'Responsive sizing',
        'width height max full fill quarter half three-quarter fraction size',
        _sizeModeProperties(node),
      );
    }
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
    if (node.type == 'safeArea') {
      add(
        'Safe Area',
        'top bottom left right minimum inset padding system bars',
        _safeAreaProperties(node),
        expanded: true,
      );
    }
    if (<String>{'expanded', 'flexible', 'spacer'}.contains(node.type)) {
      add(
        'Flex',
        'flex factor expanded flexible spacer row column fit',
        _flexChildProperties(node),
        expanded: true,
      );
    }
    if ((node.type == 'safeArea' ||
            node.type == 'expanded' ||
            node.type == 'flexible') &&
        node.children.isNotEmpty) {
      add(
        'Children',
        'nested child objects layout',
        _childrenSummary(node),
        expanded: true,
      );
    }
    if (node.type == 'card') {
      add(
        'Size',
        'width height dimensions',
        _sizeProperties(node),
        expanded: true,
      );
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
    if (<String>{
      'stack',
      'listView',
      'databaseList',
      'singleChildScrollView',
      'gridView',
      'pageView',
      'swipeableStack',
      'sizedBox',
    }.contains(node.type)) {
      add(
        'Size',
        'width height dimensions',
        node.type == 'sizedBox'
            ? _sizedBoxProperties(node)
            : _sizeProperties(node),
        expanded: true,
      );
      if (node.type == 'stack')
        add('Layout', 'alignment fit stack children', _stackProperties(node));
      if (node.type == 'listView')
        add('List', 'scroll direction spacing', _listProperties(node));
      if (node.type == 'databaseList')
        add(
          'Database List',
          'collection records rows empty message',
          _databaseListProperties(node),
          expanded: true,
        );
      if (node.type == 'singleChildScrollView')
        add(
          'Scroll View',
          'scroll direction reverse axis',
          _scrollViewProperties(node),
        );
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
    if (node.type == 'align') {
      add('Alignment', 'align child position', <Widget>[
        _alignmentDropdown(node, 'alignment'),
      ]);
    }
    if (node.type == 'wrap') {
      add('Wrap', 'direction spacing run spacing', _wrapProperties(node));
    }
    if (node.type == 'aspectRatio') {
      add('Layout', 'aspect ratio width height', <Widget>[
        _numberField(node, 'aspectRatio', label: 'Aspect ratio', fallback: 1.5),
      ]);
    }
    if (node.type == 'clipRRect') {
      add('Clip', 'corner radius rounded clipping', <Widget>[
        _numberField(node, 'borderRadius', label: 'Radius', fallback: 12),
      ]);
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
    if (const <String>{
      'extendedFloatingActionButton',
      'iconButton',
      'segmentedButton',
      'badge',
      'linearProgressIndicator',
      'snackBar',
      'alertDialog',
      'bottomSheet',
      'listTile',
      'bottomAppBar',
      'navigationBar',
      'navigationDrawer',
      'navigationRail',
      'tabBar',
      'chip',
      'datePicker',
      'menu',
      'radio',
      'slider',
      'timePicker',
    }.contains(node.type)) {
      final List<Widget> componentProperties = _materialComponentProperties(
        node,
      );
      if (componentProperties.isNotEmpty) {
        add(
          'Component',
          'material widget content label title value options tabs destinations icon progress size button navigation badge snackbar dialog date time radio slider',
          componentProperties,
          expanded: true,
        );
      }
      if (<String>{
        'extendedFloatingActionButton',
        'iconButton',
        'segmentedButton',
        'snackBar',
        'alertDialog',
        'listTile',
        'bottomAppBar',
        'chip',
        'datePicker',
        'menu',
        'timePicker',
        'navigationBar',
        'navigationDrawer',
        'navigationRail',
        'tabBar',
        'radio',
        'slider',
      }.contains(node.type)) {
        add(
          'Actions',
          'on tap navigate snackbar alert dialog back',
          _actionsProperties(node),
          expanded: true,
        );
      }
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
          style: TextStyle(
            color: EditorPalette.mutedText(context),
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ], expanded: true);
    }
    if (node.type == 'componentGroup') {
      add('Group contents', 'reusable saved group components', <Widget>[
        Text(
          'This reusable group contains ${node.children.length} top-level component(s). Changes to this inserted copy stay with this instance.',
          style: TextStyle(
            color: EditorPalette.mutedText(context),
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ], expanded: true);
    }
    if (!<String>{
      'expanded',
      'appBar',
      'floatingActionButton',
      'extendedFloatingActionButton',
      'bottomAppBar',
      'bottomSheet',
      'navigationBar',
      'navigationDrawer',
      'navigationRail',
    }.contains(node.type)) {
      add(
        'Responsive overrides',
        'phone tablet desktop breakpoint width height font size spacing visibility color',
        <Widget>[
          _ResponsiveOverridesEditor(
            key: ValueKey<String>('responsive-${node.id}'),
            node: node,
            onChanged:
                (Map<String, Object?> value) =>
                    widget.onSetProperty(node.id, 'responsiveOverrides', value),
          ),
        ],
      );
    }
    if (sections.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'No properties match this search.',
            style: TextStyle(
              color: EditorPalette.mutedText(context),
              fontSize: 11,
            ),
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
    childrenPadding: const EdgeInsets.fromLTRB(3, 0, 3, 10),
    visualDensity: VisualDensity.compact,
    iconColor: EditorPalette.mutedText(context),
    collapsedIconColor: EditorPalette.mutedText(context),
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    children: children,
  );

  List<Widget> _visibilityProperties(BuilderNode node) => <Widget>[
    SwitchListTile.adaptive(
      key: ValueKey<String>('${node.id}-visible'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Visible', style: const TextStyle(fontSize: 11)),
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
    Widget sideField(String side) => TextField(
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      ),
      onChanged: (String text) {
        final double? value = double.tryParse(text);
        if (value == null || !value.isFinite) return;
        _setSpacing(node, prefix, side, value.clamp(0, 1200));
      },
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EditorPalette.surfaceRaised(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EditorPalette.border(context)),
      ),
      child: Column(
        children: <Widget>[
          Center(child: SizedBox(width: 68, child: sideField('top'))),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(child: sideField('left')),
              const SizedBox(width: 6),
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
                          ? EditorPalette.primary(context)
                          : EditorPalette.mutedText(context),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: sideField('right')),
            ],
          ),
          const SizedBox(height: 6),
          Center(child: SizedBox(width: 68, child: sideField('bottom'))),
          const SizedBox(height: 5),
          Text(
            linked ? 'All sides linked' : 'Top · Right · Bottom · Left',
            style: TextStyle(
              fontSize: 9,
              color: EditorPalette.mutedText(context),
            ),
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

  List<Widget> _sizeModeProperties(BuilderNode node) => <Widget>[
    _sizeModeDropdown(node, 'widthMode', 'Width'),
    const SizedBox(height: 8),
    _sizeModeDropdown(node, 'heightMode', 'Height'),
    const SizedBox(height: 6),
    Text(
      'Fill and fractional sizes use the available parent space.',
      style: TextStyle(fontSize: 10, color: EditorPalette.mutedText(context)),
    ),
  ];

  Widget _sizeModeDropdown(BuilderNode node, String property, String label) =>
      DropdownButtonFormField<String>(
        key: ValueKey<String>('${node.id}-$property'),
        initialValue: _sizeMode(node.properties[property]),
        isExpanded: true,
        decoration: _inputDecoration(labelText: label),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'fixed', child: Text('Component size')),
          DropdownMenuItem(value: 'max', child: Text('Max / fill')),
          DropdownMenuItem(value: 'quarter', child: Text('One quarter')),
          DropdownMenuItem(value: 'half', child: Text('Half')),
          DropdownMenuItem(
            value: 'threeQuarter',
            child: Text('Three quarters'),
          ),
        ],
        onChanged: (String? value) {
          if (value != null) widget.onSetProperty(node.id, property, value);
        },
      );

  String _sizeMode(Object? value) =>
      const <String>{
            'fixed',
            'max',
            'quarter',
            'half',
            'threeQuarter',
          }.contains(value)
          ? value! as String
          : 'fixed';

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
      style: TextStyle(
        color: EditorPalette.mutedText(context),
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
      isExpanded: true,
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
      isExpanded: true,
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

  List<Widget> _databaseListProperties(BuilderNode node) => <Widget>[
    DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'database-list-collection-${node.id}-${node.properties['collectionId']}',
      ),
      initialValue:
          widget.databaseCollections.any(
                (BuilderDatabaseCollection item) =>
                    item.id == node.properties['collectionId'],
              )
              ? node.properties['collectionId'] as String
              : '',
      isExpanded: true,
      decoration: _inputDecoration(labelText: 'Collection'),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: '', child: Text('Choose a collection')),
        ...widget.databaseCollections.map(
          (BuilderDatabaseCollection item) => DropdownMenuItem(
            value: item.id,
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'collectionId', value);
      },
    ),
    if (widget.databaseCollections.isEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          'Create a collection in Resources → Database first.',
          style: TextStyle(
            fontSize: 10,
            color: EditorPalette.mutedText(context),
          ),
        ),
      ),
    const SizedBox(height: 10),
    ..._listProperties(node),
    const SizedBox(height: 10),
    _fieldLabel('Empty list message'),
    const SizedBox(height: 5),
    _textField(node, 'emptyMessage'),
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
      title: const Text('Loop cards', style: const TextStyle(fontSize: 11)),
      value: node.properties['loop'] == true,
      onChanged: (bool value) => widget.onSetProperty(node.id, 'loop', value),
    ),
  ];

  List<Widget> _safeAreaProperties(BuilderNode node) => <Widget>[
    for (final (String, String) edge in const <(String, String)>[
      ('top', 'Top'),
      ('bottom', 'Bottom'),
      ('left', 'Left'),
      ('right', 'Right'),
    ])
      SwitchListTile.adaptive(
        key: ValueKey<String>('${node.id}-safe-${edge.$1}'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(edge.$2, style: const TextStyle(fontSize: 11)),
        value: node.properties[edge.$1] != false,
        onChanged:
            (bool value) => widget.onSetProperty(node.id, edge.$1, value),
      ),
    _numberField(node, 'minimum', label: 'Minimum inset', fallback: 0),
  ];

  List<Widget> _flexChildProperties(BuilderNode node) => <Widget>[
    Text(
      'Flex widgets share the remaining space in a Row or Column.',
      style: TextStyle(
        color: EditorPalette.mutedText(context),
        fontSize: 11,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 10),
    _integerField(node, 'flex', label: 'Flex factor', fallback: 1),
    if (node.type == 'flexible') ...<Widget>[
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey<String>('flex-fit-${node.id}'),
        initialValue: node.properties['fit'] == 'tight' ? 'tight' : 'loose',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Fit'),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'loose', child: Text('Loose')),
          DropdownMenuItem(value: 'tight', child: Text('Tight')),
        ],
        onChanged: (String? value) {
          if (value != null) widget.onSetProperty(node.id, 'fit', value);
        },
      ),
    ],
  ];

  List<Widget> _scrollViewProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Scroll direction'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('scroll-view-direction-${node.id}'),
      initialValue:
          node.properties['scrollDirection'] == 'horizontal'
              ? 'horizontal'
              : 'vertical',
      isExpanded: true,
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
    SwitchListTile.adaptive(
      key: ValueKey<String>('scroll-view-reverse-${node.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Reverse', style: TextStyle(fontSize: 11)),
      value: node.properties['reverse'] == true,
      onChanged:
          (bool value) => widget.onSetProperty(node.id, 'reverse', value),
    ),
  ];

  List<Widget> _wrapProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Direction'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('wrap-direction-${node.id}'),
      initialValue:
          node.properties['direction'] == 'vertical'
              ? 'vertical'
              : 'horizontal',
      isExpanded: true,
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'horizontal', child: Text('Horizontal')),
        DropdownMenuItem(value: 'vertical', child: Text('Vertical')),
      ],
      onChanged: (String? value) {
        if (value != null) widget.onSetProperty(node.id, 'direction', value);
      },
    ),
    const SizedBox(height: 10),
    _numberField(node, 'spacing', label: 'Item spacing', fallback: 8),
    const SizedBox(height: 10),
    _numberField(node, 'runSpacing', label: 'Line spacing', fallback: 8),
  ];

  List<Widget> _sizedBoxProperties(BuilderNode node) => <Widget>[
    Row(
      children: <Widget>[
        Expanded(
          child: _numberField(node, 'width', label: 'Width', fallback: 120),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _numberField(node, 'height', label: 'Height', fallback: 60),
        ),
      ],
    ),
  ];

  List<Widget> _imageProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Image file'),
    const SizedBox(height: 5),
    _textField(node, 'source', hintText: 'Image path or URL'),
    const SizedBox(height: 8),
    _textField(
      node,
      'altText',
      hintText: 'Describe the image for accessibility',
    ),
    const SizedBox(height: 6),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed:
            widget.onPickImage == null ? null : () => widget.onPickImage!(node),
        icon: const Icon(Icons.folder_open_outlined, size: 15),
        label: const Text('Choose image…'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11),
        ),
      ),
    ),
    const SizedBox(height: 10),
    _fieldLabel('Image fit'),
    DropdownButtonFormField<String>(
      key: ValueKey<String>('image-fit-${node.id}'),
      initialValue: _fitValue(node.properties['fit']),
      isExpanded: true,
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
      isExpanded: true,
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

  List<Widget> _materialComponentProperties(BuilderNode node) {
    final List<Widget> controls = <Widget>[];
    final Map<String, Object?> properties = <String, Object?>{
      ...defaultBuilderWidgetProperties(node.type),
      ...node.properties,
    };
    for (final MapEntry<String, Object?> entry in properties.entries) {
      final String property = entry.key;
      final Object? value = entry.value;
      if (property.endsWith('Color') && value is int) {
        controls.addAll(<Widget>[
          _fieldLabel(_componentPropertyLabel(property)),
          const SizedBox(height: 6),
          ColorPickerField(
            color: Color(value),
            onChanged:
                (Color color) =>
                    widget.onSetProperty(node.id, property, color.toARGB32()),
          ),
          const SizedBox(height: 10),
        ]);
      } else if (node.type == 'iconButton' && property == 'style') {
        controls.addAll(<Widget>[
          _fieldLabel('Style'),
          const SizedBox(height: 5),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('${node.id}-icon-button-style'),
            initialValue: _iconButtonStyle(value),
            isExpanded: true,
            decoration: _inputDecoration(),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'standard', child: Text('Standard')),
              DropdownMenuItem(value: 'filled', child: Text('Filled')),
              DropdownMenuItem(
                value: 'filledTonal',
                child: Text('Filled tonal'),
              ),
              DropdownMenuItem(value: 'outlined', child: Text('Outlined')),
            ],
            onChanged: (String? next) {
              if (next != null) widget.onSetProperty(node.id, property, next);
            },
          ),
        ]);
      } else if (value is bool) {
        controls.add(
          SwitchListTile.adaptive(
            key: ValueKey<String>('${node.id}-$property'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              _componentPropertyLabel(property),
              style: const TextStyle(fontSize: 11),
            ),
            value: value,
            onChanged:
                (bool next) => widget.onSetProperty(node.id, property, next),
          ),
        );
      } else if (value is num) {
        double minimum = 0;
        double maximum = 1200;
        if (node.type == 'slider') {
          final double sliderMinimum =
              node.properties['min'] is num
                  ? (node.properties['min']! as num).toDouble()
                  : 0;
          final double sliderMaximum =
              node.properties['max'] is num
                  ? (node.properties['max']! as num).toDouble()
                  : 100;
          switch (property) {
            case 'min':
              minimum = -100000;
              maximum = 99999;
              break;
            case 'max':
              minimum = sliderMinimum + 0.001;
              maximum = 100000;
              break;
            case 'value':
              minimum = sliderMinimum;
              maximum =
                  sliderMaximum > sliderMinimum
                      ? sliderMaximum
                      : sliderMinimum + 0.001;
              break;
          }
        } else if (property == 'value' &&
            node.type == 'linearProgressIndicator') {
          maximum = 1;
        } else if (property == 'minHeight' &&
            node.type == 'linearProgressIndicator') {
          maximum = 100;
        } else if (property == 'selectedIndex' &&
            <String>{
              'segmentedButton',
              'navigationBar',
              'navigationDrawer',
              'navigationRail',
            }.contains(node.type)) {
          final String listProperty =
              node.type == 'segmentedButton' ? 'options' : 'destinations';
          maximum =
              _commaSeparatedProperty(
                node.properties[listProperty],
              ).length.toDouble().clamp(1, 1000) -
              1;
        }
        controls.add(
          _numberField(
            node,
            property,
            label: _componentPropertyLabel(property),
            fallback: value.toDouble(),
            min: minimum,
            max: maximum,
          ),
        );
      } else if (value is String &&
          <String>{'destinationIcons', 'tabIcons'}.contains(property)) {
        controls.addAll(<Widget>[
          _fieldLabel(_componentPropertyLabel(property)),
          const SizedBox(height: 5),
          _textField(
            node,
            property,
            fallback: value,
            hintText:
                property == 'destinationIcons'
                    ? 'home,search,settings'
                    : 'none,none,none',
          ),
          const SizedBox(height: 4),
          Text(
            property == 'destinationIcons'
                ? 'Use one icon name per destination in label order (for example, home, search, settings).'
                : 'Use one icon name per tab in label order. Use "none" for text-only tabs.',
            style: TextStyle(
              color: EditorPalette.mutedText(context),
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ]);
      } else if (value is String) {
        controls.addAll(<Widget>[
          _fieldLabel(_componentPropertyLabel(property)),
          const SizedBox(height: 5),
          _textField(
            node,
            property,
            fallback: value,
            hintText: _componentPropertyLabel(property),
            minLines: property == 'message' || property == 'options' ? 2 : 1,
            maxLines: property == 'message' || property == 'options' ? 3 : 1,
          ),
        ]);
      }
      controls.add(const SizedBox(height: 9));
    }
    if (controls.isNotEmpty) controls.removeLast();
    return controls;
  }

  String _componentPropertyLabel(String property) => property
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (Match match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (String word) =>
            word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  List<String> _commaSeparatedProperty(Object? value) =>
      (value is String ? value : '')
          .split(',')
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList();

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
    const SizedBox(height: 10),
    DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'input-variable-${node.id}-${node.properties['inputVariableId']}',
      ),
      initialValue:
          widget.variables.any(
                (BuilderVariable item) =>
                    item.id == node.properties['inputVariableId'] &&
                    item.type == 'string',
              )
              ? node.properties['inputVariableId'] as String
              : '',
      isExpanded: true,
      decoration: _inputDecoration(labelText: 'Save input to variable'),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: '', child: Text('No variable')),
        ...widget.variables
            .where((BuilderVariable item) => item.type == 'string')
            .map(
              (BuilderVariable item) => DropdownMenuItem(
                value: item.id,
                child: Text(item.name, overflow: TextOverflow.ellipsis),
              ),
            ),
      ],
      onChanged: (String? value) {
        if (value != null)
          widget.onSetProperty(node.id, 'inputVariableId', value);
      },
    ),
    Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        r'Insert app variables with ${variableName}. In a Database List use ${record.fieldId}.',
        style: TextStyle(fontSize: 10, color: EditorPalette.mutedText(context)),
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
      title: const Text(
        'Initially selected',
        style: const TextStyle(fontSize: 11),
      ),
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
      isExpanded: true,
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
        isExpanded: true,
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
      isExpanded: true,
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
    Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        r'Insert app variables with ${variableName} or $variableName.',
        style: TextStyle(fontSize: 10, color: EditorPalette.mutedText(context)),
      ),
    ),
  ];

  List<Widget> _textStyleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Font size'),
    const SizedBox(height: 6),
    DropdownButtonFormField<double>(
      key: ValueKey<String>('fontSize-${node.id}'),
      initialValue: _fontSize(node),
      isExpanded: true,
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
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'No actions yet. Add a step to define what happens when this widget is pressed.',
            style: TextStyle(
              color: EditorPalette.mutedText(context),
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
                _allActions(node)
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
            next.add(_createAction(id, type));
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
                PopupMenuItem<String>(
                  value: 'conditional',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.account_tree_outlined, size: 17),
                    title: Text('If / else'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'loop',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.repeat, size: 17),
                    title: Text('Repeat actions'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'httpRequest',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.language, size: 17),
                    title: Text('HTTP request'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'customFunction',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.functions, size: 17),
                    title: Text('Run custom function'),
                  ),
                ),
              ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: EditorPalette.primaryContainer(context),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.add,
                  size: 15,
                  color: EditorPalette.primary(context),
                ),
                const SizedBox(width: 5),
                Text(
                  'Add action',
                  style: TextStyle(
                    color: EditorPalette.primary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (widget.customFunctions.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        _fieldLabel('Custom functions'),
        const SizedBox(height: 4),
        for (final BuilderCustomFunction function in widget.customFunctions)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.functions,
                  size: 14,
                  color: EditorPalette.mutedText(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    function.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit custom function',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => _editCustomFunction(node, function),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                ),
                IconButton(
                  tooltip: 'Remove custom function',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed:
                      () => widget.onSetCustomFunctions?.call(
                        widget.customFunctions
                            .where(
                              (BuilderCustomFunction item) =>
                                  item.id != function.id,
                            )
                            .toList(),
                      ),
                  icon: const Icon(Icons.delete_outline, size: 15),
                ),
              ],
            ),
          ),
      ],
      const SizedBox(height: 5),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _editCustomFunction(node),
          icon: const Icon(Icons.functions, size: 15),
          label: const Text('Create custom function'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            textStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    ];
  }

  List<Widget> _bindingsProperties(BuilderNode node) {
    if (widget.variables.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Text(
            'Create an app variable to bind this widget to changing state.',
            style: TextStyle(
              fontSize: 10,
              color: EditorPalette.mutedText(context),
            ),
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
      ];
    }
    final Map<String, Object?> bindings = _bindingsFor(node);
    final List<Widget> rows = <Widget>[];
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
      rows.add(
        _bindingDropdown(node, bindings, 'hintText', 'Hint text', 'text'),
      );
    }
    rows.add(_bindingDropdown(node, bindings, 'visible', 'Visible', 'boolean'));
    rows.add(_bindingDropdown(node, bindings, 'opacity', 'Opacity', 'number'));
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
              style: TextStyle(
                color: EditorPalette.mutedText(context),
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
            isExpanded: true,
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
        page?.root
            .depthFirst()
            .where(
              (BuilderNode item) =>
                  !<String>{
                    'appBar',
                    'floatingActionButton',
                  }.contains(item.type),
            )
            .toList() ??
        <BuilderNode>[];
    final String targetId = action['targetNodeId'] as String? ?? '';
    final BuilderNode? target = _firstOrNull<BuilderNode>(
      targets.where((BuilderNode item) => item.id == targetId),
    );
    final List<String> properties = <String>[
      'visible',
      'opacity',
      if (target?.type == 'text') 'text',
      if (target?.type == 'textField') 'initialValue',
      if (target?.type == 'textField') 'hintText',
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
                      'hintText' => 'Hint text',
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
          isExpanded: true,
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
              : property == 'hintText'
              ? 'Hint text'
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
        'initialValue' => target?.properties['initialValue']?.toString() ?? '',
        'hintText' => target?.properties['hintText']?.toString() ?? '',
        'label' => target?.properties['label']?.toString() ?? '',
        _ => '',
      };

  List<Map<String, Object?>> _actionMaps(Object? raw) =>
      raw is List
          ? raw
              .whereType<Map<Object?, Object?>>()
              .map(
                (Map<Object?, Object?> item) => <String, Object?>{
                  for (final MapEntry<Object?, Object?> entry in item.entries)
                    entry.key.toString(): entry.value,
                },
              )
              .toList()
          : <Map<String, Object?>>[];

  List<Map<String, Object?>> _allActions(BuilderNode node) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    void visit(List<Map<String, Object?>> actions) {
      for (final Map<String, Object?> action in actions) {
        result.add(action);
        for (final String key in <String>[
          'thenActions',
          'elseActions',
          'actions',
        ]) {
          if (action[key] is List) visit(_actionMaps(action[key]));
        }
      }
    }

    visit(_customFunctionActionsDraft ?? BuilderAction.forNode(node));
    return result;
  }

  void _commitActionList(BuilderNode node, List<Map<String, Object?>> actions) {
    if (_customFunctionActionsDraft != null) {
      _customFunctionActionsDraft = actions;
      _customFunctionDialogSetState?.call(() {});
      return;
    }
    widget.onSetProperty(node.id, 'actions', actions);
  }

  List<Map<String, Object?>> _rewriteActions(
    List<Map<String, Object?>> actions,
    String id,
    Map<String, Object?>? replacement,
    Map<String, Object?>? values,
  ) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> action in actions) {
      if (action['id'] == id && replacement == null && values == null) continue;
      Map<String, Object?> next =
          action['id'] == id && replacement != null
              ? replacement
              : <String, Object?>{
                ...action,
                if (action['id'] == id && values != null) ...values,
              };
      if (next['id'] != id || replacement == null) {
        for (final String key in <String>[
          'thenActions',
          'elseActions',
          'actions',
        ]) {
          if (next[key] is List) {
            next = <String, Object?>{
              ...next,
              key: _rewriteActions(
                _actionMaps(next[key]),
                id,
                replacement,
                values,
              ),
            };
          }
        }
      }
      result.add(next);
    }
    return result;
  }

  void _removeAction(BuilderNode node, String id) => _commitActionList(
    node,
    _rewriteActions(
      _customFunctionActionsDraft ?? BuilderAction.forNode(node),
      id,
      null,
      null,
    ),
  );

  void _replaceAction(
    BuilderNode node,
    String id,
    Map<String, Object?> replacement,
  ) => _commitActionList(
    node,
    _rewriteActions(
      _customFunctionActionsDraft ?? BuilderAction.forNode(node),
      id,
      replacement,
      null,
    ),
  );

  void _setActionValues(
    BuilderNode node,
    String id,
    Map<String, Object?> values,
  ) => _commitActionList(
    node,
    _rewriteActions(
      _customFunctionActionsDraft ?? BuilderAction.forNode(node),
      id,
      null,
      values,
    ),
  );

  String _newCustomFunctionId() {
    final Set<String> ids =
        widget.customFunctions
            .map((BuilderCustomFunction function) => function.id)
            .toSet();
    final String base =
        'custom_function_${DateTime.now().microsecondsSinceEpoch}';
    String id = base;
    int suffix = 2;
    while (ids.contains(id)) {
      id = '${base}_$suffix';
      suffix++;
    }
    return id;
  }

  Future<BuilderCustomFunction?> _editCustomFunction(
    BuilderNode source, [
    BuilderCustomFunction? existing,
  ]) async {
    final String id = existing?.id ?? _newCustomFunctionId();
    final TextEditingController nameController = TextEditingController(
      text: existing?.name ?? 'New function',
    );
    final CodeController bodyController = CodeController(
      text: existing?.body ?? '',
      language: dart_language.dart,
    );
    _customFunctionDraftId = id;
    _customFunctionActionsDraft =
        existing == null
            ? <Map<String, Object?>>[]
            : existing.actions
                .map(
                  (Map<String, Object?> action) =>
                      Map<String, Object?>.of(action),
                )
                .toList();
    String? validationMessage;
    BuilderCustomFunction? saved;
    try {
      saved = await showDialog<BuilderCustomFunction>(
        context: context,
        builder:
            (BuildContext dialogContext) => StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                _customFunctionDialogSetState = setDialogState;
                final List<Map<String, Object?>> actions =
                    _customFunctionActionsDraft ?? <Map<String, Object?>>[];
                final List<String> syntaxErrors = _customFunctionSyntaxErrors(
                  bodyController.text,
                );
                return AlertDialog(
                  title: Text(
                    existing == null
                        ? 'Create custom function'
                        : 'Edit ${existing.name}',
                  ),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: nameController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Function name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (validationMessage != null) ...<Widget>[
                            const SizedBox(height: 5),
                            Text(
                              validationMessage!,
                              style: const TextStyle(
                                color: const Color(0xFF9C3535),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Dart function body',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          CodeTheme(
                            data: CodeThemeData(
                              styles:
                                  EditorPalette.isDark(context)
                                      ? atomOneDarkTheme
                                      : githubTheme,
                            ),
                            child: CodeField(
                              controller: bodyController,
                              minLines: 5,
                              maxLines: 12,
                              wrap: true,
                              textStyle: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                              gutterStyle: const GutterStyle(
                                width: 38,
                                margin: 4,
                                showFoldingHandles: false,
                              ),
                              onChanged: (_) => setDialogState(() {}),
                              decoration: BoxDecoration(
                                color: EditorPalette.surface(context),
                                border: Border.all(
                                  color: const Color(0xFF74777F),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Canvas preview supports Dart core, math, JSON, and types from Data types. Use getVariable and setVariable with JSON plus fromJson()/toJson() to persist structured values. showMessage, navigateTo, back and print interact with the canvas preview. Material APIs are available in Flutter Preview and exports; place any import lines before the function statements.',
                              style: TextStyle(
                                color: EditorPalette.mutedText(context),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (syntaxErrors.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 6),
                            for (final String error in syntaxErrors.take(4))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  error,
                                  style: const TextStyle(
                                    color: const Color(0xFFB3261E),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ] else if (bodyController.text
                              .trim()
                              .isNotEmpty) ...<Widget>[
                            const SizedBox(height: 5),
                            const Text(
                              'No Dart syntax errors found.',
                              style: const TextStyle(
                                color: const Color(0xFF477A55),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (bodyController.text
                              .trim()
                              .isNotEmpty) ...<Widget>[
                            const SizedBox(height: 6),
                            Text(
                              'Dart code runs in Flutter Preview and exported apps. The canvas preview supports core Dart code. Action steps below are ignored while code is present.',
                              style: TextStyle(
                                color: EditorPalette.mutedText(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Function action steps (optional alternative)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (actions.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        'Leave the Dart body empty to use action steps here.',
                                        style: TextStyle(
                                          color: EditorPalette.mutedText(
                                            context,
                                          ),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  for (
                                    int index = 0;
                                    index < actions.length;
                                    index++
                                  )
                                    _actionCard(source, actions[index], index),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: PopupMenuButton<String>(
                                      tooltip: 'Add function action',
                                      onSelected: (String type) {
                                        actions.add(
                                          _createAction(
                                            _newActionId(source),
                                            type,
                                          ),
                                        );
                                        setDialogState(() {});
                                      },
                                      itemBuilder:
                                          (BuildContext context) =>
                                              _actionTypeItems(),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Icon(
                                              Icons.add,
                                              size: 14,
                                              color: EditorPalette.primary(
                                                context,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Add function action',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: EditorPalette.primary(
                                                  context,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final String name = nameController.text.trim();
                        final bool duplicate = widget.customFunctions.any(
                          (BuilderCustomFunction function) =>
                              function.id != id &&
                              function.name.toLowerCase() == name.toLowerCase(),
                        );
                        if (name.isEmpty || duplicate) {
                          setDialogState(() {
                            validationMessage =
                                name.isEmpty
                                    ? 'Enter a function name.'
                                    : 'A function with that name already exists.';
                          });
                          return;
                        }
                        Navigator.pop(
                          dialogContext,
                          BuilderCustomFunction(
                            id: id,
                            name: name,
                            body: bodyController.text,
                            actions: _customFunctionActionsDraft ?? actions,
                          ),
                        );
                      },
                      child: const Text('Save function'),
                    ),
                  ],
                );
              },
            ),
      );
    } finally {
      _customFunctionActionsDraft = null;
      _customFunctionDraftId = null;
      _customFunctionDialogSetState = null;
      nameController.dispose();
      bodyController.dispose();
    }
    if (saved == null) return null;
    final List<BuilderCustomFunction> next = <BuilderCustomFunction>[
      ...widget.customFunctions.where(
        (BuilderCustomFunction function) => function.id != saved!.id,
      ),
      saved,
    ];
    widget.onSetCustomFunctions?.call(next);
    return saved;
  }

  List<String> _customFunctionSyntaxErrors(String body) {
    if (body.trim().isEmpty) return <String>[];

    final CustomFunctionSource parts = CustomFunctionSource.parse(body);
    final String imports =
        parts.imports.isEmpty ? '' : '${parts.imports.join('\n')}\n';
    final String prefix = '${imports}void _customFunctionBody() async {\n';
    final String source = '$prefix${parts.body}\n}';
    final parsed = parseString(
      content: source,
      path: 'custom_function.dart',
      throwIfDiagnostics: false,
    );
    final int bodyEnd = prefix.length + parts.body.length;
    final List<String> errors = <String>[];
    for (final error in parsed.errors) {
      if ((error.offset >= imports.length && error.offset < prefix.length) ||
          error.offset > bodyEnd)
        continue;
      final int line =
          '\n'.allMatches(source.substring(0, error.offset)).length;
      errors.add('Line $line: ${error.message}');
    }
    return errors;
  }

  Map<String, Object?> _createAction(String id, String type) {
    final Map<String, Object?> action = BuilderAction.create(id, type);
    if (type.startsWith('database') && widget.databaseCollections.length == 1) {
      action['collectionId'] = widget.databaseCollections.single.id;
    }
    if (type == 'customFunction') {
      final List<BuilderCustomFunction> availableFunctions =
          widget.customFunctions
              .where(
                (BuilderCustomFunction function) =>
                    function.id != _customFunctionDraftId,
              )
              .toList();
      if (availableFunctions.length == 1) {
        action['functionId'] = availableFunctions.single.id;
      }
    }
    return action;
  }

  String _newActionId(BuilderNode node) {
    final Set<String> ids =
        _allActions(node)
            .map((Map<String, Object?> item) => item['id'] as String? ?? '')
            .toSet();
    int index = ids.length + 1;
    final String actionPrefix = _customFunctionDraftId ?? node.id;
    String id = '${actionPrefix}_action_$index';
    while (ids.contains(id)) {
      index++;
      id = '${actionPrefix}_action_$index';
    }
    return id;
  }

  List<PopupMenuEntry<String>>
  _actionTypeItems() => const <PopupMenuEntry<String>>[
    PopupMenuItem(value: 'navigate', child: Text('Navigate to page')),
    PopupMenuItem(value: 'snackbar', child: Text('Show snackbar')),
    PopupMenuItem(value: 'dialog', child: Text('Show alert dialog')),
    PopupMenuItem(value: 'back', child: Text('Navigate back')),
    PopupMenuItem(value: 'setVariable', child: Text('Set app variable')),
    PopupMenuItem(
      value: 'incrementVariable',
      child: Text('Increment number variable'),
    ),
    PopupMenuItem(
      value: 'toggleVariable',
      child: Text('Toggle boolean variable'),
    ),
    PopupMenuItem(value: 'updateWidget', child: Text('Update another widget')),
    PopupMenuItem(value: 'conditional', child: Text('If / else')),
    PopupMenuItem(value: 'loop', child: Text('Repeat actions')),
    PopupMenuItem(value: 'httpRequest', child: Text('HTTP request')),
    PopupMenuItem(value: 'databaseInsert', child: Text('Save database record')),
    PopupMenuItem(
      value: 'databaseUpdate',
      child: Text('Update database record'),
    ),
    PopupMenuItem(value: 'databaseQuery', child: Text('Load database records')),
    PopupMenuItem(
      value: 'databaseDelete',
      child: Text('Delete database record'),
    ),
    PopupMenuItem(value: 'customFunction', child: Text('Run custom function')),
  ];

  Widget _nestedActionEditor(
    BuilderNode node,
    String parentId,
    Map<String, Object?> parent,
    String field,
    String label,
  ) {
    final List<Map<String, Object?>> actions = _actionMaps(parent[field]);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EditorPalette.surface(context),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: EditorPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
          if (actions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No steps yet.',
                style: TextStyle(
                  fontSize: 10,
                  color: EditorPalette.mutedText(context),
                ),
              ),
            ),
          for (int index = 0; index < actions.length; index++)
            _actionCard(node, actions[index], index),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              tooltip: 'Add nested action',
              onSelected: (String type) {
                final List<Map<String, Object?>> next = _actionMaps(
                  parent[field],
                );
                next.add(_createAction(_newActionId(node), type));
                _setActionValues(node, parentId, <String, Object?>{
                  field: next,
                });
              },
              itemBuilder: (BuildContext context) => _actionTypeItems(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.add,
                      size: 14,
                      color: EditorPalette.primary(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Add step',
                      style: TextStyle(
                        fontSize: 10,
                        color: EditorPalette.primary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _conditionalActionFields(
    BuilderNode node,
    String id,
    Map<String, Object?> action,
  ) {
    const List<String> operators = <String>[
      'equals',
      'notEquals',
      'greaterThan',
      'lessThan',
      'contains',
      'isTrue',
      'isFalse',
    ];
    final String variableId = action['variableId'] as String? ?? '';
    final String operator =
        operators.contains(action['operator'])
            ? action['operator']! as String
            : 'equals';
    return <Widget>[
      DropdownButtonFormField<String>(
        key: ValueKey<String>(
          'condition-variable-$id-$variableId-${widget.variables.length}',
        ),
        initialValue:
            widget.variables.any(
                  (BuilderVariable item) => item.id == variableId,
                )
                ? variableId
                : '',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Check app variable'),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem(value: '', child: Text('Choose a variable')),
          ...widget.variables.map(
            (BuilderVariable item) => DropdownMenuItem(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (String? value) {
          if (value != null) _setActionValue(node, id, 'variableId', value);
        },
      ),
      const SizedBox(height: 7),
      DropdownButtonFormField<String>(
        key: ValueKey<String>('condition-operator-$id-$operator'),
        initialValue: operator,
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Condition'),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'equals', child: Text('Equals')),
          DropdownMenuItem(value: 'notEquals', child: Text('Does not equal')),
          DropdownMenuItem(
            value: 'greaterThan',
            child: Text('Is greater than'),
          ),
          DropdownMenuItem(value: 'lessThan', child: Text('Is less than')),
          DropdownMenuItem(value: 'contains', child: Text('Contains')),
          DropdownMenuItem(value: 'isTrue', child: Text('Is true')),
          DropdownMenuItem(value: 'isFalse', child: Text('Is false')),
        ],
        onChanged: (String? value) {
          if (value != null) _setActionValue(node, id, 'operator', value);
        },
      ),
      if (!<String>{'isTrue', 'isFalse'}.contains(operator)) ...<Widget>[
        const SizedBox(height: 7),
        _actionTextField(node, id, action, 'value', 'Compare with'),
      ],
    ];
  }

  List<Widget> _databaseActionFields(
    BuilderNode node,
    String id,
    Map<String, Object?> action,
    String type,
  ) {
    final String collectionId = action['collectionId'] as String? ?? '';
    final String resultId = action['resultVariableId'] as String? ?? '';
    final BuilderDatabaseCollection? collection = _firstOrNull(
      widget.databaseCollections.where(
        (BuilderDatabaseCollection item) => item.id == collectionId,
      ),
    );
    final List<BuilderDatabaseField> fields =
        collection?.fields ?? <BuilderDatabaseField>[];
    final List<Map<String, Object?>> joins = _actionMaps(action['joins']);
    final Map<String, BuilderDatabaseCollection> collectionsById =
        <String, BuilderDatabaseCollection>{
          for (final BuilderDatabaseCollection item
              in widget.databaseCollections)
            item.id: item,
        };
    final List<Map<String, Object?>> resolvedJoins = resolveDatabaseQueryJoins(
      rootCollectionId: collectionId,
      relationships: widget.databaseRelationships,
      collectionsById: collectionsById,
      configuredJoins: joins,
    );
    final List<Map<String, Object?>> fieldScopes = <Map<String, Object?>>[
      for (final BuilderDatabaseField field in fields)
        <String, Object?>{
          'relationshipId': '',
          'alias': collection?.name ?? 'Base collection',
          'field': field,
        },
      for (final Map<String, Object?> join in resolvedJoins)
        for (final BuilderDatabaseField field
            in (collectionsById[join['relatedCollectionId']]?.fields ??
                const <BuilderDatabaseField>[]))
          <String, Object?>{
            'relationshipId': join['relationshipId'],
            'alias': join['alias'],
            'field': field,
          },
    ];
    final List<Map<String, Object?>> filters = _actionMaps(action['filters']);
    final String filterMode = action['filterMode'] == 'any' ? 'any' : 'all';
    final String sortRelationshipId =
        action['sortRelationshipId'] as String? ?? '';
    final String sortFieldId = action['sortFieldId'] as String? ?? '';

    String fieldToken(String relationshipId, String fieldId) =>
        jsonEncode(<String>[relationshipId, fieldId]);

    String tokenFor(Map<String, Object?> item) => fieldToken(
      item['relationshipId'] as String? ?? '',
      (item['field']! as BuilderDatabaseField).id,
    );

    Map<String, Object?>? selectedScope(String relationshipId, String fieldId) {
      for (final Map<String, Object?> scope in fieldScopes) {
        final BuilderDatabaseField field =
            scope['field']! as BuilderDatabaseField;
        if (scope['relationshipId'] == relationshipId && field.id == fieldId) {
          return scope;
        }
      }
      return null;
    }

    void updateFilter(int index, Map<String, Object?> changes) {
      final List<Map<String, Object?>> updated = <Map<String, Object?>>[
        ...filters,
      ];
      updated[index] = <String, Object?>{...updated[index], ...changes};
      _setActionValue(node, id, 'filters', updated);
    }

    final List<BuilderVariable> jsonVariables =
        widget.variables
            .where((BuilderVariable variable) => variable.type == 'json')
            .toList();
    final Set<String> selectedRelationshipIds = <String>{
      for (final Map<String, Object?> join in joins)
        if (join['relationshipId'] is String) join['relationshipId']! as String,
    };
    final List<BuilderDatabaseRelationship> availableRelationships =
        widget.databaseRelationships.where((BuilderDatabaseRelationship item) {
          if (item.fromCollectionId != collectionId &&
              item.toCollectionId != collectionId) {
            return false;
          }
          final String relatedId =
              item.fromCollectionId == collectionId
                  ? item.toCollectionId
                  : item.fromCollectionId;
          return collectionsById.containsKey(relatedId) &&
              !selectedRelationshipIds.contains(item.id);
        }).toList();
    return <Widget>[
      DropdownButtonFormField<String>(
        key: ValueKey<String>('database-collection-$id-$collectionId'),
        initialValue:
            widget.databaseCollections.any(
                  (BuilderDatabaseCollection item) => item.id == collectionId,
                )
                ? collectionId
                : '',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Collection'),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem(value: '', child: Text('Choose a collection')),
          ...widget.databaseCollections.map(
            (BuilderDatabaseCollection item) => DropdownMenuItem(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (String? value) {
          if (value == null) return;
          if (type == 'databaseQuery') {
            _setActionValues(node, id, <String, Object?>{
              'collectionId': value,
              'joins': <Map<String, Object?>>[],
              'filters': <Map<String, Object?>>[],
              'sortRelationshipId': '',
              'sortFieldId': '',
            });
          } else {
            _setActionValue(node, id, 'collectionId', value);
          }
        },
      ),
      if (widget.databaseCollections.isEmpty) ...<Widget>[
        const SizedBox(height: 5),
        const Text('Create a collection in Resources → Database first.'),
      ],
      if (type == 'databaseInsert') ...<Widget>[
        const SizedBox(height: 8),
        _actionTextField(
          node,
          id,
          action,
          'record',
          'Record JSON',
          maxLines: 4,
          hintText: r'{"title":"$newTodo"}',
        ),
      ],
      if (type == 'databaseUpdate') ...<Widget>[
        const SizedBox(height: 8),
        _actionTextField(
          node,
          id,
          action,
          'recordId',
          'Record ID',
          hintText: r'Use ${record._id} inside a Database List item.',
        ),
        const SizedBox(height: 8),
        _actionTextField(
          node,
          id,
          action,
          'record',
          'Fields to update (JSON)',
          maxLines: 4,
          hintText: r'{"done":true} or {"title":"${record.title}"}',
        ),
      ],
      if (type == 'databaseQuery') ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'Related collections',
          style: TextStyle(
            color: EditorPalette.text(context),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        ...joins.asMap().entries.map((
          MapEntry<int, Map<String, Object?>> entry,
        ) {
          final int index = entry.key;
          final Map<String, Object?> join = entry.value;
          final String relationshipId = join['relationshipId'] as String? ?? '';
          final BuilderDatabaseRelationship? relationship = _firstOrNull(
            widget.databaseRelationships.where(
              (BuilderDatabaseRelationship item) =>
                  item.id == relationshipId &&
                  (item.fromCollectionId == collectionId ||
                      item.toCollectionId == collectionId),
            ),
          );
          final Map<String, Object?>? resolved = _firstOrNull(
            resolvedJoins.where(
              (Map<String, Object?> item) =>
                  item['relationshipId'] == relationshipId,
            ),
          );
          final String alias = join['alias'] as String? ?? '';
          final String joinType =
              join['joinType'] == 'inner' ? 'inner' : 'left';
          return Container(
            key: ValueKey<String>('database-query-join-$id-$relationshipId'),
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: EditorPalette.border(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        resolved == null
                            ? relationship?.name ?? relationshipId
                            : '${collectionsById[resolved['relatedCollectionId']]?.name ?? relationshipId}${resolved['many'] == true ? ' · many' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove related collection',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final List<Map<String, Object?>> updatedJoins =
                            <Map<String, Object?>>[
                              for (int item = 0; item < joins.length; item++)
                                if (item != index) joins[item],
                            ];
                        final List<Map<String, Object?>> updatedFilters =
                            <Map<String, Object?>>[
                              for (final Map<String, Object?> filter in filters)
                                if (filter['relationshipId'] != relationshipId)
                                  filter,
                            ];
                        _setActionValues(node, id, <String, Object?>{
                          'joins': updatedJoins,
                          'filters': updatedFilters,
                          if (sortRelationshipId == relationshipId)
                            'sortRelationshipId': '',
                          if (sortRelationshipId == relationshipId)
                            'sortFieldId': '',
                        });
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                TextFormField(
                  key: ValueKey<String>('query-join-alias-$id-$relationshipId'),
                  initialValue: alias,
                  decoration: _inputDecoration(
                    labelText: 'Result key',
                    hintText: 'Nested key for related data',
                  ),
                  onChanged: (String value) {
                    final List<Map<String, Object?>> updated =
                        <Map<String, Object?>>[
                          for (int item = 0; item < joins.length; item++)
                            if (item == index)
                              <String, Object?>{...joins[item], 'alias': value}
                            else
                              joins[item],
                        ];
                    _setActionValue(node, id, 'joins', updated);
                  },
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'query-join-type-$id-$relationshipId-$joinType',
                  ),
                  initialValue: joinType,
                  isExpanded: true,
                  decoration: _inputDecoration(labelText: 'Join type'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'left',
                      child: Text('Left join · keep unmatched rows'),
                    ),
                    DropdownMenuItem(
                      value: 'inner',
                      child: Text('Inner join · matching rows only'),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value == null) return;
                    final List<Map<String, Object?>> updated =
                        <Map<String, Object?>>[
                          for (int item = 0; item < joins.length; item++)
                            if (item == index)
                              <String, Object?>{
                                ...joins[item],
                                'joinType': value,
                              }
                            else
                              joins[item],
                        ];
                    _setActionValue(node, id, 'joins', updated);
                  },
                ),
              ],
            ),
          );
        }),
        DropdownButtonFormField<String>(
          key: ValueKey<String>('query-add-join-$id-${joins.length}'),
          initialValue: '',
          isExpanded: true,
          decoration: _inputDecoration(labelText: 'Add a relationship'),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem(
              value: '',
              child: Text('Choose related collection'),
            ),
            ...availableRelationships.map((BuilderDatabaseRelationship item) {
              final String relatedId =
                  item.fromCollectionId == collectionId
                      ? item.toCollectionId
                      : item.fromCollectionId;
              return DropdownMenuItem<String>(
                value: item.id,
                child: Text(
                  '${collectionsById[relatedId]?.name ?? item.name} · ${item.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (String? value) {
            if (value == null || value.isEmpty) return;
            final BuilderDatabaseRelationship? relationship = _firstOrNull(
              availableRelationships.where(
                (BuilderDatabaseRelationship item) => item.id == value,
              ),
            );
            if (relationship == null) return;
            final String relatedId =
                relationship.fromCollectionId == collectionId
                    ? relationship.toCollectionId
                    : relationship.fromCollectionId;
            final String baseAlias =
                collectionsById[relatedId]?.name ?? relationship.name;
            final Set<String> aliases = <String>{
              '_id',
              ...fields.map((BuilderDatabaseField field) => field.id),
              for (final Map<String, Object?> join in joins)
                (join['alias'] as String? ?? '').trim(),
            };
            String alias = baseAlias;
            int suffix = 2;
            while (aliases.contains(alias) || alias == '_id') {
              alias = '${baseAlias}_$suffix';
              suffix++;
            }
            _setActionValue(node, id, 'joins', <Map<String, Object?>>[
              ...joins,
              <String, Object?>{
                'relationshipId': value,
                'alias': alias,
                'joinType': 'left',
              },
            ]);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Conditions',
          style: TextStyle(
            color: EditorPalette.text(context),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        if (filters.length > 1)
          DropdownButtonFormField<String>(
            key: ValueKey<String>('query-filter-mode-$id-$filterMode'),
            initialValue: filterMode,
            isExpanded: true,
            decoration: _inputDecoration(labelText: 'Match conditions'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'all',
                child: Text('All conditions (AND)'),
              ),
              DropdownMenuItem(value: 'any', child: Text('Any condition (OR)')),
            ],
            onChanged: (String? value) {
              if (value != null) {
                _setActionValue(node, id, 'filterMode', value);
              }
            },
          ),
        ...List<Widget>.generate(filters.length, (int index) {
          final Map<String, Object?> filter = filters[index];
          final String filterId = filter['id'] as String? ?? 'filter_$index';
          final String fieldId = filter['fieldId'] as String? ?? '';
          final String filterRelationshipId =
              filter['relationshipId'] as String? ?? '';
          final String operator = filter['operator'] as String? ?? 'equals';
          final Map<String, Object?>? filterScope = selectedScope(
            filterRelationshipId,
            fieldId,
          );
          final BuilderDatabaseField? filterField =
              filterScope?['field'] as BuilderDatabaseField?;
          final String selectedToken = fieldToken(
            filterRelationshipId,
            fieldId,
          );
          return Container(
            key: ValueKey<String>('database-query-filter-$id-$filterId'),
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: EditorPalette.border(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>(
                          'query-field-$id-$filterId-$selectedToken',
                        ),
                        initialValue: filterScope != null ? selectedToken : '',
                        isExpanded: true,
                        decoration: _inputDecoration(labelText: 'Field'),
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Choose field'),
                          ),
                          ...fieldScopes.map((Map<String, Object?> scope) {
                            final BuilderDatabaseField field =
                                scope['field']! as BuilderDatabaseField;
                            return DropdownMenuItem<String>(
                              value: tokenFor(scope),
                              child: Text(
                                '${scope['alias']}.${field.name} · ${field.id} (${field.type})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: (String? value) {
                          if (value != null && value.isNotEmpty) {
                            final List<Object?> selected =
                                jsonDecode(value) as List<Object?>;
                            updateFilter(index, <String, Object?>{
                              'relationshipId': selected[0] as String,
                              'fieldId': selected[1] as String,
                            });
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove condition',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final List<Map<String, Object?>> updated =
                            <Map<String, Object?>>[
                              for (int item = 0; item < filters.length; item++)
                                if (item != index) filters[item],
                            ];
                        _setActionValue(node, id, 'filters', updated);
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'query-operator-$id-$filterId-$operator',
                  ),
                  initialValue: operator,
                  isExpanded: true,
                  decoration: _inputDecoration(labelText: 'Operator'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'equals', child: Text('Equals')),
                    DropdownMenuItem(
                      value: 'notEquals',
                      child: Text('Does not equal'),
                    ),
                    DropdownMenuItem(
                      value: 'contains',
                      child: Text('Contains'),
                    ),
                    DropdownMenuItem(
                      value: 'greaterThan',
                      child: Text('Greater than'),
                    ),
                    DropdownMenuItem(
                      value: 'greaterThanOrEqual',
                      child: Text('Greater than or equal to'),
                    ),
                    DropdownMenuItem(
                      value: 'lessThan',
                      child: Text('Less than'),
                    ),
                    DropdownMenuItem(
                      value: 'lessThanOrEqual',
                      child: Text('Less than or equal to'),
                    ),
                    DropdownMenuItem(value: 'isNull', child: Text('Is empty')),
                    DropdownMenuItem(
                      value: 'isNotNull',
                      child: Text('Is not empty'),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) {
                      updateFilter(index, <String, Object?>{'operator': value});
                    }
                  },
                ),
                if (!<String>{
                  'isNull',
                  'isNotNull',
                }.contains(operator)) ...<Widget>[
                  const SizedBox(height: 6),
                  TextFormField(
                    key: ValueKey<String>('query-value-$id-$filterId'),
                    initialValue: filter['value']?.toString() ?? '',
                    decoration: _inputDecoration(
                      labelText:
                          'Value${filterField == null ? '' : ' (${filterField.type})'}',
                      hintText: 'Type a value or use \${variableId}',
                    ),
                    onChanged:
                        (String value) => updateFilter(index, <String, Object?>{
                          'value': value,
                        }),
                  ),
                ],
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed:
                fieldScopes.isEmpty
                    ? null
                    : () {
                      final String filterId =
                          'query_filter_${DateTime.now().microsecondsSinceEpoch}';
                      _setActionValue(
                        node,
                        id,
                        'filters',
                        <Map<String, Object?>>[
                          ...filters,
                          <String, Object?>{
                            'id': filterId,
                            'relationshipId':
                                fieldScopes.first['relationshipId'],
                            'fieldId':
                                (fieldScopes.first['field']!
                                        as BuilderDatabaseField)
                                    .id,
                            'operator': 'equals',
                            'value': '',
                          },
                        ],
                      );
                    },
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Add condition'),
          ),
        ),
        if (collection != null && fieldScopes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Define fields in Resources → Database to filter or sort.',
            ),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
            'query-sort-field-$id-$sortRelationshipId-$sortFieldId',
          ),
          initialValue:
              selectedScope(sortRelationshipId, sortFieldId) == null
                  ? ''
                  : fieldToken(sortRelationshipId, sortFieldId),
          isExpanded: true,
          decoration: _inputDecoration(labelText: 'Sort by (optional)'),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem(value: '', child: Text('No sorting')),
            ...fieldScopes.map((Map<String, Object?> scope) {
              final BuilderDatabaseField field =
                  scope['field']! as BuilderDatabaseField;
              return DropdownMenuItem<String>(
                value: tokenFor(scope),
                child: Text(
                  '${scope['alias']}.${field.name} · ${field.id}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (String? value) {
            if (value == null) return;
            final List<Object?> selected =
                value.isEmpty
                    ? <Object?>['', '']
                    : jsonDecode(value) as List<Object?>;
            _setActionValues(node, id, <String, Object?>{
              'sortRelationshipId': selected[0] as String,
              'sortFieldId': selected[1] as String,
            });
          },
        ),
        if (resolvedJoins.any(
          (Map<String, Object?> join) =>
              join['relationshipId'] == sortRelationshipId &&
              join['many'] == true,
        )) ...<Widget>[
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(
              'query-sort-aggregate-$id-${action['sortAggregate']}',
            ),
            initialValue: action['sortAggregate'] == 'max' ? 'max' : 'min',
            isExpanded: true,
            decoration: _inputDecoration(
              labelText: 'Related row value for sorting',
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'min',
                child: Text('Lowest related value'),
              ),
              DropdownMenuItem(
                value: 'max',
                child: Text('Highest related value'),
              ),
            ],
            onChanged: (String? value) {
              if (value != null) {
                _setActionValue(node, id, 'sortAggregate', value);
              }
            },
          ),
        ],
        const SizedBox(height: 6),
        DropdownButtonFormField<bool>(
          key: ValueKey<String>(
            'query-sort-direction-$id-${action['sortDescending']}',
          ),
          initialValue: action['sortDescending'] == true,
          isExpanded: true,
          decoration: _inputDecoration(labelText: 'Sort direction'),
          items: const <DropdownMenuItem<bool>>[
            DropdownMenuItem(value: false, child: Text('Ascending')),
            DropdownMenuItem(value: true, child: Text('Descending')),
          ],
          onChanged: (bool? value) {
            if (value != null) {
              _setActionValue(node, id, 'sortDescending', value);
            }
          },
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey<String>('query-limit-$id'),
          initialValue: action['limit']?.toString() ?? '0',
          keyboardType: TextInputType.number,
          decoration: _inputDecoration(
            labelText: 'Maximum rows (0 = no limit)',
          ),
          onChanged: (String value) {
            final int? parsed = int.tryParse(value);
            if (parsed != null && parsed >= 0) {
              _setActionValue(
                node,
                id,
                'limit',
                parsed.clamp(0, 100000).toInt(),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey<String>('database-result-$id-$resultId'),
          initialValue:
              jsonVariables.any(
                    (BuilderVariable variable) => variable.id == resultId,
                  )
                  ? resultId
                  : '',
          isExpanded: true,
          decoration: _inputDecoration(
            labelText: 'Store rows in JSON variable',
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem(
              value: '',
              child: Text('Choose a JSON variable'),
            ),
            ...jsonVariables.map(
              (BuilderVariable variable) => DropdownMenuItem(
                value: variable.id,
                child: Text(variable.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (String? value) {
            if (value != null) {
              _setActionValue(node, id, 'resultVariableId', value);
            }
          },
        ),
      ],
      if (type == 'databaseDelete') ...<Widget>[
        const SizedBox(height: 8),
        _actionTextField(
          node,
          id,
          action,
          'recordId',
          'Record ID',
          hintText: r'Use ${record._id} inside a Database List item.',
        ),
      ],
    ];
  }

  List<Widget> _httpRequestActionFields(
    BuilderNode node,
    String id,
    Map<String, Object?> action,
  ) {
    final String method =
        <String>{
              'GET',
              'POST',
              'PUT',
              'PATCH',
              'DELETE',
            }.contains(action['method'])
            ? action['method']! as String
            : 'GET';
    final String responseId = action['responseVariableId'] as String? ?? '';
    return <Widget>[
      DropdownButtonFormField<String>(
        key: ValueKey<String>('http-method-$id-$method'),
        isExpanded: true,
        initialValue: method,
        decoration: _inputDecoration(labelText: 'Method'),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'GET', child: Text('GET')),
          DropdownMenuItem(value: 'POST', child: Text('POST')),
          DropdownMenuItem(value: 'PUT', child: Text('PUT')),
          DropdownMenuItem(value: 'PATCH', child: Text('PATCH')),
          DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
        ],
        onChanged: (String? value) {
          if (value != null) _setActionValue(node, id, 'method', value);
        },
      ),
      const SizedBox(height: 7),
      _actionTextField(
        node,
        id,
        action,
        'url',
        'Request URL',
        hintText: r'Use ${variableId} or $variableName',
      ),
      const SizedBox(height: 7),
      _actionTextField(
        node,
        id,
        action,
        'headers',
        'Headers (JSON)',
        maxLines: 3,
        hintText: r'Variable values such as ${token} can be inserted.',
      ),
      const SizedBox(height: 7),
      _actionTextField(
        node,
        id,
        action,
        'body',
        'Body',
        maxLines: 3,
        hintText: r'Variable values such as ${userId} can be inserted.',
      ),
      const SizedBox(height: 7),
      DropdownButtonFormField<String>(
        key: ValueKey<String>(
          'http-response-$id-$responseId-${widget.variables.length}',
        ),
        initialValue:
            widget.variables.any(
                  (BuilderVariable item) => item.id == responseId,
                )
                ? responseId
                : '',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Save response body to'),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem(value: '', child: Text('Discard response')),
          ...widget.variables.map(
            (BuilderVariable item) => DropdownMenuItem(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (String? value) {
          if (value != null)
            _setActionValue(node, id, 'responseVariableId', value);
        },
      ),
    ];
  }

  Widget _actionIntegerField(
    BuilderNode node,
    String id,
    Map<String, Object?> action,
    String field,
    String label,
  ) => TextFormField(
    key: ValueKey<String>('action-integer-$id-$field'),
    initialValue: action[field]?.toString() ?? '1',
    keyboardType: TextInputType.number,
    decoration: _inputDecoration(labelText: label),
    onChanged: (String value) {
      final int? parsed = int.tryParse(value);
      if (parsed != null)
        _setActionValue(node, id, field, parsed.clamp(1, 1000));
    },
  );

  List<Widget> _customFunctionActionFields(
    BuilderNode node,
    String actionId,
    Map<String, Object?> action,
  ) {
    final String functionId = action['functionId'] as String? ?? '';
    final bool hasFunction = widget.customFunctions.any(
      (BuilderCustomFunction function) => function.id == functionId,
    );
    return <Widget>[
      DropdownButtonFormField<String>(
        key: ValueKey<String>(
          'action-function-$actionId-$functionId-${widget.customFunctions.length}',
        ),
        initialValue: hasFunction ? functionId : '',
        isExpanded: true,
        decoration: _inputDecoration(labelText: 'Custom function'),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Choose a function'),
          ),
          ...widget.customFunctions.map(
            (BuilderCustomFunction function) => DropdownMenuItem<String>(
              value: function.id,
              child: Text(function.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (String? value) {
          if (value != null)
            _setActionValue(node, actionId, 'functionId', value);
        },
      ),
      if (_customFunctionDraftId == null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final BuilderCustomFunction? function = await _editCustomFunction(
                node,
              );
              if (function != null) {
                _setActionValue(node, actionId, 'functionId', function.id);
              }
            },
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Create function'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              textStyle: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      if (functionId.isNotEmpty && !hasFunction)
        const Padding(
          padding: const EdgeInsets.only(top: 4),
          child: const Text(
            'This function was removed. Choose another function.',
            style: const TextStyle(
              color: const Color(0xFF9C3535),
              fontSize: 10,
            ),
          ),
        ),
    ];
  }

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
        color: EditorPalette.surfaceRaised(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EditorPalette.border(context)),
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
                  color: EditorPalette.primaryContainer(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: EditorPalette.primary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _actionName(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: EditorPalette.text(context),
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
                onPressed: () => _removeAction(node, id),
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
              DropdownMenuItem(value: 'conditional', child: Text('If / else')),
              DropdownMenuItem(value: 'loop', child: Text('Repeat actions')),
              DropdownMenuItem(
                value: 'httpRequest',
                child: Text('HTTP request'),
              ),
              DropdownMenuItem(
                value: 'databaseInsert',
                child: Text('Save database record'),
              ),
              DropdownMenuItem(
                value: 'databaseUpdate',
                child: Text('Update database record'),
              ),
              DropdownMenuItem(
                value: 'databaseQuery',
                child: Text('Load database records'),
              ),
              DropdownMenuItem(
                value: 'databaseDelete',
                child: Text('Delete database record'),
              ),
              DropdownMenuItem(
                value: 'customFunction',
                child: Text('Run custom function'),
              ),
            ],
            onChanged: (String? nextType) {
              if (nextType == null) return;
              _replaceAction(node, id, _createAction(id, nextType));
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
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'Returns to the previous page in the preview or running app.',
                style: TextStyle(
                  color: EditorPalette.mutedText(context),
                  fontSize: 10,
                ),
              ),
            ),
          if (type == 'setVariable' ||
              type == 'incrementVariable' ||
              type == 'toggleVariable') ...<Widget>[
            const SizedBox(height: 8),
            ..._variableActionFields(node, id, action, type),
          ],
          if (type == 'updateWidget') ...<Widget>[
            const SizedBox(height: 8),
            ..._updateWidgetActionFields(node, id, action),
          ],
          if (type == 'conditional') ...<Widget>[
            const SizedBox(height: 8),
            ..._conditionalActionFields(node, id, action),
            const SizedBox(height: 8),
            _nestedActionEditor(node, id, action, 'thenActions', 'If true'),
            const SizedBox(height: 8),
            _nestedActionEditor(node, id, action, 'elseActions', 'If false'),
          ],
          if (type == 'loop') ...<Widget>[
            const SizedBox(height: 8),
            _actionIntegerField(node, id, action, 'iterations', 'Repeat count'),
            const SizedBox(height: 8),
            _nestedActionEditor(node, id, action, 'actions', 'Loop actions'),
          ],
          if (type == 'httpRequest') ...<Widget>[
            const SizedBox(height: 8),
            ..._httpRequestActionFields(node, id, action),
          ],
          if (<String>{
            'databaseInsert',
            'databaseUpdate',
            'databaseQuery',
            'databaseDelete',
          }.contains(type)) ...<Widget>[
            const SizedBox(height: 8),
            ..._databaseActionFields(node, id, action, type),
          ],
          if (type == 'customFunction') ...<Widget>[
            const SizedBox(height: 8),
            ..._customFunctionActionFields(node, id, action),
          ],
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
    String? hintText,
  }) => TextFormField(
    key: ValueKey<String>('action-field-${node.id}-$id-$field'),
    initialValue:
        action[field] is String
            ? action[field]! as String
            : action[field] is List || action[field] is Map
            ? jsonEncode(action[field])
            : action[field]?.toString() ?? '',
    maxLines: maxLines,
    decoration: _inputDecoration(labelText: label, hintText: hintText),
    onChanged: (String value) => _setActionValue(node, id, field, value),
  );

  void _setActionValue(BuilderNode node, String id, String key, Object? value) {
    _setActionValues(node, id, <String, Object?>{key: value});
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
    'conditional' => 'If / else',
    'loop' => 'Repeat actions',
    'httpRequest' => 'HTTP request',
    'databaseInsert' => 'Save database record',
    'databaseUpdate' => 'Update database record',
    'databaseQuery' => 'Load database records',
    'databaseDelete' => 'Delete database record',
    'customFunction' => 'Run custom function',
    _ => 'Action',
  };

  List<Widget> _buttonStyleProperties(BuilderNode node) => <Widget>[
    _fieldLabel('Style'),
    const SizedBox(height: 6),
    SegmentedButton<String>(
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'filled', label: Text('Filled')),
        ButtonSegment<String>(value: 'elevated', label: Text('Elevated')),
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
      style: TextStyle(
        color: EditorPalette.mutedText(context),
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
      isExpanded: true,
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
      isExpanded: true,
      decoration: _inputDecoration(),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(value: 'start', child: Text('Start')),
        DropdownMenuItem<String>(value: 'center', child: Text('Center')),
        DropdownMenuItem<String>(value: 'end', child: Text('End')),
        DropdownMenuItem<String>(value: 'stretch', child: Text('Stretch')),
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
    Object? fallback,
    int minLines = 1,
    int maxLines = 1,
  }) => TextField(
    key: ValueKey<String>('${node.id}-$property'),
    controller: _controllerFor(node, property, fallback: fallback),
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
    double min = 0,
    double max = 1200,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _fieldLabel(label),
      const SizedBox(height: 5),
      _compactNumberField(
        node,
        property,
        fallback: fallback,
        min: min,
        max: max,
      ),
    ],
  );

  Widget _integerField(
    BuilderNode node,
    String property, {
    required String label,
    required int fallback,
    int max = 100,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _fieldLabel(label),
      const SizedBox(height: 5),
      TextField(
        key: ValueKey<String>('${node.id}-$property'),
        controller: _controllerFor(node, property, fallback: fallback),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
        onChanged: (String value) {
          final int? parsed = int.tryParse(value);
          if (parsed != null) {
            widget.onSetProperty(node.id, property, parsed.clamp(1, max));
          }
        },
        decoration: _inputDecoration(),
      ),
    ],
  );

  Widget _compactNumberField(
    BuilderNode node,
    String property, {
    required double fallback,
    double min = 0,
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
        widget.onSetProperty(node.id, property, parsed.clamp(min, max));
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
    style: TextStyle(
      color: EditorPalette.text(context),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _inputDecoration({String? hintText, String? labelText}) =>
      InputDecoration(
        hintText: hintText,
        labelText: labelText,
        filled: true,
        fillColor: EditorPalette.surface(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: EditorPalette.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: EditorPalette.border(context)),
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
    return const <String>{'elevated', 'outlined', 'text'}.contains(style)
        ? style! as String
        : 'filled';
  }

  String _iconButtonStyle(Object? value) =>
      const <String>{'filled', 'filledTonal', 'outlined'}.contains(value)
          ? value! as String
          : 'standard';

  String _alignmentValue(Object? value) => switch (value) {
    'center' => 'center',
    'end' => 'end',
    'spaceBetween' => 'spaceBetween',
    _ => 'start',
  };

  String _crossAlignmentValue(Object? value) => switch (value) {
    'center' => 'center',
    'end' => 'end',
    'stretch' => 'stretch',
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

  int _integer(Object? value, int fallback) =>
      value is num && value.isFinite ? value.round() : fallback;

  String _typeLabel(String type) =>
      builderWidgetDefinitionFor(type)?.name ?? type;
}

class _ResponsiveOverridesEditor extends StatefulWidget {
  const _ResponsiveOverridesEditor({
    required this.node,
    required this.onChanged,
    super.key,
  });

  final BuilderNode node;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<_ResponsiveOverridesEditor> createState() =>
      _ResponsiveOverridesEditorState();
}

class _ResponsiveOverridesEditorState
    extends State<_ResponsiveOverridesEditor> {
  static const Map<String, String> _breakpoints = <String, String>{
    'phone': 'Phone · up to 600 px',
    'tablet': 'Tablet · 601–1024 px',
    'desktop': 'Desktop · over 1024 px',
  };
  static const List<String> _properties = <String>[
    'width',
    'height',
    'fontSize',
    'padding',
    'margin',
    'opacity',
    'visible',
    'color',
    'backgroundColor',
  ];

  String _breakpoint = 'phone';
  String _property = 'width';
  final TextEditingController _value = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _value.text = _overrides[_breakpoint]?[_property]?.toString() ?? '';
  }

  @override
  void didUpdateWidget(covariant _ResponsiveOverridesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.node.properties['responsiveOverrides'] !=
            widget.node.properties['responsiveOverrides']) {
      _value.text = _overrides[_breakpoint]?[_property]?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Map<String, Map<String, Object?>> get _overrides {
    final Object? raw = widget.node.properties['responsiveOverrides'];
    if (raw is! Map) return <String, Map<String, Object?>>{};
    return <String, Map<String, Object?>>{
      for (final String key in _breakpoints.keys)
        if (raw[key] is Map) key: Map<String, Object?>.from(raw[key]! as Map),
    };
  }

  void _apply() {
    final Object? value = _parseValue(_value.text.trim());
    if (value == null) {
      setState(() => _error = 'Enter a valid value for $_property.');
      return;
    }
    final Map<String, Map<String, Object?>> next = _overrides;
    next.putIfAbsent(_breakpoint, () => <String, Object?>{})[_property] = value;
    widget.onChanged(<String, Object?>{
      for (final MapEntry<String, Map<String, Object?>> entry in next.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    });
    setState(() => _error = null);
  }

  Object? _parseValue(String value) {
    if (_property == 'visible') {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
      return null;
    }
    if (_property == 'color' || _property == 'backgroundColor') {
      final String digits = value.replaceFirst(
        RegExp(r'^(#|0x)', caseSensitive: false),
        '',
      );
      final int? parsed = int.tryParse(digits, radix: 16);
      if (parsed == null) return null;
      return digits.length <= 6 ? 0xFF000000 | parsed : parsed;
    }
    final double? parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) return null;
    return _property == 'opacity' ? parsed.clamp(0, 1).toDouble() : parsed;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, Map<String, Object?>> overrides = _overrides;
    final Map<String, Object?> values =
        overrides[_breakpoint] ?? const <String, Object?>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Overrides apply at the selected screen width and carry into export.',
          style: TextStyle(
            color: EditorPalette.mutedText(context),
            fontSize: 10,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _breakpoint,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, labelText: 'Width'),
          items:
              _breakpoints.entries
                  .map(
                    (MapEntry<String, String> entry) =>
                        DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  )
                  .toList(),
          onChanged: (String? value) {
            if (value != null) {
              setState(() {
                _breakpoint = value;
                _value.text = _overrides[value]?[_property]?.toString() ?? '';
              });
            }
          },
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: _property,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Property',
          ),
          items:
              _properties
                  .map(
                    (String property) => DropdownMenuItem<String>(
                      value: property,
                      child: Text(property),
                    ),
                  )
                  .toList(),
          onChanged: (String? value) {
            if (value != null) {
              setState(() {
                _property = value;
                _value.text = values[value]?.toString() ?? '';
              });
            }
          },
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _value,
          decoration: InputDecoration(
            isDense: true,
            labelText: _property == 'visible' ? 'true / false' : 'Value',
            hintText:
                _property == 'color' || _property == 'backgroundColor'
                    ? '#6750A4'
                    : null,
          ),
          onSubmitted: (_) => _apply(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFB3261E), fontSize: 10),
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Set override'),
          ),
        ),
        if (values.isNotEmpty)
          Wrap(
            spacing: 5,
            runSpacing: 3,
            children:
                values.entries
                    .map(
                      (MapEntry<String, Object?> entry) => InputChip(
                        label: Text('${entry.key}: ${entry.value}'),
                        onDeleted: () {
                          final Map<String, Map<String, Object?>> next =
                              _overrides;
                          next[_breakpoint]?.remove(entry.key);
                          next.removeWhere(
                            (String _, Map<String, Object?> value) =>
                                value.isEmpty,
                          );
                          widget.onChanged(<String, Object?>{
                            for (final MapEntry<String, Map<String, Object?>>
                                item
                                in next.entries)
                              item.key: item.value,
                          });
                        },
                      ),
                    )
                    .toList(),
          ),
      ],
    );
  }
}

class _InspectorHeading extends StatelessWidget {
  const _InspectorHeading({required this.title, required this.icon});

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
