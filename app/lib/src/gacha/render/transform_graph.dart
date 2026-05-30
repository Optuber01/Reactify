import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

class AffineMatrix {
  const AffineMatrix({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.tx,
    required this.ty,
  });

  const AffineMatrix.identity() : a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  factory AffineMatrix.translation(double x, double y) {
    return AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y);
  }

  factory AffineMatrix.scale(double x, double y) {
    return AffineMatrix(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0);
  }

  factory AffineMatrix.rotationDegrees(double degrees) {
    final radians = degrees * math.pi / 180;
    final cosValue = math.cos(radians);
    final sinValue = math.sin(radians);
    return AffineMatrix(
      a: cosValue,
      b: sinValue,
      c: -sinValue,
      d: cosValue,
      tx: 0,
      ty: 0,
    );
  }

  factory AffineMatrix.fromComponents({
    required double scaleX,
    required double scaleY,
    required double rotateSkew0,
    required double rotateSkew1,
    required double translateX,
    required double translateY,
  }) {
    return AffineMatrix(
      a: scaleX,
      b: rotateSkew1,
      c: rotateSkew0,
      d: scaleY,
      tx: translateX,
      ty: translateY,
    );
  }

  AffineMatrix multiply(AffineMatrix child) {
    return AffineMatrix(
      a: a * child.a + c * child.b,
      b: b * child.a + d * child.b,
      c: a * child.c + c * child.d,
      d: b * child.c + d * child.d,
      tx: a * child.tx + c * child.ty + tx,
      ty: b * child.tx + d * child.ty + ty,
    );
  }

  AffineMatrix inverse() {
    final determinant = a * d - b * c;
    if (determinant == 0) {
      throw StateError('Cannot invert a singular affine matrix.');
    }
    final invDeterminant = 1 / determinant;
    final inverseA = d * invDeterminant;
    final inverseB = -b * invDeterminant;
    final inverseC = -c * invDeterminant;
    final inverseD = a * invDeterminant;
    return AffineMatrix(
      a: inverseA,
      b: inverseB,
      c: inverseC,
      d: inverseD,
      tx: -(inverseA * tx + inverseC * ty),
      ty: -(inverseB * tx + inverseD * ty),
    );
  }

  Offset transformPoint(Offset point) {
    return Offset(
      a * point.dx + c * point.dy + tx,
      b * point.dx + d * point.dy + ty,
    );
  }

  Rect transformRect(Rect rect) {
    final tL = transformPoint(rect.topLeft);
    final tR = transformPoint(rect.topRight);
    final bL = transformPoint(rect.bottomLeft);
    final bR = transformPoint(rect.bottomRight);

    var minX = tL.dx;
    var maxX = tL.dx;
    var minY = tL.dy;
    var maxY = tL.dy;

    if (tR.dx < minX) minX = tR.dx;
    if (tR.dx > maxX) maxX = tR.dx;
    if (tR.dy < minY) minY = tR.dy;
    if (tR.dy > maxY) maxY = tR.dy;

    if (bL.dx < minX) minX = bL.dx;
    if (bL.dx > maxX) maxX = bL.dx;
    if (bL.dy < minY) minY = bL.dy;
    if (bL.dy > maxY) maxY = bL.dy;

    if (bR.dx < minX) minX = bR.dx;
    if (bR.dx > maxX) maxX = bR.dx;
    if (bR.dy < minY) minY = bR.dy;
    if (bR.dy > maxY) maxY = bR.dy;

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Float64List toFloat64List() {
    return Float64List.fromList([
      a,
      b,
      0,
      0,
      c,
      d,
      0,
      0,
      0,
      0,
      1,
      0,
      tx,
      ty,
      0,
      1,
    ]);
  }

  Map<String, double> toDebugJson() {
    return {'a': a, 'b': b, 'c': c, 'd': d, 'tx': tx, 'ty': ty};
  }
}
