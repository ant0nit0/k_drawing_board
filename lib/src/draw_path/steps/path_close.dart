// path.close();

import 'dart:ui';

import 'operation_step.dart';

class PathClose extends OperationStep {
  const PathClose();

  factory PathClose.fromJson(Map<String, dynamic> _) {
    return const PathClose();
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'type': 'close'};
  }

  @override
  PathClose translate(Offset offset) {
    return const PathClose();
  }
}
