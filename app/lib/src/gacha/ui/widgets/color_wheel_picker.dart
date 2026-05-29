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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.01),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: currentColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          field,
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Render curated color palette based on HSL color shifts
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 8,
                  itemBuilder: (context, index) {
                    final double hue = (index * 45.0) % 360.0;
                    final color = HSLColor.fromAHSL(1.0, hue, 0.75, 0.55).toColor();
                    final isSelected = currentColor.toARGB32() == color.toARGB32();

                    return GestureDetector(
                      onTap: () => onColorSelected(color),
                      child: Container(
                        width: 32,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
