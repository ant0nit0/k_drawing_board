import 'package:flutter/painting.dart';
import '../paint_extension/ex_offset.dart';
import '../paint_extension/ex_paint.dart';

import 'paint_content.dart';

/// 直线
class StraightLine extends PaintContent {
  StraightLine();

  StraightLine.data({
    required this.startPoint,
    required this.endPoint,
    required Paint paint,
  }) : super.paint(paint);

  factory StraightLine.fromJson(Map<String, dynamic> data) {
    return StraightLine.data(
      startPoint: jsonToOffset(data['startPoint'] as Map<String, dynamic>),
      endPoint: jsonToOffset(data['endPoint'] as Map<String, dynamic>),
      paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
    );
  }

  Offset? startPoint;
  Offset? endPoint;

  @override
  String get contentType => 'StraightLine';

  @override
  void startDraw(Offset startPoint) => this.startPoint = startPoint;

  @override
  void drawing(Offset nowPoint) => endPoint = nowPoint;

  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    if (startPoint == null || endPoint == null) {
      return;
    }

    canvas.drawLine(startPoint!, endPoint!, paint);
  }

  @override
  Rect? get boundingBox {
    if (startPoint == null || endPoint == null) {
      return null;
    }
    final double halfStroke = paint.strokeWidth / 2;
    final double minX = startPoint!.dx < endPoint!.dx ? startPoint!.dx : endPoint!.dx;
    final double minY = startPoint!.dy < endPoint!.dy ? startPoint!.dy : endPoint!.dy;
    final double maxX = startPoint!.dx > endPoint!.dx ? startPoint!.dx : endPoint!.dx;
    final double maxY = startPoint!.dy > endPoint!.dy ? startPoint!.dy : endPoint!.dy;
    return Rect.fromLTRB(
      minX - halfStroke,
      minY - halfStroke,
      maxX + halfStroke,
      maxY + halfStroke,
    );
  }

  @override
  StraightLine copy() => StraightLine();

  @override
  Map<String, dynamic> toContentJson() {
    return <String, dynamic>{
      'startPoint': startPoint?.toJson(),
      'endPoint': endPoint?.toJson(),
      'paint': paint.toJson(),
    };
  }
}
