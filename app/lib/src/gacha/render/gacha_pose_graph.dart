import '../data/resolver_tables.dart';
import 'transform_graph.dart';

class GachaPoseAnchorDefinition {
  const GachaPoseAnchorDefinition({
    required this.id,
    required this.sourceHostName,
    this.parentId,
  });

  final String id;
  final String? sourceHostName;
  final String? parentId;
}

class GachaPoseGraph {
  const GachaPoseGraph._();

  static const List<GachaPoseAnchorDefinition> anchors = [
    GachaPoseAnchorDefinition(id: 'torso', sourceHostName: 'body'),
    GachaPoseAnchorDefinition(
      id: 'head',
      sourceHostName: 'head',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'backhair',
      sourceHostName: 'backhair',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'shoulder_front',
      sourceHostName: 'shoulder',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'shoulder_back',
      sourceHostName: 'backshoulder',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'forearm_front',
      sourceHostName: 'handx',
      parentId: 'shoulder_front',
    ),
    GachaPoseAnchorDefinition(
      id: 'forearm_back',
      sourceHostName: 'backhand',
      parentId: 'shoulder_back',
    ),
    GachaPoseAnchorDefinition(
      id: 'hip',
      sourceHostName: null,
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'thigh_front',
      sourceHostName: 'thigh',
      parentId: 'hip',
    ),
    GachaPoseAnchorDefinition(
      id: 'thigh_back',
      sourceHostName: 'backthigh',
      parentId: 'hip',
    ),
    GachaPoseAnchorDefinition(
      id: 'feet_front',
      sourceHostName: 'foot',
      parentId: 'thigh_front',
    ),
    GachaPoseAnchorDefinition(
      id: 'feet_back',
      sourceHostName: 'backfoot',
      parentId: 'thigh_back',
    ),
    GachaPoseAnchorDefinition(
      id: 'belt',
      sourceHostName: 'belt',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'cape',
      sourceHostName: 'cape',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'scarf',
      sourceHostName: 'scarf',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'wings',
      sourceHostName: 'wings',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'tail',
      sourceHostName: 'tail',
      parentId: 'torso',
    ),
    GachaPoseAnchorDefinition(
      id: 'weapon_front',
      sourceHostName: 'weapon',
      parentId: 'forearm_front',
    ),
    GachaPoseAnchorDefinition(
      id: 'weapon_back',
      sourceHostName: 'backweapon',
      parentId: 'forearm_back',
    ),
    GachaPoseAnchorDefinition(
      id: 'shield',
      sourceHostName: 'shield',
      parentId: 'forearm_back',
    ),
  ];

  static final Map<String, GachaPoseAnchorDefinition> _anchorsById = {
    for (final anchor in anchors) anchor.id: anchor,
  };

  static final Map<String, String> _anchorIdsBySourceHost = {
    for (final anchor in anchors)
      if (anchor.sourceHostName != null) anchor.sourceHostName!: anchor.id,
  };

  static String? anchorIdForSourceHost(String sourceHostName) {
    return _anchorIdsBySourceHost[sourceHostName];
  }

  static Map<String, AffineMatrix> worldTransforms(
    ResolverTables tables,
    int pose,
  ) {
    final resolved = <String, AffineMatrix>{};
    for (final anchor in anchors) {
      final sourceHostName = anchor.sourceHostName;
      if (sourceHostName == null) {
        final parentId = anchor.parentId;
        resolved[anchor.id] = parentId == null
            ? const AffineMatrix.identity()
            : resolved[parentId]!;
        continue;
      }
      final placement = tables.posePlacementFor(
        pose: pose,
        hostName: sourceHostName,
      );
      if (placement == null) {
        throw StateError(
          'Missing source pose placement for $sourceHostName at pose $pose.',
        );
      }
      resolved[anchor.id] = placement.matrix;
    }
    return resolved;
  }

  static Map<String, AffineMatrix> localTransforms(
    ResolverTables tables,
    int pose,
  ) {
    final world = worldTransforms(tables, pose);
    return {
      for (final anchor in anchors)
        anchor.id: anchor.parentId == null
            ? world[anchor.id]!
            : world[anchor.parentId]!.inverse().multiply(world[anchor.id]!),
    };
  }

  static String? parentIdFor(String anchorId) {
    return _anchorsById[anchorId]?.parentId;
  }
}
