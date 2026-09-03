import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';
import 'package:flutter_test/flutter_test.dart';

Paint _paint(double width) => Paint()
  ..color = const Color(0xFF000000)
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.butt
  ..strokeWidth = width;

/// A straight stroke, as the board would have recorded it.
SimpleLine _line(Offset from, Offset to, {double width = 4}) {
  final SimpleLine line = SimpleLine()..paint = _paint(width);
  line
    ..startDraw(from)
    ..drawing(to);
  return line;
}

Eraser _eraser(Offset from, Offset to, {double width = 40}) {
  final Eraser eraser = Eraser()..paint = _paint(width);
  eraser
    ..startDraw(from)
    ..drawing(to);
  return eraser;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getBoundingBox', () {
    test('an eraser stroke does not widen the box', () {
      final DrawingController controller = DrawingController();
      controller.addContents(<PaintContent>[
        _line(const Offset(10, 10), const Offset(50, 30)),
        _eraser(const Offset(200, 200), const Offset(300, 300)),
      ]);

      expect(controller.hasErasedContent, isTrue);
      // The path, plus half the stroke width all round.
      expect(controller.getBoundingBox(), const Rect.fromLTRB(8, 8, 52, 32));
      controller.dispose();
    });

    test('a drawing made of nothing but eraser strokes has no box', () {
      final DrawingController controller = DrawingController();
      controller.addContent(
        _eraser(Offset.zero, const Offset(100, 100)),
      );

      expect(controller.getBoundingBox(), isNull);
      controller.dispose();
    });

    test('hasErasedContent is false when nothing was erased', () {
      final DrawingController controller = DrawingController();
      controller.addContent(_line(Offset.zero, const Offset(10, 0)));

      expect(controller.hasErasedContent, isFalse);
      controller.dispose();
    });
  });

  group('visibleBounds', () {
    test('finds the opaque pixels of a raw RGBA buffer', () {
      const int width = 6;
      const int height = 4;
      final ByteData rgba = ByteData(width * height * 4);
      void paint(int x, int y, int alpha) => rgba.setUint8((y * width + x) * 4 + 3, alpha);
      paint(2, 1, 255);
      paint(4, 2, 255);
      // A fringe under the threshold must not count.
      paint(0, 3, 4);

      expect(
        DrawingController.visibleBounds(rgba, width: width, height: height),
        const Rect.fromLTRB(2, 1, 5, 3),
      );
    });

    test('is null for a blank buffer', () {
      expect(
        DrawingController.visibleBounds(ByteData(6 * 4 * 4), width: 6, height: 4),
        isNull,
      );
    });
  });

  group('getVisibleBoundingBox', () {
    test('stops where the eraser took the stroke away', () async {
      final DrawingController controller = DrawingController();
      controller.addContents(<PaintContent>[
        _line(const Offset(10, 50), const Offset(90, 50)),
        // Clears x in [50, 100].
        _eraser(const Offset(75, 0), const Offset(75, 100), width: 50),
      ]);

      final Rect? visible = await controller.getVisibleBoundingBox(
        size: const Size(100, 100),
        sampleScale: 1,
      );

      expect(visible, isNotNull);
      expect(visible!.left, closeTo(10, 2));
      expect(visible.right, closeTo(50, 2));
      expect(visible.top, closeTo(48, 2));
      expect(visible.bottom, closeTo(52, 2));
      controller.dispose();
    });

    test('a stroke rubbed out entirely leaves no box', () async {
      final DrawingController controller = DrawingController();
      controller.addContents(<PaintContent>[
        _line(const Offset(10, 50), const Offset(90, 50)),
        _eraser(const Offset(0, 50), const Offset(100, 50), width: 20),
      ]);

      expect(
        await controller.getVisibleBoundingBox(
          size: const Size(100, 100),
          sampleScale: 1,
        ),
        isNull,
      );
      controller.dispose();
    });

    test('matches the path box when nothing was erased', () async {
      final DrawingController controller = DrawingController();
      controller.addContent(_line(const Offset(10, 50), const Offset(90, 50)));

      final Rect? visible = await controller.getVisibleBoundingBox(
        size: const Size(100, 100),
        sampleScale: 1,
      );

      expect(visible, isNotNull);
      expect(visible!.left, closeTo(10, 2));
      expect(visible.right, closeTo(90, 2));
      controller.dispose();
    });
  });
}
