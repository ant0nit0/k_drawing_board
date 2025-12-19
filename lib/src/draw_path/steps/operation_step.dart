import 'dart:ui';

abstract class OperationStep {
  const OperationStep();

  Map<String, dynamic> toJson();

  OperationStep translate(Offset offset);
}
