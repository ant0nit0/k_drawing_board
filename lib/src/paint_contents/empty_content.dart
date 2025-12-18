import 'dart:ui';

import 'paint_content.dart';

class EmptyContent extends PaintContent {
  EmptyContent();

  factory EmptyContent.fromJson(Map<String, dynamic> _) => EmptyContent();

  @override
  String get contentType => 'EmptyContent';

  @override
  PaintContent copy() => EmptyContent();

  @override
  PaintContent translate(Offset offset) => EmptyContent();

  @override
  void draw(Canvas canvas, Size size, bool deeper) {}

  @override
  void drawing(Offset nowPoint) {}

  @override
  void startDraw(Offset startPoint) {}

  @override
  Rect? get boundingBox => null;

  @override
  Map<String, dynamic> toContentJson() {
    return <String, dynamic>{};
  }
}
