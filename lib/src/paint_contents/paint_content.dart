import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

/// 绘制对象
abstract class PaintContent {
  PaintContent();

  PaintContent.paint(this.paint);

  /// 画笔
  late Paint paint;

  /// 复制实例，避免对象传递
  PaintContent copy();

  PaintContent translate(Offset offset);

  /// Resize the content by the given scale factor
  /// This will scale all coordinates and stroke width
  PaintContent resize(double scaleFactor);

  /// 绘制核心方法
  /// * [deeper] 当前是否为底层绘制
  /// * 出于性能考虑
  /// * 绘制过程为表层绘制，绘制完成抬起手指时会进行底层绘制
  void draw(Canvas canvas, Size size, bool deeper);

  /// 正在绘制
  void drawing(Offset nowPoint);

  /// 开始绘制
  void startDraw(Offset startPoint);

  /// 获取绘制内容的边界框
  /// 返回包含绘制内容的最小矩形，如果内容为空则返回null
  Rect? get boundingBox;

  /// Whether this content takes up room in the drawing.
  ///
  /// A drawing's bounding box is the union of its contents' boxes, and only
  /// things that put paint on the board belong in it. An eraser takes paint
  /// away: counting its path would grow the box around a region that is, by
  /// construction, blank. Contents that only ever subtract opt out.
  bool get affectsBounds => true;

  /// Whether the controller may stabilise (smooth) the pointer positions fed
  /// to [drawing].
  ///
  /// Free-hand contents follow every point, so smoothing them makes the stroke
  /// cleaner. Contents that only keep an anchor and a moving end point (lines,
  /// rectangles, circles) would just lag behind the finger, so they opt out.
  bool get supportsInputSmoothing => true;

  /// toJson
  Map<String, dynamic> toContentJson();

  /// contentType for web
  String get contentType => runtimeType.toString();

  /// toJson
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': contentType,
      ...toContentJson(),
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
