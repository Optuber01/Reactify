import 'dart:ui';
import 'package:flutter/material.dart';

class ColorWheelPicker extends StatelessWidget {
  const ColorWheelPicker({
    super.key,
    required this.field,
    required this.label,
    required this.currentColor,
    required this.onColorSelected,
  });

  final String field;
  final String label;
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(20));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07090C).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CustomPaint(
            foregroundPainter: _GlassBorderPainter(
              borderRadius: borderRadius,
              strokeWidth: 1.2,
            ),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.45),
                    const Color(0xFF0F172A).withValues(alpha: 0.65),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: currentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: currentColor.withValues(alpha: 0.4),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              field,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w500,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 8,
                      itemBuilder: (context, index) {
                        final double hue = (index * 45.0) % 360.0;
                        final color = HSLColor.fromAHSL(1.0, hue, 0.8, 0.55).toColor();
                        final isSelected = currentColor.toARGB32() == color.toARGB32();

                        return _CuratedColorItem(
                          color: color,
                          isSelected: isSelected,
                          onTap: () => onColorSelected(color),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CuratedColorItem extends StatefulWidget {
  const _CuratedColorItem({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_CuratedColorItem> createState() => _CuratedColorItemState();
}

class _CuratedColorItemState extends State<_CuratedColorItem> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.8),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.decelerate,
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isSelected ? Colors.white : Colors.white.withValues(alpha: 0.1),
              width: widget.isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              if (widget.isSelected)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassBorderPainter extends CustomPainter {
  const _GlassBorderPainter({
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
          Colors.white.withValues(alpha: 0.26),
          Colors.white.withValues(alpha: 0.04),
          Colors.black.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.14),
        ],
        stops: const [0.0, 0.45, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassBorderPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.strokeWidth != strokeWidth;
}
