import 'dart:convert';
import 'dart:io';

import 'package:reactify_gacha/src/reactify/automation/automation.dart';
import 'package:reactify_gacha/src/reactify/commands/commands.dart';
import 'package:reactify_gacha/src/reactify/io/io.dart';
import 'package:reactify_gacha/src/reactify/project/project.dart';

Future<void> main(List<String> arguments) async {
  try {
    final response = await _run(arguments);
    stdout.writeln(jsonEncode(canonicalJsonMap(response)));
  } on ProjectAutomationException catch (error) {
    _fail(
      AutomationErrorResponse(
        code: error.code,
        message: error.message,
        details: error.details,
      ),
    );
  } on ProjectRepositoryException catch (error) {
    _fail(
      AutomationErrorResponse(
        code: 'repository.error',
        message: error.message,
        details: {
          if (error.validationIssues.isNotEmpty)
            'issues': [
              for (final issue in error.validationIssues)
                {
                  'code': issue.code,
                  'message': issue.message,
                  'path': issue.path,
                  'severity': issue.severity.name,
                },
            ],
        },
      ),
    );
  } on ProjectCommandException catch (error) {
    _fail(
      AutomationErrorResponse(
        code: 'command.invalid',
        message: error.message,
        details: {
          if (error.issues.isNotEmpty)
            'issues': [
              for (final issue in error.issues)
                {
                  'code': issue.code,
                  'message': issue.message,
                  'path': issue.path,
                  'severity': issue.severity.name,
                },
            ],
        },
      ),
    );
  } on FormatException catch (error) {
    _fail(
      AutomationErrorResponse(code: 'protocol.invalid', message: error.message),
    );
  } on FileSystemException catch (error) {
    _fail(AutomationErrorResponse(code: 'io.error', message: error.message));
  } catch (error) {
    _fail(
      AutomationErrorResponse(code: 'automation.failed', message: '$error'),
    );
  }
}

Future<Map<String, Object?>> _run(List<String> arguments) async {
  if (arguments.length < 2) {
    throw const ProjectAutomationException(
      'arguments.invalid',
      'Usage: reactify_project <action> <project> [command-or-draft-file].',
    );
  }
  final action = arguments[0];
  final projectLocation = arguments[1];
  final service = ProjectAutomationService();
  switch (action) {
    case 'inspect':
      _requireLength(arguments, 2, 3);
      return (await service.inspect(
        projectLocation,
        draftLocation: arguments.length == 3 ? arguments[2] : null,
      )).toJson();
    case 'validate':
      _requireLength(arguments, 2, 3);
      return (await service.validate(
        projectLocation,
        draftLocation: arguments.length == 3 ? arguments[2] : null,
      )).toJson();
    case 'apply':
      _requireLength(arguments, 3, 3);
      final envelope = await _readEnvelope(arguments[2]);
      return (await service.apply(projectLocation, envelope)).toJson();
    case 'draft':
      _requireLength(arguments, 3, 4);
      final envelope = await _readEnvelope(arguments[2]);
      return (await service.createDraft(
        projectLocation,
        envelope,
        draftLocation: arguments.length == 4 ? arguments[3] : null,
      )).toJson();
    case 'commit-draft':
      _requireLength(arguments, 2, 3);
      return (await service.commitDraft(
        projectLocation,
        draftLocation: arguments.length == 3 ? arguments[2] : null,
      )).toJson();
    case 'rollback-draft':
      _requireLength(arguments, 2, 3);
      return (await service.rollbackDraft(
        projectLocation,
        draftLocation: arguments.length == 3 ? arguments[2] : null,
      )).toJson();
    default:
      throw ProjectAutomationException(
        'action.unknown',
        'Unknown action $action.',
      );
  }
}

Future<ProjectCommandFileEnvelope> _readEnvelope(String location) async {
  final source = await File(location).readAsString();
  return ProjectCommandFileEnvelope.fromJson(jsonMap(jsonDecode(source)));
}

void _requireLength(List<String> arguments, int minimum, int maximum) {
  if (arguments.length < minimum || arguments.length > maximum) {
    throw const ProjectAutomationException(
      'arguments.invalid',
      'Invalid argument count for action.',
    );
  }
}

void _fail(AutomationErrorResponse response) {
  stdout.writeln(jsonEncode(response.toJson()));
  exitCode = 2;
}
