import 'package:flutter/material.dart';

enum WidgetCategory { layout, base, form, page }

class WidgetCatalogItem {
  const WidgetCatalogItem(this.type, this.label, this.icon, this.category);

  final String type;
  final String label;
  final IconData icon;
  final WidgetCategory category;

  String get keywords => '$type $label ${category.name}';
}

const List<WidgetCatalogItem> widgetCatalog = <WidgetCatalogItem>[
  WidgetCatalogItem(
    'container',
    'Container',
    Icons.crop_square,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'row',
    'Row',
    Icons.view_week_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'expanded',
    'Expanded',
    Icons.open_in_full,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'column',
    'Column',
    Icons.view_column_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'safeArea',
    'Safe Area',
    Icons.crop_free,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'stack',
    'Stack',
    Icons.layers_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'listView',
    'ListView',
    Icons.view_agenda_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'gridView',
    'GridView',
    Icons.grid_view_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'pageView',
    'PageView',
    Icons.swipe_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'swipeableStack',
    'Swipeable Stack',
    Icons.style_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'card',
    'Card',
    Icons.credit_card_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem(
    'padding',
    'Padding',
    Icons.padding_outlined,
    WidgetCategory.layout,
  ),
  WidgetCatalogItem('text', 'Text', Icons.text_fields, WidgetCategory.base),
  WidgetCatalogItem(
    'button',
    'Button',
    Icons.smart_button_outlined,
    WidgetCategory.base,
  ),
  WidgetCatalogItem('icon', 'Icon', Icons.star_outline, WidgetCategory.base),
  WidgetCatalogItem(
    'image',
    'Image',
    Icons.image_outlined,
    WidgetCategory.base,
  ),
  WidgetCatalogItem(
    'divider',
    'Divider',
    Icons.horizontal_rule,
    WidgetCategory.base,
  ),
  WidgetCatalogItem(
    'verticalDivider',
    'Vertical Divider',
    Icons.more_vert,
    WidgetCategory.base,
  ),
  WidgetCatalogItem('textField', 'TextField', Icons.input, WidgetCategory.form),
  WidgetCatalogItem(
    'checkbox',
    'Checkbox',
    Icons.check_box_outlined,
    WidgetCategory.form,
  ),
  WidgetCatalogItem(
    'switch',
    'Switch',
    Icons.toggle_on_outlined,
    WidgetCategory.form,
  ),
  WidgetCatalogItem(
    'signature',
    'Signature',
    Icons.draw_outlined,
    WidgetCategory.form,
  ),
  WidgetCatalogItem(
    'appBar',
    'AppBar',
    Icons.web_asset_outlined,
    WidgetCategory.page,
  ),
  WidgetCatalogItem(
    'floatingActionButton',
    'Floating Action Button',
    Icons.add_circle_outline,
    WidgetCategory.page,
  ),
];

WidgetCatalogItem? catalogItemFor(String type) {
  for (final WidgetCatalogItem item in widgetCatalog) {
    if (item.type == type) return item;
  }
  return null;
}
