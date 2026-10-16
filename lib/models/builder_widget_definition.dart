import 'dart:collection';

class BuilderWidgetDefinition {
  const BuilderWidgetDefinition({
    required this.type,
    required this.name,
    required this.acceptsChildren,
    this.allowedChildTypes,
  });

  final String type;
  final String name;
  final bool acceptsChildren;
  final Set<String>? allowedChildTypes;

  bool accepts(String childType) =>
      acceptsChildren &&
      (allowedChildTypes == null || allowedChildTypes!.contains(childType));
}

const Set<String> _containerTypes = <String>{
  'scaffold',
  'column',
  'row',
  'expanded',
  'container',
  'safeArea',
  'stack',
  'listView',
  'databaseList',
  'singleChildScrollView',
  'gridView',
  'pageView',
  'swipeableStack',
  'card',
  'padding',
  'center',
  'align',
  'wrap',
  'sizedBox',
  'aspectRatio',
  'clipRRect',
  'flexible',
  'componentGroup',
  'badge',
  'alertDialog',
  'bottomSheet',
};

const Set<String> builderWidgetTypes = <String>{
  'scaffold',
  'column',
  'row',
  'expanded',
  'spacer',
  'safeArea',
  'container',
  'stack',
  'listView',
  'databaseList',
  'singleChildScrollView',
  'gridView',
  'pageView',
  'swipeableStack',
  'card',
  'padding',
  'center',
  'align',
  'wrap',
  'sizedBox',
  'aspectRatio',
  'clipRRect',
  'flexible',
  'componentGroup',
  'text',
  'button',
  'image',
  'icon',
  'divider',
  'verticalDivider',
  'textField',
  'checkbox',
  'switch',
  'signature',
  'appBar',
  'floatingActionButton',
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
};

final Map<String, BuilderWidgetDefinition> builderWidgetDefinitions =
    UnmodifiableMapView<String, BuilderWidgetDefinition>(
      <String, BuilderWidgetDefinition>{
        for (final String type in builderWidgetTypes)
          type: BuilderWidgetDefinition(
            type: type,
            name: _widgetName(type),
            acceptsChildren: _containerTypes.contains(type),
            allowedChildTypes:
                type == 'row' || type == 'column' ? builderWidgetTypes : null,
          ),
      },
    );

String _widgetName(String type) => switch (type) {
  'safeArea' => 'Safe Area',
  'listView' => 'List View',
  'databaseList' => 'Database List',
  'singleChildScrollView' => 'Scroll View',
  'gridView' => 'Grid View',
  'pageView' => 'Page View',
  'swipeableStack' => 'Swipeable Stack',
  'componentGroup' => 'Component Group',
  'sizedBox' => 'Sized Box',
  'aspectRatio' => 'Aspect Ratio',
  'clipRRect' => 'Clip RRect',
  'verticalDivider' => 'Vertical Divider',
  'textField' => 'Text Field',
  'appBar' => 'App Bar',
  'floatingActionButton' => 'Floating Action Button',
  'extendedFloatingActionButton' => 'Extended Floating Action Button',
  'iconButton' => 'Icon Button',
  'segmentedButton' => 'Segmented Button',
  'linearProgressIndicator' => 'Linear Progress Indicator',
  'snackBar' => 'Snack Bar',
  'alertDialog' => 'Alert Dialog',
  'bottomSheet' => 'Bottom Sheet',
  'listTile' => 'List Tile',
  'bottomAppBar' => 'Bottom App Bar',
  'navigationBar' => 'Navigation Bar',
  'navigationDrawer' => 'Navigation Drawer',
  'navigationRail' => 'Navigation Rail',
  'tabBar' => 'Tab Bar',
  'datePicker' => 'Date Picker',
  'timePicker' => 'Time Picker',
  _ => type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}',
};

BuilderWidgetDefinition? builderWidgetDefinitionFor(String type) =>
    builderWidgetDefinitions[type];

bool builderWidgetAcceptsChild(String parentType, String childType) {
  if (<String>{'expanded', 'flexible', 'spacer'}.contains(childType) &&
      parentType != 'row' &&
      parentType != 'column') {
    return false;
  }
  return builderWidgetDefinitions[parentType]?.accepts(childType) ?? false;
}

Map<String, Object?> defaultBuilderWidgetProperties(
  String type, {
  String? componentGroupId,
  String? componentGroupName,
}) => switch (type) {
  'text' => <String, Object?>{
    'text': 'New text',
    'fontSize': 18.0,
    'fontWeight': 'regular',
    'color': 0xFF303644,
  },
  'button' => <String, Object?>{'label': 'Button', 'style': 'filled'},
  'container' => <String, Object?>{
    'width': 220.0,
    'height': 100.0,
    'padding': 12.0,
    'backgroundColor': 0xFFF1EFF8,
    'borderRadius': 12.0,
  },
  'row' => <String, Object?>{
    'mainAxisAlignment': 'start',
    'crossAxisAlignment': 'center',
  },
  'expanded' => <String, Object?>{'flex': 1},
  'safeArea' => <String, Object?>{
    'top': true,
    'bottom': true,
    'left': true,
    'right': true,
    'minimum': 0.0,
  },
  'column' => <String, Object?>{
    'mainAxisAlignment': 'start',
    'crossAxisAlignment': 'start',
  },
  'stack' => <String, Object?>{
    'width': 260.0,
    'height': 160.0,
    'alignment': 'topLeft',
    'fit': 'loose',
  },
  'listView' => <String, Object?>{
    'width': 300.0,
    'height': 220.0,
    'scrollDirection': 'vertical',
    'itemSpacing': 8.0,
  },
  'databaseList' => <String, Object?>{
    'collectionId': '',
    'width': 300.0,
    'height': 320.0,
    'scrollDirection': 'vertical',
    'itemSpacing': 8.0,
    'emptyMessage': 'No records yet',
  },
  'singleChildScrollView' => <String, Object?>{
    'width': 300.0,
    'height': 220.0,
    'scrollDirection': 'vertical',
    'reverse': false,
  },
  'gridView' => <String, Object?>{
    'width': 300.0,
    'height': 220.0,
    'crossAxisCount': 2,
    'itemSpacing': 8.0,
  },
  'pageView' => <String, Object?>{'width': 300.0, 'height': 220.0},
  'swipeableStack' => <String, Object?>{
    'width': 300.0,
    'height': 220.0,
    'visibleCount': 3,
    'loop': false,
  },
  'card' => <String, Object?>{
    'width': 240.0,
    'height': 140.0,
    'padding': 12.0,
    'backgroundColor': 0xFFFFFFFF,
    'borderRadius': 12.0,
    'elevation': 2.0,
  },
  'padding' => <String, Object?>{'padding': 16.0},
  'center' => <String, Object?>{},
  'align' => <String, Object?>{'alignment': 'center'},
  'wrap' => <String, Object?>{
    'direction': 'horizontal',
    'spacing': 8.0,
    'runSpacing': 8.0,
  },
  'sizedBox' => <String, Object?>{'width': 120.0, 'height': 60.0},
  'aspectRatio' => <String, Object?>{'aspectRatio': 1.5},
  'clipRRect' => <String, Object?>{'borderRadius': 12.0},
  'flexible' => <String, Object?>{'flex': 1, 'fit': 'loose'},
  'spacer' => <String, Object?>{'flex': 1},
  'image' => <String, Object?>{
    'source': '',
    'altText': '',
    'width': 180.0,
    'height': 120.0,
    'fit': 'cover',
  },
  'icon' => <String, Object?>{
    'iconName': 'star',
    'size': 32.0,
    'color': 0xFF6750A4,
  },
  'divider' => <String, Object?>{
    'thickness': 1.0,
    'height': 24.0,
    'indent': 0.0,
    'endIndent': 0.0,
    'color': 0xFFB8BEC9,
  },
  'verticalDivider' => <String, Object?>{
    'thickness': 1.0,
    'width': 24.0,
    'height': 48.0,
    'indent': 0.0,
    'endIndent': 0.0,
    'color': 0xFFB8BEC9,
  },
  'textField' => <String, Object?>{
    'hintText': 'Enter text',
    'label': 'Text field',
    'initialValue': '',
    'width': 240.0,
    'inputVariableId': '',
  },
  'checkbox' => <String, Object?>{
    'label': 'Checkbox',
    'value': false,
    'activeColor': 0xFF6750A4,
  },
  'switch' => <String, Object?>{
    'label': 'Switch',
    'value': false,
    'activeColor': 0xFF6750A4,
  },
  'signature' => <String, Object?>{
    'width': 280.0,
    'height': 160.0,
    'strokeWidth': 2.0,
    'penColor': 0xFF20242C,
    'backgroundColor': 0xFFFFFFFF,
  },
  'appBar' => <String, Object?>{
    'title': 'App Bar',
    'backgroundColor': 0xFF6750A4,
    'foregroundColor': 0xFFFFFFFF,
    'elevation': 2.0,
  },
  'floatingActionButton' => <String, Object?>{
    'iconName': 'add',
    'backgroundColor': 0xFF6750A4,
    'foregroundColor': 0xFFFFFFFF,
  },
  'extendedFloatingActionButton' => <String, Object?>{
    'label': 'Create',
    'iconName': 'add',
    'backgroundColor': 0xFF6750A4,
    'foregroundColor': 0xFFFFFFFF,
  },
  'iconButton' => <String, Object?>{
    'iconName': 'favorite',
    'tooltip': 'Favorite',
    'style': 'standard',
  },
  'segmentedButton' => <String, Object?>{
    'options': 'Day,Week,Month',
    'selectedIndex': 0,
    'selectedOptions': 'Day',
    'multiSelect': false,
  },
  'badge' => <String, Object?>{'label': '3', 'iconName': 'notifications'},
  'linearProgressIndicator' => <String, Object?>{
    'value': 0.65,
    'minHeight': 4.0,
  },
  'snackBar' => <String, Object?>{
    'message': 'File saved',
    'actionLabel': 'Undo',
  },
  'alertDialog' => <String, Object?>{
    'title': 'Confirm action',
    'message': 'Are you sure you want to continue?',
    'confirmLabel': 'Continue',
    'cancelLabel': 'Cancel',
  },
  'bottomSheet' => <String, Object?>{
    'title': 'More options',
    'message': 'Supplementary content goes here.',
  },
  'listTile' => <String, Object?>{
    'title': 'List item',
    'subtitle': 'Supporting text',
    'leadingIcon': 'person',
    'trailingIcon': 'arrowForward',
  },
  'bottomAppBar' => <String, Object?>{
    'label': 'Bottom app bar',
    'iconName': 'add',
  },
  'navigationBar' => <String, Object?>{
    'destinations': 'Home,Search,Settings',
    'destinationIcons': 'home,search,settings',
    'selectedIndex': 0,
  },
  'navigationDrawer' => <String, Object?>{
    'destinations': 'Home,Search,Settings',
    'destinationIcons': 'home,search,settings',
    'header': 'Navigation',
    'selectedIndex': 0,
  },
  'navigationRail' => <String, Object?>{
    'destinations': 'Home,Search,Settings',
    'destinationIcons': 'home,search,settings',
    'selectedIndex': 0,
    'showLabels': true,
  },
  'tabBar' => <String, Object?>{
    'tabs': 'Overview,Details,Reviews',
    'tabIcons': 'none,none,none',
  },
  'chip' => <String, Object?>{'label': 'Filter'},
  'datePicker' => <String, Object?>{'label': 'Select date'},
  'menu' => <String, Object?>{
    'label': 'Open menu',
    'options': 'Edit,Copy,Delete',
  },
  'radio' => <String, Object?>{
    'options': 'Option one,Option two',
    'selectedOption': 'Option one',
  },
  'slider' => <String, Object?>{'min': 0.0, 'max': 100.0, 'value': 50.0},
  'timePicker' => <String, Object?>{'label': 'Select time'},
  'componentGroup' => <String, Object?>{
    'groupId': componentGroupId ?? '',
    'groupName': componentGroupName ?? '',
  },
  _ => <String, Object?>{},
};
