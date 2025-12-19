import 'dart:ui';

import 'operation_step.dart';

class CubicTo extends OperationStep {
  const CubicTo(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);

  factory CubicTo.fromJson(Map<String, dynamic> data) {
    return CubicTo(
      data['x1'] as double,
      data['y1'] as double,
      data['x2'] as double,
      data['y2'] as double,
      data['x3'] as double,
      data['y3'] as double,
    );
  }

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x3;
  final double y3;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': 'cubicTo',
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'x3': x3,
      'y3': y3,
    };
  }

  @override
  CubicTo translate(Offset offset) {
    return CubicTo(
      x1 + offset.dx,
      y1 + offset.dy,
      x2 + offset.dx,
      y2 + offset.dy,
      x3 + offset.dx,
      y3 + offset.dy,
    );
  }
}
