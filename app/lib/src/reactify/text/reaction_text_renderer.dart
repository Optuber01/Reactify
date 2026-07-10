import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'reaction_text.dart';

class ReactionTextRenderLine {
  const ReactionTextRenderLine({
    required this.line,
    required this.style,
    required this.offset,
    required this.size,
  });

  final ReactionDialogueLine line;
  final ReactionTextStyle style;
  final Offset offset;
  final Size size;
}

class ReactionTextLayout {
  const ReactionTextLayout({required this.size, required this.lines});

  final Size size;
  final List<ReactionTextRenderLine> lines;
}

typedef ReactionSpeakerStyleResolver =
    ReactionTextStyle? Function(String? speakerId);

class ReactionTextBlockRenderer {
  const ReactionTextBlockRenderer();

  ReactionTextLayout layout({
    required List<ReactionDialogueLine> lines,
    required double maxWidth,
    ReactionTextStyle applicationStyle = ReactionTextStyle.defaults,
    ReactionTextStyle? projectStyle,
    ReactionTextStyle? timelineStyle,
    ReactionSpeakerStyleResolver? speakerStyle,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final resolved = <({ReactionDialogueLine line, ReactionTextStyle style})>[];
    for (final line in lines) {
      resolved.add((
        line: line,
        style: resolveReactionLineStyle(
          application: applicationStyle,
          projectPreset: projectStyle,
          timelineOverride: timelineStyle,
          speakerRule: speakerStyle?.call(line.speakerId),
          lineOverride: line.styleOverride,
        ),
      ));
    }

    final measured =
        <({ReactionDialogueLine line, ReactionTextStyle style, Size size})>[];
    var totalHeight = 0.0;
    for (final item in resolved) {
      final painter = _painter(
        item.line.text,
        item.style,
        textDirection,
        foreground: _fillPaint(item.style),
      )..layout(maxWidth: maxWidth);
      final spacing =
          (item.style.fontSize ?? 42) *
          ((item.style.lineSpacing ?? 1.1) - 1).clamp(0, 4);
      final size = Size(painter.width, painter.height + spacing);
      measured.add((line: item.line, style: item.style, size: size));
      totalHeight += size.height;
    }

    final placed = <ReactionTextRenderLine>[];
    var y = 0.0;
    for (final item in measured) {
      final x = switch (item.style.alignment ?? ReactionTextAlign.center) {
        ReactionTextAlign.left => 0.0,
        ReactionTextAlign.center => (maxWidth - item.size.width) / 2,
        ReactionTextAlign.right => maxWidth - item.size.width,
      };
      placed.add(
        ReactionTextRenderLine(
          line: item.line,
          style: item.style,
          offset: Offset(x, y),
          size: item.size,
        ),
      );
      y += item.size.height;
    }
    return ReactionTextLayout(size: Size(maxWidth, totalHeight), lines: placed);
  }

  void paint(
    Canvas canvas,
    ReactionTextLayout layout, {
    Offset offset = Offset.zero,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    for (final entry in layout.lines) {
      final position = offset + entry.offset;
      final glowSize = entry.style.glowSize ?? 0;
      final glowColor = Color(entry.style.glowColor ?? 0x00000000);
      if (glowSize > 0 && glowColor.a > 0) {
        final glow = _painter(
          entry.line.text,
          entry.style,
          textDirection,
          foreground: Paint()..color = glowColor,
          shadows: [Shadow(color: glowColor, blurRadius: glowSize)],
        )..layout(maxWidth: layout.size.width);
        glow.paint(canvas, position);
      }

      final outlineWidth = entry.style.outlineWidth ?? 0;
      final outlineColor = Color(entry.style.outlineColor ?? 0x00000000);
      if (outlineWidth > 0 && outlineColor.a > 0) {
        final outline = _painter(
          entry.line.text,
          entry.style,
          textDirection,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = outlineWidth * 2
            ..color = outlineColor,
          shadows: _shadows(entry.style),
        )..layout(maxWidth: layout.size.width);
        outline.paint(canvas, position);
      }

      final fill = _painter(
        entry.line.text,
        entry.style,
        textDirection,
        foreground: _fillPaint(entry.style),
        shadows: _shadows(entry.style),
      )..layout(maxWidth: layout.size.width);
      fill.paint(canvas, position);
    }
  }

  Future<ui.Image> renderImage({
    required ReactionTextLayout layout,
    double pixelRatio = 1,
    Color background = const Color(0x00000000),
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final width = (layout.size.width * pixelRatio).ceil().clamp(1, 16384);
    final height = (layout.size.height * pixelRatio).ceil().clamp(1, 16384);
    canvas.scale(pixelRatio);
    if (background.a > 0) {
      canvas.drawRect(Offset.zero & layout.size, Paint()..color = background);
    }
    paint(canvas, layout, textDirection: textDirection);
    return recorder.endRecording().toImage(width, height);
  }

  TextPainter _painter(
    String value,
    ReactionTextStyle style,
    TextDirection textDirection, {
    required Paint foreground,
    List<Shadow> shadows = const [],
  }) {
    final capitalization =
        style.capitalization ?? ReactionTextCapitalization.preserve;
    return TextPainter(
      text: TextSpan(
        text: applyReactionCapitalization(value, capitalization),
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: _fontWeight(style.fontWeight),
          fontStyle: style.italic == true ? FontStyle.italic : FontStyle.normal,
          letterSpacing: style.tracking,
          height: 1,
          foreground: foreground,
          shadows: shadows,
        ),
      ),
      textAlign: _textAlign(style.alignment),
      textDirection: textDirection,
    );
  }

  Paint _fillPaint(ReactionTextStyle style) {
    return Paint()..color = Color(style.fillColor ?? 0xffffffff);
  }

  List<Shadow> _shadows(ReactionTextStyle style) {
    final color = Color(style.shadowColor ?? 0x00000000);
    final opacity = (style.shadowOpacity ?? 0).clamp(0, 1);
    if (opacity <= 0 || color.a == 0) return const [];
    return [
      Shadow(
        color: color.withValues(alpha: color.a * opacity),
        offset: Offset(style.shadowOffsetX ?? 0, style.shadowOffsetY ?? 0),
        blurRadius: style.shadowSoftness ?? 0,
      ),
    ];
  }

  TextAlign _textAlign(ReactionTextAlign? alignment) {
    return switch (alignment ?? ReactionTextAlign.center) {
      ReactionTextAlign.left => TextAlign.left,
      ReactionTextAlign.center => TextAlign.center,
      ReactionTextAlign.right => TextAlign.right,
    };
  }

  FontWeight _fontWeight(int? weight) {
    final normalized = ((weight ?? 700) / 100).round().clamp(1, 9);
    return FontWeight.values[normalized - 1];
  }
}

class ReactionTextPreview extends StatelessWidget {
  const ReactionTextPreview({
    required this.layout,
    this.background = const Color(0x00000000),
    super.key,
  });

  final ReactionTextLayout layout;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: layout.size,
      child: CustomPaint(
        painter: _ReactionTextPainter(
          renderer: const ReactionTextBlockRenderer(),
          layout: layout,
          background: background,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _ReactionTextPainter extends CustomPainter {
  const _ReactionTextPainter({
    required this.renderer,
    required this.layout,
    required this.background,
    required this.textDirection,
  });

  final ReactionTextBlockRenderer renderer;
  final ReactionTextLayout layout;
  final Color background;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (background.a > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background);
    }
    renderer.paint(canvas, layout, textDirection: textDirection);
  }

  @override
  bool shouldRepaint(covariant _ReactionTextPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.background != background ||
        oldDelegate.textDirection != textDirection;
  }
}
