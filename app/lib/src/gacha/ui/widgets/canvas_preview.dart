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
    const borderRadius = BorderRadius.all(Radius.circular(28));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07090C).withValues(alpha: 0.6),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
            blurRadius: 50,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: CustomPaint(
          foregroundPainter: _CanvasGlassBorderPainter(
            borderRadius: borderRadius,
            strokeWidth: 1.5,
          ),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF161B22), Color(0xFF0F1216)],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: GameWidget(game: widget.game),
                  ),
                ),
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
                Positioned(
                  top: 16,
                  right: 16,
                  child: _GlassToolbar(
                    drawingMode: _drawingMode,
                    onToggleDrawing: () {
                      setState(() {
                        _drawingMode = !_drawingMode;
                        if (!_drawingMode) {
                          _clearCanvas();
                        }
                      });
                    },
                    onClear: _clearCanvas,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassToolbar extends StatelessWidget {
  const _GlassToolbar({
    required this.drawingMode,
    required this.onToggleDrawing,
    required this.onClear,
  });

  final bool drawingMode;
  final VoidCallback onToggleDrawing;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(16));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07090C).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: CustomPaint(
            foregroundPainter: _CanvasGlassBorderPainter(
              borderRadius: borderRadius,
              strokeWidth: 1.0,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.4),
                    const Color(0xFF0F172A).withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SpringToolbarButton(
                    tooltip: 'Drawing Canvas',
                    icon: Icon(
                      Icons.brush,
                      color: drawingMode ? const Color(0xFF00F5FF) : Colors.white.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    onPressed: onToggleDrawing,
                  ),
                  if (drawingMode) ...[
                    const SizedBox(width: 4),
                    _SpringToolbarButton(
                      tooltip: 'Clear Custom Strokes',
                      icon: Icon(Icons.delete_sweep, color: Colors.white.withValues(alpha: 0.7), size: 20),
                      onPressed: onClear,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpringToolbarButton extends StatefulWidget {
  const _SpringToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback onPressed;

  @override
  State<_SpringToolbarButton> createState() => _SpringToolbarButtonState();
}

class _SpringToolbarButtonState extends State<_SpringToolbarButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.8),
        onTapUp: (_) => setState(() => _scale = 1.0),
        onTapCancel: () => setState(() => _scale = 1.0),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.decelerate,
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: Center(child: widget.icon),
          ),
        ),
      ),
    );
  }
}

class _CanvasGlassBorderPainter extends CustomPainter {
  const _CanvasGlassBorderPainter({
    required this.borderRadius,
    required this.strokeWidth,
  });

  final BorderRadius borderRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.14),
        ],
        stops: const [0.0, 0.45, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _CanvasGlassBorderPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.strokeWidth != strokeWidth;
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
      ..color = const Color(0xFF00F5FF)
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
