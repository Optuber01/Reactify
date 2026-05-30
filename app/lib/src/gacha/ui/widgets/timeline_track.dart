import 'dart:ui';
import 'package:flutter/material.dart';

class TimelineTrack extends StatelessWidget {
  const TimelineTrack({
    super.key,
    required this.currentTime,
    required this.maxDuration,
    required this.isPlaying,
    required this.onTimeChanged,
    required this.onPlaybackToggle,
    required this.keyframes,
    required this.onAddKeyframe,
  });

  final double currentTime;
  final double maxDuration;
  final bool isPlaying;
  final ValueChanged<double> onTimeChanged;
  final VoidCallback onPlaybackToggle;
  final List<double> keyframes;
  final VoidCallback onAddKeyframe;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07090C).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.15),
            blurRadius: 40,
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.4),
                    const Color(0xFF0F172A).withValues(alpha: 0.65),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _SpringIconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 34,
                              color: const Color(0xFF00F5FF),
                            ),
                            onPressed: onPlaybackToggle,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${currentTime.toStringAsFixed(2)}s / ${maxDuration.toStringAsFixed(1)}s',
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                      _SpringAddKeyframeButton(onPressed: onAddKeyframe),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildTrackRow('Character', context, keyframes),
                  const SizedBox(height: 10),
                  _buildTrackRow('Camera', context, []),
                  const SizedBox(height: 10),
                  _buildTrackRow('Audio', context, []),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackRow(String label, BuildContext context, List<double> nodes) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Outfit',
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF090D16).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: List.generate(20, (index) {
                      return Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 1,
                            height: index % 5 == 0 ? 10 : 5,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                for (final node in nodes)
                  Positioned(
                    left: (node / maxDuration) * (MediaQuery.of(context).size.width - 240),
                    top: 11,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.0),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xFF00F5FF),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: const Color(0xFF00F5FF).withValues(alpha: 0.35),
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: const Color(0xFF00F5FF),
                      overlayColor: const Color(0xFF00F5FF).withValues(alpha: 0.15),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, pressedElevation: 10),
                    ),
                    child: Slider(
                      value: currentTime.clamp(0.0, maxDuration),
                      max: maxDuration,
                      onChanged: onTimeChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SpringIconButton extends StatefulWidget {
  const _SpringIconButton({
    required this.icon,
    required this.onPressed,
  });

  final Widget icon;
  final VoidCallback onPressed;

  @override
  State<_SpringIconButton> createState() => _SpringIconButtonState();
}

class _SpringIconButtonState extends State<_SpringIconButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.8),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.decelerate,
        child: widget.icon,
      ),
    );
  }
}

class _SpringAddKeyframeButton extends StatefulWidget {
  const _SpringAddKeyframeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_SpringAddKeyframeButton> createState() => _SpringAddKeyframeButtonState();
}

class _SpringAddKeyframeButtonState extends State<_SpringAddKeyframeButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.decelerate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00F5FF).withValues(alpha: 0.15),
                const Color(0xFF1E3A8A).withValues(alpha: 0.25),
              ],
            ),
            border: Border.all(color: const Color(0xFF00F5FF).withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F5FF).withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF00F5FF)),
              SizedBox(width: 6),
              Text(
                'Add Keyframe',
                style: TextStyle(
                  color: Color(0xFF00F5FF),
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
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
          Colors.black.withValues(alpha: 0.2),
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
