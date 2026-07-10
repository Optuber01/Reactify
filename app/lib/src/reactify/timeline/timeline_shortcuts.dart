import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class TogglePlaybackIntent extends Intent {
  const TogglePlaybackIntent();
}

class ShuttleIntent extends Intent {
  const ShuttleIntent(this.direction);

  final int direction;
}

class StopPlaybackIntent extends Intent {
  const StopPlaybackIntent();
}

class StepFrameIntent extends Intent {
  const StepFrameIntent(this.delta);

  final int delta;
}

class SplitSelectionIntent extends Intent {
  const SplitSelectionIntent();
}

class DeleteSelectionIntent extends Intent {
  const DeleteSelectionIntent({this.ripple = false});

  final bool ripple;
}

class CopySelectionIntent extends Intent {
  const CopySelectionIntent();
}

class PasteSelectionIntent extends Intent {
  const PasteSelectionIntent();
}

class UndoTimelineIntent extends Intent {
  const UndoTimelineIntent();
}

class RedoTimelineIntent extends Intent {
  const RedoTimelineIntent();
}

class ToggleSnappingIntent extends Intent {
  const ToggleSnappingIntent();
}

class AddTimelineMarkerIntent extends Intent {
  const AddTimelineMarkerIntent();
}

class ZoomTimelineIntent extends Intent {
  const ZoomTimelineIntent(this.delta);

  final double delta;
}

class NavigateEditIntent extends Intent {
  const NavigateEditIntent(this.direction);

  final int direction;
}

class TimelineToolIntent extends Intent {
  const TimelineToolIntent(this.tool);

  final TimelineTool tool;
}

enum TimelineTool { selection, blade }

Map<ShortcutActivator, Intent> resolveStyleTimelineShortcuts() {
  return const {
    SingleActivator(LogicalKeyboardKey.space): TogglePlaybackIntent(),
    SingleActivator(LogicalKeyboardKey.keyJ): ShuttleIntent(-1),
    SingleActivator(LogicalKeyboardKey.keyK): StopPlaybackIntent(),
    SingleActivator(LogicalKeyboardKey.keyL): ShuttleIntent(1),
    SingleActivator(LogicalKeyboardKey.arrowLeft): StepFrameIntent(-1),
    SingleActivator(LogicalKeyboardKey.arrowRight): StepFrameIntent(1),
    SingleActivator(LogicalKeyboardKey.keyB, control: true):
        SplitSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.keyB, meta: true):
        SplitSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.delete): DeleteSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.backspace, shift: true):
        DeleteSelectionIntent(ripple: true),
    SingleActivator(LogicalKeyboardKey.keyC, control: true):
        CopySelectionIntent(),
    SingleActivator(LogicalKeyboardKey.keyC, meta: true): CopySelectionIntent(),
    SingleActivator(LogicalKeyboardKey.keyV, control: true):
        PasteSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.keyV, meta: true):
        PasteSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.keyZ, control: true):
        UndoTimelineIntent(),
    SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoTimelineIntent(),
    SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        RedoTimelineIntent(),
    SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
        RedoTimelineIntent(),
    SingleActivator(LogicalKeyboardKey.keyY, control: true):
        RedoTimelineIntent(),
    SingleActivator(LogicalKeyboardKey.keyN): ToggleSnappingIntent(),
    SingleActivator(LogicalKeyboardKey.keyM): AddTimelineMarkerIntent(),
    SingleActivator(LogicalKeyboardKey.equal, control: true):
        ZoomTimelineIntent(0.2),
    SingleActivator(LogicalKeyboardKey.equal, meta: true): ZoomTimelineIntent(
      0.2,
    ),
    SingleActivator(LogicalKeyboardKey.minus, control: true):
        ZoomTimelineIntent(-0.2),
    SingleActivator(LogicalKeyboardKey.minus, meta: true): ZoomTimelineIntent(
      -0.2,
    ),
    SingleActivator(LogicalKeyboardKey.arrowUp): NavigateEditIntent(-1),
    SingleActivator(LogicalKeyboardKey.arrowDown): NavigateEditIntent(1),
    SingleActivator(LogicalKeyboardKey.keyA): TimelineToolIntent(
      TimelineTool.selection,
    ),
    SingleActivator(LogicalKeyboardKey.keyB): TimelineToolIntent(
      TimelineTool.blade,
    ),
  };
}

class TimelineShortcutCallbacks {
  const TimelineShortcutCallbacks({
    required this.togglePlayback,
    required this.shuttle,
    required this.stop,
    required this.stepFrame,
    required this.split,
    required this.delete,
    required this.copy,
    required this.paste,
    required this.undo,
    required this.redo,
    required this.toggleSnapping,
    required this.addMarker,
    required this.zoom,
    required this.navigateEdit,
    required this.selectTool,
  });

  final VoidCallback togglePlayback;
  final ValueChanged<int> shuttle;
  final VoidCallback stop;
  final ValueChanged<int> stepFrame;
  final VoidCallback split;
  final ValueChanged<bool> delete;
  final VoidCallback copy;
  final VoidCallback paste;
  final VoidCallback undo;
  final VoidCallback redo;
  final VoidCallback toggleSnapping;
  final VoidCallback addMarker;
  final ValueChanged<double> zoom;
  final ValueChanged<int> navigateEdit;
  final ValueChanged<TimelineTool> selectTool;
}

class TimelineShortcutActions extends StatelessWidget {
  const TimelineShortcutActions({
    super.key,
    required this.callbacks,
    required this.child,
  });

  final TimelineShortcutCallbacks callbacks;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: resolveStyleTimelineShortcuts(),
      child: Actions(
        actions: {
          TogglePlaybackIntent: CallbackAction<TogglePlaybackIntent>(
            onInvoke: (_) => callbacks.togglePlayback(),
          ),
          ShuttleIntent: CallbackAction<ShuttleIntent>(
            onInvoke: (intent) => callbacks.shuttle(intent.direction),
          ),
          StopPlaybackIntent: CallbackAction<StopPlaybackIntent>(
            onInvoke: (_) => callbacks.stop(),
          ),
          StepFrameIntent: CallbackAction<StepFrameIntent>(
            onInvoke: (intent) => callbacks.stepFrame(intent.delta),
          ),
          SplitSelectionIntent: CallbackAction<SplitSelectionIntent>(
            onInvoke: (_) => callbacks.split(),
          ),
          DeleteSelectionIntent: CallbackAction<DeleteSelectionIntent>(
            onInvoke: (intent) => callbacks.delete(intent.ripple),
          ),
          CopySelectionIntent: CallbackAction<CopySelectionIntent>(
            onInvoke: (_) => callbacks.copy(),
          ),
          PasteSelectionIntent: CallbackAction<PasteSelectionIntent>(
            onInvoke: (_) => callbacks.paste(),
          ),
          UndoTimelineIntent: CallbackAction<UndoTimelineIntent>(
            onInvoke: (_) => callbacks.undo(),
          ),
          RedoTimelineIntent: CallbackAction<RedoTimelineIntent>(
            onInvoke: (_) => callbacks.redo(),
          ),
          ToggleSnappingIntent: CallbackAction<ToggleSnappingIntent>(
            onInvoke: (_) => callbacks.toggleSnapping(),
          ),
          AddTimelineMarkerIntent: CallbackAction<AddTimelineMarkerIntent>(
            onInvoke: (_) => callbacks.addMarker(),
          ),
          ZoomTimelineIntent: CallbackAction<ZoomTimelineIntent>(
            onInvoke: (intent) => callbacks.zoom(intent.delta),
          ),
          NavigateEditIntent: CallbackAction<NavigateEditIntent>(
            onInvoke: (intent) => callbacks.navigateEdit(intent.direction),
          ),
          TimelineToolIntent: CallbackAction<TimelineToolIntent>(
            onInvoke: (intent) => callbacks.selectTool(intent.tool),
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
