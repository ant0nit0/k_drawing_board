import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'helper/safe_value_notifier.dart';
import 'paint_contents/eraser.dart';
import 'paint_contents/paint_content.dart';
import 'paint_contents/simple_line.dart';
import 'paint_extension/ex_paint.dart';

/// Drawing parameters
class DrawConfig {
  DrawConfig({
    required this.contentType,
    this.angle = 0,
    this.fingerCount = 0,
    this.size,
    this.blendMode = BlendMode.srcOver,
    this.color = Colors.red,
    this.colorFilter,
    this.filterQuality = FilterQuality.high,
    this.imageFilter,
    this.invertColors = false,
    this.isAntiAlias = false,
    this.maskFilter,
    this.shader,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.strokeWidth = 4,
    this.style = PaintingStyle.stroke,
    this.smoothness = 0,
  });

  DrawConfig.def({
    required this.contentType,
    this.angle = 0,
    this.fingerCount = 0,
    this.size,
    this.blendMode = BlendMode.srcOver,
    this.color = Colors.red,
    this.colorFilter,
    this.filterQuality = FilterQuality.high,
    this.imageFilter,
    this.invertColors = false,
    this.isAntiAlias = false,
    this.maskFilter,
    this.shader,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.strokeWidth = 4,
    this.style = PaintingStyle.stroke,
    this.smoothness = 0,
  });

  /// Rotation angle (0:0°, 1:90°, 2:180°, 3:270°)
  final int angle;

  final Type contentType;

  final int fingerCount;

  final Size? size;

  /// How much the incoming pointer positions are stabilised before they reach
  /// the paint content, from `0` (raw input) to `1` (maximum stabilisation).
  ///
  /// Higher values filter out hand tremor and make it much easier to draw clean
  /// shapes, at the cost of the stroke lagging behind the finger.
  final double smoothness;

  /// Paint related properties
  final BlendMode blendMode;
  final Color color;
  final ColorFilter? colorFilter;
  final FilterQuality filterQuality;
  final ui.ImageFilter? imageFilter;
  final bool invertColors;
  final bool isAntiAlias;
  final MaskFilter? maskFilter;
  final Shader? shader;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final double strokeWidth;
  final PaintingStyle style;

  /// Generate paint object
  Paint get paint => Paint()
    ..blendMode = blendMode
    ..color = color
    ..colorFilter = colorFilter
    ..filterQuality = filterQuality
    ..imageFilter = imageFilter
    ..invertColors = invertColors
    ..isAntiAlias = isAntiAlias
    ..maskFilter = maskFilter
    ..shader = shader
    ..strokeCap = strokeCap
    ..strokeJoin = strokeJoin
    ..strokeWidth = strokeWidth
    ..style = style;

  DrawConfig copyWith({
    Type? contentType,
    BlendMode? blendMode,
    Color? color,
    ColorFilter? colorFilter,
    FilterQuality? filterQuality,
    ui.ImageFilter? imageFilter,
    bool? invertColors,
    bool? isAntiAlias,
    MaskFilter? maskFilter,
    Shader? shader,
    StrokeCap? strokeCap,
    StrokeJoin? strokeJoin,
    double? strokeWidth,
    PaintingStyle? style,
    int? angle,
    int? fingerCount,
    Size? size,
    double? smoothness,
  }) {
    return DrawConfig(
      contentType: contentType ?? this.contentType,
      angle: angle ?? this.angle,
      blendMode: blendMode ?? this.blendMode,
      color: color ?? this.color,
      colorFilter: colorFilter ?? this.colorFilter,
      filterQuality: filterQuality ?? this.filterQuality,
      imageFilter: imageFilter ?? this.imageFilter,
      invertColors: invertColors ?? this.invertColors,
      isAntiAlias: isAntiAlias ?? this.isAntiAlias,
      maskFilter: maskFilter ?? this.maskFilter,
      shader: shader ?? this.shader,
      strokeCap: strokeCap ?? this.strokeCap,
      strokeJoin: strokeJoin ?? this.strokeJoin,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      style: style ?? this.style,
      fingerCount: fingerCount ?? this.fingerCount,
      size: size ?? this.size,
      smoothness: smoothness ?? this.smoothness,
    );
  }
}

/// Drawing controller
class DrawingController extends ChangeNotifier {
  DrawingController({DrawConfig? config, PaintContent? content}) {
    _history = <PaintContent>[];
    _currentIndex = 0;
    realPainter = RePaintNotifier();
    painter = RePaintNotifier();
    drawConfig = SafeValueNotifier<DrawConfig>(
        config ?? DrawConfig.def(contentType: SimpleLine));
    setPaintContent(content ?? SimpleLine());
  }

  /// Strongest stabilisation applied at `smoothness == 1`. The pointer position
  /// is followed by `1 - _kMaxSmoothing` of the remaining distance per event,
  /// so 0.9 keeps a small amount of follow (0.1) instead of freezing the point.
  static const double _kMaxSmoothing = 0.9;

  /// Number of interpolated points used to bring a stabilised stroke back onto
  /// the real pointer position when the finger is lifted.
  static const int _kSmoothingCatchUpSteps = 6;

  /// Drawing start point
  Offset? _startPoint;

  /// Drawing board data key
  late GlobalKey painterKey = GlobalKey();

  /// Controller
  late SafeValueNotifier<DrawConfig> drawConfig;

  /// Last drawn content
  late PaintContent _paintContent;

  /// Current drawing content
  PaintContent? currentContent;

  /// Eraser content
  PaintContent? eraserContent;

  /// Raster snapshot of the committed history, only built while an eraser
  /// stroke is in progress (the eraser needs real pixels to punch through).
  ui.Image? cachedImage;

  /// Display list holding every committed content, so a repaint never has to
  /// replay the whole history through Dart again. Extended one stroke at a
  /// time instead of being rebuilt from scratch.
  ui.Picture? _historyPicture;

  /// Number of history entries already recorded into [_historyPicture].
  int _historyPictureIndex = 0;

  /// Board size [_historyPicture] was recorded for.
  Size? _historyPictureSize;

  /// Whether [_historyPicture] contains erasing (`BlendMode.clear`) operations
  /// and therefore has to be composited through its own layer.
  bool _historyPictureHasEraser = false;

  /// Last stabilised pointer position of the stroke in progress.
  Offset? _smoothedPoint;

  /// Last raw (un-stabilised) pointer position of the stroke in progress.
  Offset? _lastRawPoint;

  /// Bottom layer drawing content (drawing history)
  late List<PaintContent> _history;

  /// Whether the current controller is mounted
  bool _mounted = true;

  /// Get drawing layer/history
  List<PaintContent> get getHistory => _history;

  /// Step pointer
  late int _currentIndex;

  /// Surface canvas refresh control
  RePaintNotifier? painter;

  /// Bottom layer canvas refresh control
  RePaintNotifier? realPainter;

  /// Whether valid content was drawn
  bool _isDrawingValidContent = false;

  /// Get current step index
  int get currentIndex => _currentIndex;

  /// Get current color
  Color get getColor => drawConfig.value.color;

  /// Whether drawing can start
  bool get couldStartDraw => drawConfig.value.fingerCount == 0;

  /// Whether drawing can proceed
  bool get couldDrawing => drawConfig.value.fingerCount == 1;

  /// Whether there is content being drawn
  bool get hasPaintingContent =>
      currentContent != null || eraserContent != null;

  /// Start drawing point
  Offset? get startPoint => _startPoint;

  /// Set drawing board size
  void setBoardSize(Size? size) {
    drawConfig.value = drawConfig.value.copyWith(size: size);
  }

  /// Finger down
  void addFingerCount(Offset offset) {
    drawConfig.value = drawConfig.value
        .copyWith(fingerCount: drawConfig.value.fingerCount + 1);
  }

  /// Finger up
  void reduceFingerCount(Offset offset) {
    if (drawConfig.value.fingerCount <= 0) {
      return;
    }

    drawConfig.value = drawConfig.value
        .copyWith(fingerCount: drawConfig.value.fingerCount - 1);
  }

  /// Set drawing style
  void setStyle({
    BlendMode? blendMode,
    Color? color,
    ColorFilter? colorFilter,
    FilterQuality? filterQuality,
    ui.ImageFilter? imageFilter,
    bool? invertColors,
    bool? isAntiAlias,
    MaskFilter? maskFilter,
    Shader? shader,
    StrokeCap? strokeCap,
    StrokeJoin? strokeJoin,
    double? strokeMiterLimit,
    double? strokeWidth,
    PaintingStyle? style,
  }) {
    drawConfig.value = drawConfig.value.copyWith(
      blendMode: blendMode,
      color: color,
      colorFilter: colorFilter,
      filterQuality: filterQuality,
      imageFilter: imageFilter,
      invertColors: invertColors,
      isAntiAlias: isAntiAlias,
      maskFilter: maskFilter,
      shader: shader,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
      strokeWidth: strokeWidth,
      style: style,
    );
  }

  /// Set how much the pointer input is stabilised, from `0` (raw input) to `1`
  /// (maximum stabilisation). Values outside that range are clamped.
  void setSmoothness(double smoothness) {
    drawConfig.value =
        drawConfig.value.copyWith(smoothness: smoothness.clamp(0.0, 1.0));
  }

  /// Set drawing content
  void setPaintContent(PaintContent content) {
    content.paint = drawConfig.value.paint;
    _paintContent = content;
    drawConfig.value =
        drawConfig.value.copyWith(contentType: content.runtimeType);
  }

  /// Add a drawing data item
  void addContent(PaintContent content) {
    _history.add(content);
    _currentIndex++;
    _disposeCachedImage();
    _refreshDeep();
  }

  /// Add multiple data items
  void addContents(List<PaintContent> contents) {
    _history.addAll(contents);
    _currentIndex += contents.length;
    _disposeCachedImage();
    _refreshDeep();
  }

  /// Rotate canvas
  /// Set rotation angle
  void turn() {
    drawConfig.value =
        drawConfig.value.copyWith(angle: (drawConfig.value.angle + 1) % 4);
  }

  /// Start drawing
  void startDraw(Offset startPoint) {
    if (_currentIndex == 0 && _paintContent is Eraser) {
      return;
    }

    _startPoint = startPoint;
    _smoothedPoint = startPoint;
    _lastRawPoint = startPoint;
    if (_paintContent is Eraser) {
      // The eraser punches through the already drawn pixels, so it needs a
      // raster of the history. Build it once here rather than on every repaint.
      _ensureEraserSnapshot();
      eraserContent = _paintContent.copy();
      eraserContent?.paint = drawConfig.value.paint.copyWith();
      eraserContent?.startDraw(startPoint);
    } else {
      currentContent = _paintContent.copy();
      currentContent?.paint = drawConfig.value.paint;
      currentContent?.startDraw(startPoint);
    }
  }

  /// Cancel drawing
  void cancelDraw() {
    _startPoint = null;
    currentContent = null;
    eraserContent = null;
    _smoothedPoint = null;
    _lastRawPoint = null;
    _disposeCachedImage();
  }

  /// Drawing in progress
  void drawing(Offset nowPaint) {
    if (!hasPaintingContent) {
      return;
    }

    _isDrawingValidContent = true;
    _lastRawPoint = nowPaint;

    if (_paintContent is Eraser) {
      eraserContent?.drawing(_stabilise(nowPaint, eraserContent));
      _refresh();
      _refreshDeep();
    } else {
      currentContent?.drawing(_stabilise(nowPaint, currentContent));
      _refresh();
    }
  }

  /// End drawing
  void endDraw() {
    if (!hasPaintingContent) {
      return;
    }

    if (!_isDrawingValidContent) {
      // Clear drawing content
      _startPoint = null;
      currentContent = null;
      eraserContent = null;
      _smoothedPoint = null;
      _lastRawPoint = null;
      _disposeCachedImage();
      return;
    }

    _isDrawingValidContent = false;

    _catchUpSmoothing();

    _startPoint = null;
    _smoothedPoint = null;
    _lastRawPoint = null;
    final int hisLen = _history.length;

    if (hisLen > _currentIndex) {
      _history.removeRange(_currentIndex, hisLen);
      // Drawing after an undo drops the redo tail. If the cached render still
      // holds those entries it is stale, and appending onto it would keep a
      // stroke the user just replaced.
      if (_historyPictureIndex > _currentIndex) {
        _invalidateHistoryPicture();
      }
    }

    if (eraserContent != null) {
      _history.add(eraserContent!);
      _currentIndex = _history.length;
      eraserContent = null;
    }

    if (currentContent != null) {
      _history.add(currentContent!);
      _currentIndex = _history.length;
      currentContent = null;
    }

    _disposeCachedImage();

    _refresh();
    _refreshDeep();
    notifyListeners();
  }

  /// Undo
  void undo() {
    _disposeCachedImage();
    if (_currentIndex > 0) {
      _currentIndex = _currentIndex - 1;
      _refreshDeep();
      notifyListeners();
    }
  }

  /// Check if undo is available.
  /// Returns true if possible.
  bool canUndo() {
    if (_currentIndex > 0) {
      return true;
    } else {
      return false;
    }
  }

  /// Redo
  void redo() {
    _disposeCachedImage();
    if (_currentIndex < _history.length) {
      _currentIndex = _currentIndex + 1;
      _refreshDeep();
      notifyListeners();
    }
  }

  /// Check if redo is available.
  /// Returns true if possible.
  bool canRedo() {
    if (_currentIndex < _history.length) {
      return true;
    } else {
      return false;
    }
  }

  /// Clear canvas
  void clear() {
    _invalidateHistoryPicture();
    _history.clear();
    _currentIndex = 0;
    _refreshDeep();
  }

  /// Resize the board and all its contents by the given scale factor
  /// This will scale all drawing content, coordinates, and stroke widths
  void resize(double scaleFactor) {
    if (scaleFactor <= 0) {
      return;
    }

    // Resize all history items
    for (int i = 0; i < _history.length; i++) {
      _history[i] = _history[i].resize(scaleFactor);
    }

    // Resize current content if it exists
    if (currentContent != null) {
      currentContent = currentContent!.resize(scaleFactor);
    }

    // Resize eraser content if it exists
    if (eraserContent != null) {
      eraserContent = eraserContent!.resize(scaleFactor);
    }

    // Resize the board size
    if (drawConfig.value.size != null) {
      final Size currentSize = drawConfig.value.size!;
      setBoardSize(Size(
        currentSize.width * scaleFactor,
        currentSize.height * scaleFactor,
      ));
    }

    // Every content changed in place, so the cached render is now invalid
    _invalidateHistoryPicture();

    // Refresh both canvases
    _refresh();
    _refreshDeep();
    notifyListeners();
  }

  /// Get image data
  Future<ByteData?> getImageData() async {
    try {
      final RenderRepaintBoundary boundary = painterKey.currentContext!
          .findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(
          pixelRatio: View.of(painterKey.currentContext!).devicePixelRatio);
      return await image.toByteData(format: ui.ImageByteFormat.png);
    } catch (e) {
      debugPrint('Error getting image data: $e');
      return null;
    }
  }

  /// Get surface image data
  Future<ByteData?> getSurfaceImageData() async {
    try {
      if (cachedImage != null) {
        return await cachedImage!.toByteData(format: ui.ImageByteFormat.png);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting surface image data: $e');
      return null;
    }
  }

  /// Get drawing board content as JSON
  List<Map<String, dynamic>> getJsonList() {
    return _history.map((PaintContent e) => e.toJson()).toList();
  }

  /// Combined bounding box of all contents and return the smallest rectangle that contains all the contents.
  Rect? getBoundingBox() {
    if (_history.isEmpty || _currentIndex == 0) {
      return null;
    }

    Rect? combinedBounds;
    for (int i = 0; i < _currentIndex && i < _history.length; i++) {
      final Rect? bounds = _history[i].boundingBox;
      if (bounds != null && !bounds.isEmpty) {
        if (combinedBounds == null) {
          combinedBounds = bounds;
        } else {
          combinedBounds = combinedBounds.expandToInclude(bounds);
        }
      }
    }

    return combinedBounds;
  }

  // ---------------------------------------------------------------------
  // Cached history rendering
  // ---------------------------------------------------------------------

  /// Whether [historyPicture] has to be drawn through its own layer because it
  /// contains erasing operations.
  bool get historyPictureNeedsLayer => _historyPictureHasEraser;

  /// A display list containing every committed content up to [currentIndex],
  /// recorded for a board of [size].
  ///
  /// Replaying it is orders of magnitude cheaper than calling
  /// [PaintContent.draw] on every history entry again, which matters a lot for
  /// the textured brushes: they emit hundreds of primitives per stroke. The
  /// picture is extended one stroke at a time, so committing a stroke costs the
  /// same whether the drawing holds 3 strokes or 300.
  ///
  /// Returns `null` when there is nothing to draw.
  ui.Picture? historyPicture(Size size) {
    final int end = _currentIndex < _history.length
        ? _currentIndex
        : _history.length;

    if (end <= 0) {
      _invalidateHistoryPicture();
      return null;
    }

    final bool sameSize = _historyPictureSize == size;
    if (sameSize && _historyPicture != null && _historyPictureIndex == end) {
      return _historyPicture;
    }

    // Undo (and anything that rewrote the history) can only be honoured by
    // recording from scratch; new strokes are appended onto what we already
    // recorded.
    final bool canAppend =
        sameSize && _historyPicture != null && end > _historyPictureIndex;
    final int start = canAppend ? _historyPictureIndex : 0;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, Offset.zero & size);

    bool hasEraser = canAppend && _historyPictureHasEraser;
    if (canAppend) {
      canvas.drawPicture(_historyPicture!);
    }
    for (int i = start; i < end; i++) {
      final PaintContent content = _history[i];
      hasEraser = hasEraser || content is Eraser;
      content.draw(canvas, size, true);
    }

    final ui.Picture picture = recorder.endRecording();

    // Safe to release: the recording above keeps its own reference to the
    // previous picture's display list.
    _historyPicture?.dispose();
    _historyPicture = picture;
    _historyPictureIndex = end;
    _historyPictureSize = size;
    _historyPictureHasEraser = hasEraser;
    _disposeCachedImage();

    return picture;
  }

  /// Drop the cached render. The next paint records it again from the history.
  void _invalidateHistoryPicture() {
    _historyPicture?.dispose();
    _historyPicture = null;
    _historyPictureIndex = 0;
    _historyPictureSize = null;
    _historyPictureHasEraser = false;
    _disposeCachedImage();
  }

  void _disposeCachedImage() {
    cachedImage?.dispose();
    cachedImage = null;
  }

  /// Rasterise the committed history so the eraser has pixels to punch through.
  void _ensureEraserSnapshot() {
    if (cachedImage != null) {
      return;
    }
    final Size? size = _historyPictureSize ?? drawConfig.value.size;
    if (size == null || size.isEmpty) {
      return;
    }
    final ui.Picture? picture = historyPicture(size);
    if (picture == null) {
      return;
    }
    cachedImage = picture.toImageSync(
      size.width.ceil(),
      size.height.ceil(),
    );
  }

  // ---------------------------------------------------------------------
  // Pointer stabilisation
  // ---------------------------------------------------------------------

  /// Pull the previous position part of the way towards [raw] instead of
  /// jumping to it, which filters out hand tremor and makes clean shapes far
  /// easier to draw.
  Offset _stabilise(Offset raw, PaintContent? content) {
    final double smoothness = drawConfig.value.smoothness.clamp(0.0, 1.0);
    final Offset? previous = _smoothedPoint;
    if (smoothness <= 0 ||
        previous == null ||
        !(content?.supportsInputSmoothing ?? true)) {
      _smoothedPoint = raw;
      return raw;
    }

    final double follow = 1 - smoothness * _kMaxSmoothing;
    final Offset smoothed = previous + (raw - previous) * follow;
    _smoothedPoint = smoothed;
    return smoothed;
  }

  /// Bring the stabilised stroke back onto the last real pointer position, so a
  /// stroke always ends where the finger was lifted instead of trailing behind.
  void _catchUpSmoothing() {
    final PaintContent? content = eraserContent ?? currentContent;
    final Offset? raw = _lastRawPoint;
    final Offset? smoothed = _smoothedPoint;
    if (content == null ||
        raw == null ||
        smoothed == null ||
        !content.supportsInputSmoothing ||
        (raw - smoothed).distance <= 1) {
      return;
    }

    for (int i = 1; i <= _kSmoothingCatchUpSteps; i++) {
      content.drawing(
        Offset.lerp(smoothed, raw, i / _kSmoothingCatchUpSteps)!,
      );
    }
    _smoothedPoint = raw;
  }

  /// Refresh surface canvas
  void _refresh() {
    painter?._refresh();
  }

  /// Refresh bottom layer canvas
  void _refreshDeep() {
    realPainter?._refresh();
  }

  /// Dispose controller
  @override
  void dispose() {
    if (!_mounted) {
      return;
    }

    drawConfig.dispose();
    realPainter?.dispose();
    painter?.dispose();
    _invalidateHistoryPicture();

    _mounted = false;

    super.dispose();
  }
}

/// Canvas refresh controller
class RePaintNotifier extends ChangeNotifier {
  void _refresh() {
    notifyListeners();
  }
}
