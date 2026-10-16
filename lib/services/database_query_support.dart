import '../models/builder_document.dart';

/// Resolves configured direct relationships into the join shape shared by the
/// preview query engine and generated database repository.
List<Map<String, Object?>> resolveDatabaseQueryJoins({
  required String rootCollectionId,
  required List<BuilderDatabaseRelationship> relationships,
  required Map<String, BuilderDatabaseCollection> collectionsById,
  required Object? configuredJoins,
}) {
  if (configuredJoins is! List) return <Map<String, Object?>>[];
  final Map<String, BuilderDatabaseRelationship> relationshipsById =
      <String, BuilderDatabaseRelationship>{
        for (final BuilderDatabaseRelationship relationship in relationships)
          relationship.id: relationship,
      };
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Object? rawJoin in configuredJoins) {
    if (rawJoin is! Map) continue;
    final String relationshipId = rawJoin['relationshipId']?.toString() ?? '';
    final BuilderDatabaseRelationship? relationship =
        relationshipsById[relationshipId];
    if (relationship == null) continue;
    final bool fromSide = relationship.fromCollectionId == rootCollectionId;
    final bool toSide = relationship.toCollectionId == rootCollectionId;
    if (!fromSide && !toSide) continue;
    final String relatedCollectionId =
        fromSide ? relationship.toCollectionId : relationship.fromCollectionId;
    final BuilderDatabaseCollection? relatedCollection =
        collectionsById[relatedCollectionId];
    final BuilderDatabaseCollection? childCollection =
        collectionsById[relationship.fromCollectionId];
    if (relatedCollection == null || childCollection == null) continue;
    final BuilderDatabaseField? foreignKey = _fieldById(
      childCollection,
      relationship.fromFieldId,
    );
    if (foreignKey == null ||
        _fieldById(
              fromSide ? childCollection : collectionsById[rootCollectionId],
              fromSide ? relationship.fromFieldId : relationship.toFieldId,
            ) ==
            null) {
      continue;
    }
    final String alias =
        rawJoin['alias']?.toString().trim().isNotEmpty == true
            ? rawJoin['alias'].toString().trim()
            : relatedCollection.name;
    result.add(<String, Object?>{
      'relationshipId': relationship.id,
      'alias': alias,
      'joinType': rawJoin['joinType'] == 'inner' ? 'inner' : 'left',
      'relatedCollectionId': relatedCollectionId,
      'baseFieldId':
          fromSide ? relationship.fromFieldId : relationship.toFieldId,
      'relatedFieldId':
          fromSide ? relationship.toFieldId : relationship.fromFieldId,
      // A parent can have many children unless the child's FK is unique.
      'many': toSide && !(foreignKey.unique || foreignKey.primaryKey),
    });
  }
  return result;
}

BuilderDatabaseField? _fieldById(
  BuilderDatabaseCollection? collection,
  String fieldId,
) {
  if (collection == null) return null;
  for (final BuilderDatabaseField field in collection.fields) {
    if (field.id == fieldId) return field;
  }
  return null;
}
