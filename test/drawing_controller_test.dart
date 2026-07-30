import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every point it is handed, so tests can assert on what the controller
/// actually fed to the content.
class _RecordingContent extends PaintContent {
  _RecordingContent({this.smoothable = true});

  final bool smoothable;
  final List<Offset> points = <Offset>[];

  @override
  bool get supportsInputSmoothing => smoothable;

  @override
  String get contentType => 'RecordingContent';

  @override
  void startDraw(Offset startPoint) => points.add(startPoint);

  @override
  void drawing(Offset nowPoint) => points.add(nowPoint);

  @override
  void draw(Canvas canvas, Size size, bool deeper) {}

  @override
  Rect? get boundingBox => null;

  @override
  PaintContent copy() => _RecordingContent(smoothable: smoothable);

  @override
  PaintContent translate(Offset offset) => copy();

  @override
  PaintContent resize(double scaleFactor) => copy();

  @override
  Map<String, dynamic> toContentJson() => <String, dynamic>{};
}

/// Runs a stroke from [from] to [to] in [steps] equal moves, and returns the
/// content the controller committed for it.
PaintContent _stroke(
  DrawingController controller, {
  required Offset from,
  required Offset to,
  int steps = 10,
}) {
  controller.startDraw(from);
  for (int i = 1; i <= steps; i++) {
    controller.drawing(Offset.lerp(from, to, i / steps)!);
  }
  final PaintContent content = controller.currentContent!;
  controller.endDraw();
  return content;
}

/// [_stroke] for the recording content used by the smoothing tests.
_RecordingContent _recordedStroke(
  DrawingController controller, {
  required Offset from,
  required Offset to,
  int steps = 10,
}) =>
    _stroke(controller, from: from, to: to, steps: steps) as _RecordingContent;

void main() {
  group('input smoothing', () {
    test('follows the pointer exactly when smoothness is 0', () {
      final DrawingController controller =
          DrawingController(content: _RecordingContent());
      controller.setSmoothness(0);

      final _RecordingContent content = _recordedStroke(
        controller,
        from: Offset.zero,
        to: const Offset(100, 0),
        steps: 4,
      );

      expect(content.points, <Offset>[
        Offset.zero,
        const Offset(25, 0),
        const Offset(50, 0),
        const Offset(75, 0),
        const Offset(100, 0),
      ]);
      controller.dispose();
    });

    test('barely follows a small move at full smoothness', () {
      final DrawingController controller =
          DrawingController(content: _RecordingContent());
      controller.setSmoothness(1);

      controller.startDraw(Offset.zero);
      controller.drawing(const Offset(10, 0));
      final _RecordingContent content =
          controller.currentContent! as _RecordingContent;

      // 0.02 follow at full smoothness: 2% of a 10pt move.
      expect(content.points.last.dx, closeTo(0.2, 0.001));
      controller.dispose();
    });

    test('never trails the finger further than the leash', () {
      final DrawingController controller =
          DrawingController(content: _RecordingContent());
      controller.setSmoothness(1);

      // A long fast stroke would leave a pure filter arbitrarily far behind.
      controller.startDraw(Offset.zero);
      for (int i = 1; i <= 20; i++) {
        controller.drawing(Offset(i * 200, 0));
      }
      final _RecordingContent content =
          controller.currentContent! as _RecordingContent;

      expect(4000 - content.points.last.dx, lessThanOrEqualTo(48.001));
      controller.dispose();
    });

    test('stabilises harder the further the canvas is zoomed in', () {
      double followedDistance(double zoom) {
        final DrawingController controller =
            DrawingController(content: _RecordingContent());
        controller.setSmoothness(1);
        controller.setInputScale(zoom);
        controller.startDraw(Offset.zero);
        controller.drawing(const Offset(10, 0));
        final double dx =
            (controller.currentContent! as _RecordingContent).points.last.dx;
        controller.dispose();
        return dx;
      }

      // Following less of the move means more of the tremor is filtered out.
      expect(followedDistance(4), lessThan(followedDistance(1)));
      expect(followedDistance(2), lessThan(followedDistance(1)));
    });

    test('ignores a zero or non-finite input scale', () {
      final DrawingController controller = DrawingController();
      controller.setInputScale(3);

      controller.setInputScale(0);
      expect(controller.drawConfig.value.inputScale, 3);

      controller.setInputScale(double.nan);
      expect(controller.drawConfig.value.inputScale, 3);
      controller.dispose();
    });

    test('ends the stroke on the real pointer position', () {
      final DrawingController controller =
          DrawingController(content: _RecordingContent());
      controller.setSmoothness(1);

      final _RecordingContent content = _recordedStroke(
        controller,
        from: Offset.zero,
        to: const Offset(200, 0),
        steps: 5,
      );

      // Without the catch-up the smoothed stroke would stop well short of 200.
      expect(content.points.last, const Offset(200, 0));
      controller.dispose();
    });

    test('leaves contents that opt out untouched', () {
      final DrawingController controller =
          DrawingController(content: _RecordingContent(smoothable: false));
      controller.setSmoothness(1);

      final _RecordingContent content = _recordedStroke(
        controller,
        from: Offset.zero,
        to: const Offset(100, 0),
        steps: 2,
      );

      expect(content.points, <Offset>[
        Offset.zero,
        const Offset(50, 0),
        const Offset(100, 0),
      ]);
      controller.dispose();
    });

    test('clamps the configured smoothness to 0..1', () {
      final DrawingController controller = DrawingController();

      controller.setSmoothness(7);
      expect(controller.drawConfig.value.smoothness, 1);

      controller.setSmoothness(-3);
      expect(controller.drawConfig.value.smoothness, 0);
      controller.dispose();
    });
  });

  group('history picture cache', () {
    const Size size = Size(100, 100);

    DrawingController newController() =>
        DrawingController(content: SimpleLine());

    test('returns null while the history is empty', () {
      final DrawingController controller = newController();
      expect(controller.historyPicture(size), isNull);
      controller.dispose();
    });

    test('reuses the same picture when nothing changed', () {
      final DrawingController controller = newController();
      _stroke(controller, from: Offset.zero, to: const Offset(10, 10));

      final ui.Picture? first = controller.historyPicture(size);
      expect(first, isNotNull);
      expect(identical(controller.historyPicture(size), first), isTrue);
      controller.dispose();
    });

    test('records again for a different board size', () {
      final DrawingController controller = newController();
      _stroke(controller, from: Offset.zero, to: const Offset(10, 10));

      final ui.Picture? first = controller.historyPicture(size);
      final ui.Picture? resized =
          controller.historyPicture(const Size(200, 200));
      expect(identical(first, resized), isFalse);
      controller.dispose();
    });

    test('extends the picture when a stroke is committed', () {
      final DrawingController controller = newController();
      _stroke(controller, from: Offset.zero, to: const Offset(10, 10));
      final ui.Picture? first = controller.historyPicture(size);

      _stroke(controller, from: const Offset(20, 20), to: const Offset(30, 30));
      final ui.Picture? second = controller.historyPicture(size);

      expect(identical(first, second), isFalse);
      controller.dispose();
    });

    test('rebuilds after undo and after redo', () {
      final DrawingController controller = newController();
      _stroke(controller, from: Offset.zero, to: const Offset(10, 10));
      _stroke(controller, from: const Offset(20, 20), to: const Offset(30, 30));
      final ui.Picture? both = controller.historyPicture(size);

      controller.undo();
      final ui.Picture? afterUndo = controller.historyPicture(size);
      expect(identical(both, afterUndo), isFalse);

      controller.redo();
      final ui.Picture? afterRedo = controller.historyPicture(size);
      expect(identical(afterUndo, afterRedo), isFalse);
      controller.dispose();
    });

    test('drops the cache when drawing over an undone stroke', () {
      final DrawingController controller = newController();
      _stroke(controller, from: Offset.zero, to: const Offset(10, 10));
      _stroke(controller, from: const Offset(20, 20), to: const Offset(30, 30));
      controller.historyPicture(size);

      controller.undo();
      // Deliberately skip a repaint here: the new stroke lands on an index the
      // cache already covered, so only an explicit invalidation keeps it right.
      _stroke(controller, from: const Offset(40, 40), to: const Offset(50, 50));

      expect(controller.currentIndex, 2);
      expect(controller.getHistory.length, 2);
      expect(controller.getHistory.last, isA<SimpleLine>());
      // A fresh picture must be recorded rather than the stale 2-stroke one.
      expect(controller.historyPicture(size), isNotNull);
      controller.dispose();
    });

    test('clear drops the cached picture', () {
      final DrawingController controller = newController();
      _stroke(controller, from: Offset.zero, to: const Offset(10, 10));
      controller.historyPicture(size);

      controller.clear();
      expect(controller.historyPicture(size), isNull);
      controller.dispose();
    });
  });
}
