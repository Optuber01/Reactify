import 'package:flutter/material.dart';

import '../code/gacha_character_state.dart';
import '../code/gacha_field_schema.dart';
import '../render/render_part.dart';
import 'editor_helpers.dart';

class DebugRenderPanel extends StatelessWidget {
  const DebugRenderPanel({
    super.key,
    required this.fixtureLabel,
    required this.fixtureTags,
    required this.schema,
    required this.baselineState,
    required this.state,
    required this.scene,
    required this.selectedField,
  });

  final String fixtureLabel;
  final List<String> fixtureTags;
  final GachaFieldSchema schema;
  final GachaCharacterState baselineState;
  final GachaCharacterState state;
  final ResolvedScene scene;
  final String? selectedField;

  @override
  Widget build(BuildContext context) {
    final changes = state.diff(baselineState, schema);
    final familyCounts = resolvedFamilyCounts(scene);
    final visibleFamilies = familyCounts.keys.toList()..sort();
    final expectedFamilies = expectedResolvedFamiliesForState(state).toList()
      ..sort();
    final missingFamilies = expectedFamilies
        .where((family) => !familyCounts.containsKey(family))
        .toList(growable: false);
    final bounds = scene.worldBounds;
    final selectedDefinition = selectedField == null
        ? null
        : schema.byName[selectedField!];
    final selectedValue = selectedField == null
        ? null
        : state.rawValue(schema, selectedField!, fallback: '');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB9C2CA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Debug / Renderer Feedback',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _kv(context, 'Fixture / Code', fixtureLabel),
          _kv(
            context,
            'Fixture tags',
            fixtureTags.isEmpty ? 'none' : fixtureTags.join(', '),
          ),
          _kv(context, 'Resolved part count', '${scene.parts.length}'),
          _kv(context, 'Bounds', _formatBounds(bounds)),
          _kv(context, 'Changed fields', '${changes.length}'),
          _kv(
            context,
            'Visible families',
            visibleFamilies.isEmpty ? 'none' : visibleFamilies.join(', '),
          ),
          _kv(
            context,
            'Missing / unresolved selected families',
            missingFamilies.isEmpty ? 'none' : missingFamilies.join(', '),
            valueColor: missingFamilies.isEmpty
                ? null
                : const Color(0xFF8A2B2B),
          ),
          if (selectedDefinition != null && selectedValue != null)
            _kv(
              context,
              'Selected field',
              '[${selectedDefinition.index}] ${selectedDefinition.field} = $selectedValue',
            ),
          if (selectedField != null)
            _kv(
              context,
              'Selected field support',
              isPreviewBackedField(selectedField!)
                  ? 'preview-backed'
                  : 'state-only / export-only',
              valueColor: isPreviewBackedField(selectedField!)
                  ? const Color(0xFF2B5A39)
                  : const Color(0xFF8A5A2B),
            ),
          if (scene.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Warnings', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final warning in scene.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  warning,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A2B2B),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            'Per-family part count',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          SelectableText(
            familyCounts.isEmpty
                ? 'No render parts resolved.'
                : visibleFamilies
                      .map(
                        (family) =>
                            '$family -> ${familyCounts[family]} part(s)',
                      )
                      .join('\n'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'Consolas',
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text('Changed fields', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText(
            changes.isEmpty
                ? 'No fields changed from the imported baseline.'
                : _formatChanges(changes),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'Consolas',
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text('Resolved parts', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText(
            scene.parts.isEmpty
                ? 'No render parts resolved.'
                : _formatParts(scene.parts),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'Consolas',
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: valueColor),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBounds(Rect bounds) {
    return 'L=${bounds.left.toStringAsFixed(1)} '
        'T=${bounds.top.toStringAsFixed(1)} '
        'R=${bounds.right.toStringAsFixed(1)} '
        'B=${bounds.bottom.toStringAsFixed(1)}';
  }

  static String _formatChanges(List<GachaFieldChange> changes) {
    final buffer = StringBuffer();
    for (final change in changes) {
      buffer.writeln(
        '[${change.index.toString().padLeft(3, '0')}] '
        '${change.field}: ${change.previousRawValue} -> ${change.rawValue}',
      );
    }
    return buffer.toString().trimRight();
  }

  static String _formatParts(List<ResolvedRenderPart> parts) {
    final buffer = StringBuffer();
    for (final part in parts) {
      final tint = part.tintColor == null
          ? 'none'
          : '#${(part.tintColor!.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      buffer.writeln(
        '[${part.globalDepth}] '
        '${part.catalogPart.family}#${part.catalogPart.chooserFrame} '
        '${part.catalogPart.partRole} '
        'tint=$tint '
        'host=${part.catalogPart.hostScope}:${part.catalogPart.hostName} '
        'asset=${part.catalogPart.appAssetPath}',
      );
    }
    return buffer.toString().trimRight();
  }
}
