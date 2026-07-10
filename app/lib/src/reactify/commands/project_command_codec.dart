import 'dart:convert';

import '../project/project.dart';
import 'project_command.dart';
import 'project_entity_commands.dart';
import 'reaction_commands.dart';
import 'timeline_commands.dart';

class ProjectCommandCodec {
  const ProjectCommandCodec();

  ProjectCommand decode(Map<String, Object?> json) {
    final type = jsonString(json, 'type');
    return switch (type) {
      'batch' => ProjectCommandBatch(
        label: jsonString(json, 'label'),
        commands: [
          for (final value in jsonList(json['commands']))
            decode(jsonMap(value)),
        ],
      ),
      'entity.upsert' => UpsertProjectEntityCommand.fromJson(json),
      'entity.remove' => RemoveProjectEntityCommand.fromJson(json),
      'reaction.character.update' => UpdateReactionCharacterCommand.fromJson(
        json,
      ),
      'track.add' => AddTrackCommand.fromJson(json),
      'track.remove' => RemoveTrackCommand.fromJson(json),
      'track.reorder' => ReorderTracksCommand.fromJson(json),
      'clip.insert' => InsertClipCommand.fromJson(json),
      'clip.delete' => DeleteClipCommand.fromJson(json),
      'clip.move' => MoveClipCommand.fromJson(json),
      'clip.trim' => TrimClipCommand.fromJson(json),
      'clip.split' => SplitClipCommand.fromJson(json),
      'clip.audio.update' => UpdateAudioControlsCommand.fromJson(json),
      'marker.add' => AddMarkerCommand.fromJson(json),
      'marker.remove' => RemoveMarkerCommand.fromJson(json),
      'timeline.duplicate' => DuplicateTimelineCommand.fromJson(json),
      _ => throw FormatException('Unknown project command type $type.'),
    };
  }

  ProjectCommand decodeString(String source) {
    final decoded = jsonDecode(source);
    return decode(jsonMap(decoded));
  }

  Map<String, Object?> encode(ProjectCommand command) {
    return canonicalJsonMap(command.toJson());
  }

  String encodeString(ProjectCommand command, {bool pretty = false}) {
    final value = encode(command);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return jsonEncode(value);
  }
}
