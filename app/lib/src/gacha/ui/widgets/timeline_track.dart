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
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.01),
              ],
            ),
          ),
          child: Column(
            children: [
              // Controller row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          size: 32,
                          color: const Color(0xFF64B5F6),
                        ),
                        onPressed: onPlaybackToggle,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${currentTime.toStringAsFixed(2)}s / ${maxDuration.toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF64B5F6).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFF90CAF9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF42A5F5)),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Add Keyframe', style: TextStyle(fontFamily: 'Outfit')),
                    onPressed: onAddKeyframe,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tracks
              _buildTrackRow('Character', context, keyframes),
              const SizedBox(height: 8),
              _buildTrackRow('Camera', context, []),
              const SizedBox(height: 8),
              _buildTrackRow('Audio', context, []),
            ],
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
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Stack(
              children: [
                // Render keyframe nodes
                for (final node in nodes)
                  Positioned(
                    left: (node / maxDuration) * (MediaQuery.of(context).size.width - 240),
                    top: 10,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFF64B5F6),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0xFF42A5F5), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),

                // Scrubbing slider overlay
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: const Color(0xFF64B5F6),
                      overlayColor: const Color(0xFF42A5F5).withValues(alpha: 0.2),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
