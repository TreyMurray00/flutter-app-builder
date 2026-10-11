sealed class EditorDragData {
  const EditorDragData();
}

final class ExistingObjectDrag extends EditorDragData {
  const ExistingObjectDrag(this.nodeId);

  final String nodeId;
}

final class PaletteObjectDrag extends EditorDragData {
  const PaletteObjectDrag(this.type);

  final String type;
}
