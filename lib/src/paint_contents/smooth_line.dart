import 'dart:ui';
import '../paint_extension/ex_offset.dart';
import '../paint_extension/ex_paint.dart';
import 'paint_content.dart';

/// 笔触线条
class SmoothLine extends PaintContent {
  SmoothLine({
    /// 绘制影响因子，值越小线条越平滑，粗细变化越慢
    this.brushPrecision = 0.4,
  });

  SmoothLine.data({
    this.brushPrecision = 0.4,
    required this.points,
    required this.strokeWidthList,
    required Paint paint,
  }) : super.paint(paint);

  factory SmoothLine.fromJson(Map<String, dynamic> data) {
    return SmoothLine.data(
      brushPrecision: data['brushPrecision'] as double,
      points: (data['points'] as List<dynamic>)
          .map((dynamic e) => jsonToOffset(e as Map<String, dynamic>))
          .toList(),
      strokeWidthList: (data['strokeWidthList'] as List<dynamic>)
          .map((dynamic e) => e as double)
          .toList(),
      paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
    );
  }

  final double brushPrecision;

  /// 绘制点列表
  late List<Offset> points;

  /// 点之间的绘制线条权重列表
  late List<double> strokeWidthList;

  @override
  String get contentType => 'SmoothLine';

  @override
  void startDraw(Offset startPoint) {
    points = <Offset>[startPoint];
    strokeWidthList = <double>[paint.strokeWidth];
  }

  @override
  void drawing(Offset nowPoint) {
    final double distance = (nowPoint - points.last).distance;

    //原始画笔线条线宽
    final double s = paint.strokeWidth;

    double strokeWidth = s * (s * 2 / (s * distance));

    if (strokeWidth > s * 2) {
      strokeWidth = s * 2;
    }

    //上一个线宽
    final double preWidth = strokeWidthList.last;

    if (strokeWidth - preWidth > brushPrecision) {
      strokeWidth = preWidth + brushPrecision;
    } else if (preWidth - strokeWidth > brushPrecision) {
      strokeWidth = preWidth - brushPrecision;
    }

    //记录点位
    points.add(nowPoint);
    strokeWidthList.add(strokeWidth);
  }

  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    for (int i = 1; i < points.length; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(points[i - 1].dx, points[i - 1].dy)
          ..lineTo(points[i].dx, points[i].dy),
        paint.copyWith(
            strokeWidth: strokeWidthList[i], blendMode: BlendMode.src),
      );
    }
  }

  @override
  Rect? get boundingBox {
    if (points.isEmpty) {
      return null;
    }
    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;
    double maxStrokeWidth =
        strokeWidthList.isNotEmpty ? strokeWidthList.first : paint.strokeWidth;

    for (int i = 0; i < points.length; i++) {
      final Offset point = points[i];
      final double strokeWidth =
          i < strokeWidthList.length ? strokeWidthList[i] : paint.strokeWidth;

      minX = minX < point.dx ? minX : point.dx;
      minY = minY < point.dy ? minY : point.dy;
      maxX = maxX > point.dx ? maxX : point.dx;
      maxY = maxY > point.dy ? maxY : point.dy;
      maxStrokeWidth =
          maxStrokeWidth > strokeWidth ? maxStrokeWidth : strokeWidth;
    }

    final double halfStroke = maxStrokeWidth / 2;
    return Rect.fromLTRB(
      minX - halfStroke,
      minY - halfStroke,
      maxX + halfStroke,
      maxY + halfStroke,
    );
  }

  @override
  SmoothLine copy() => SmoothLine(brushPrecision: brushPrecision);

  @override
  PaintContent translate(Offset offset) {
    return SmoothLine.data(
      brushPrecision: brushPrecision,
      points: points.map((Offset point) => point + offset).toList(),
      strokeWidthList: List<double>.from(strokeWidthList),
      paint: paint,
    );
  }

  @override
  Map<String, dynamic> toContentJson() {
    return <String, dynamic>{
      'brushPrecision': brushPrecision,
      'points': points.map((Offset e) => e.toJson()).toList(),
      'strokeWidthList': strokeWidthList,
      'paint': paint.toJson(),
    };
  }
}
