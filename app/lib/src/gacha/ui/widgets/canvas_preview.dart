import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../../render/gacha_game_canvas.dart';
import '../../render/render_part.dart';

class CanvasPreview extends StatefulWidget {
  const CanvasPreview({
    super.key,
    required this.scene,
    required this.game,
    required this.onStrokesDrawn,
  });

  final ResolvedScene scene;
  final GachaGameCanvas game;
  final ValueChanged<List<Offset>> onStrokesDrawn;

  @override
  State<CanvasPreview> createState() => _CanvasPreviewState();
}

class _CanvasPreviewState extends State<CanvasPreview> {
  final List<Offset> _currentStroke = [];
  final List<List<Offset>> _allStrokes = [];
  bool _drawingMode = false;

  void _clearCanvas() {
    setState(() {
      _currentStroke.clear();
      _allStrokes.clear();
    });
  }

  // Ramer-Douglas-Peucker algorithm for vector stroke control point simplification
  List<Offset> _simplifyPoints(List<Offset> points, double epsilon) {
    if (points.length < 3) return points;

    int dmaxIndex = 0;
    double dmax = 0.0;

    for (int i = 1; i < points.length - 1; i++) {
      double d = _perpendicularDistance(points[i], points[0], points[points.length - 1]);
      if (d > dmax) {
        dmaxIndex = i;
        dmax = d;
      }
    }

    if (dmax > epsilon) {
      final results1 = _simplifyPoints(points.sublist(0, dmaxIndex + 1), epsilon);
      final results2 = _simplifyPoints(points.sublist(dmaxIndex), epsilon);
      return results1.sublist(0, results1.length - 1) + results2;
    } else {
      return [points[0], points[points.length - 1]];
    }
  }

  double _perpendicularDistance(Offset p, Offset lineStart, Offset lineEnd) {
    double dx = lineEnd.dx - lineStart.dx;
    double dy = lineEnd.dy - lineStart.dy;

    if (dx == 0.0 && dy == 0.0) {
      return (p - lineStart).distance;
    }

    double t = ((p.dx - lineStart.dx) * dx + (p.dy - lineStart.dy) * dy) / (dx * dx + dy * dy);
    t = t.clamp(0.0, 1.0);

    Offset projection = lineStart + Offset(dx * t, dy * t);
    return (p - projection).distance;
  }

  @override
  Widget build(BuildContext context) {
    widget.game.scene = widget.scene;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E262F), Color(0xFF15191E), Color(0xFF0F1216)],
        ),
        border: Border.all(color: const Color(0xFF333F4D)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Flame view layer
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: GameWidget(game: widget.game),
            ),
          ),

          // Gesture drawing layer
          if (_drawingMode)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _currentStroke.add(details.localPosition);
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _currentStroke.add(details.localPosition);
                  });
                },
                onPanEnd: (details) {
                  if (_currentStroke.isNotEmpty) {
                    final simplified = _simplifyPoints(_currentStroke, 1.5);
                    setState(() {
                      _allStrokes.add(List.from(simplified));
                      _currentStroke.clear();
                    });
                    widget.onStrokesDrawn(simplified);
                  }
                },
                child: CustomPaint(
                  painter: _VectorDrawingPainter(
                    currentStroke: _currentStroke,
                    allStrokes: _allStrokes,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),

          // Glassmorphic toolbar for drawing controls
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Drawing Canvas',
                    icon: Icon(
                      Icons.brush,
                      color: _drawingMode ? const Color(0xFF64B5F6) : Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _drawingMode = !_drawingMode;
                        if (!_drawingMode) {
                          _clearCanvas();
                        }
                      });
                    },
                  ),
                  if (_drawingMode) ...[
                    IconButton(
                      tooltip: 'Clear Custom Strokes',
                      icon: const Icon(Icons.delete_sweep, color: Colors.white70),
                      onPressed: _clearCanvas,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VectorDrawingPainter extends CustomPainter {
  const _VectorDrawingPainter({
    required this.currentStroke,
    required this.allStrokes,
  });

  final List<Offset> currentStroke;
  final List<List<Offset>> allStrokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF64B5F6)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in allStrokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.length >= 2) {
      final path = Path()..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (var i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorDrawingPainter oldDelegate) {
    return oldDelegate.currentStroke != currentStroke ||
        oldDelegate.allStrokes != allStrokes;
  }
}
