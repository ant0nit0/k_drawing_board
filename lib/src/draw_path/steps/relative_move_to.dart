import 'dart:ui';

import 'operation_step.dart';

class RelativeMoveTo extends OperationStep {
  const RelativeMoveTo(this.dx, this.dy);

  factory RelativeMoveTo.fromJson(Map<String, dynamic> data) {
    return RelativeMoveTo(
      data['dx'] as double,
      data['dy'] as double,
    );
  }

  final double dx;
  final double dy;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': 'relativeMoveTo',
      'dx': dx,
      'dy': dy,
    };
  }

  @override
  RelativeMoveTo translate(Offset offset) {
    return RelativeMoveTo(dx + offset.dx, dy + offset.dy);
  }
}
