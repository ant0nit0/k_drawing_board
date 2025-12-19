import 'dart:ui';

import 'operation_step.dart';

class LineTo extends OperationStep {
  const LineTo(this.x, this.y);

  factory LineTo.fromJson(Map<String, dynamic> data) {
    return LineTo(
      data['x'] as double,
      data['y'] as double,
    );
  }

  final double x;
  final double y;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': 'lineTo',
      'x': x,
      'y': y,
    };
  }

  @override
  LineTo translate(Offset offset) {
    return LineTo(x + offset.dx, y + offset.dy);
  }
}
