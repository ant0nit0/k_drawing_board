import 'dart:math' as math;
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
    this.inputScale = 1,
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
    this.inputScale = 1,
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

  /// How far the board is magnified on screen, `1` being its resting size.
  ///
  /// Stabilisation grows with it: zoomed-in work is slow and deliberate, so
  /// tremor makes up much more of the motion. Only read when [smoothness] is
  /// above zero.
  final double inputScale;

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
    double? inputScale,
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
      inputScale: inputScale ?? this.inputScale,
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

  /// Fraction of the remaining distance covered per event at `smoothness == 1`.
  /// The lower this is the harder the filter, and the more the stroke ignores
  /// everything but the overall direction of travel — which is what makes long
  /// clean curves easy to draw.
  static const double _kMinFollow = 0.015;

  /// Same, for the second filter pass. Running two passes instead of one turns
  /// the response from first into second order: the tremor that survives the
  /// first pass is attenuated again, and the emitted points land on a curve
  /// rather than on a rounded-off polyline.
  static const double _kMinSecondPassFollow = 0.15;

  /// Zoom level at which the extra stabilisation stops growing.
  static const double _kMaxZoomBoost = 4.0;

  /// How far the stabilised point may trail the finger at `smoothness == 1` and
  /// no zoom, in board units.
  ///
  /// This is the constant that decides how clean a stroke can get: whenever the
  /// filter would fall further behind than this, the leash takes over and the
  /// stroke is shaped like a string of this length being dragged by the finger.
  /// Tremor smaller than the leash barely moves the far end, so the longer it
  /// is, the smoother the drawn curve.
  static const double _kMaxLagAtRest = 160.0;

  /// Exponent applied to the slider before it scales the leash, so the extra
  /// reach is concentrated at the top of the range instead of being spread
  /// evenly over settings people use for everyday drawing.
  static const double _kLagCurve = 1.5;

  /// Board distance covered by a single catch-up point when a stabilised stroke
  /// is brought back onto the real pointer position.
  static const double _kSmoothingCatchUpSpacing = 4.0;

  /// Bounds on the number of interpolated points used for that catch-up.
  static const int _kMinSmoothingCatchUpSteps = 10;
  static const int _kMaxSmoothingCatchUpSteps = 64;

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

  /// Position held by the first filter pass of the stroke in progress.
  Offset? _smoothedPoint;

  /// Position held by the second filter pass, i.e. the point last handed to the
  /// paint content.
  Offset? _stabilisedPoint;

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

  /// Tell the controller how far the board is magnified on screen so it can
  /// stabilise zoomed-in strokes harder. `1` means the board is at rest.
  void setInputScale(double scale) {
    if (!scale.isFinite || scale <= 0) {
      return;
    }
    drawConfig.value = drawConfig.value.copyWith(inputScale: scale);
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
    _stabilisedPoint = startPoint;
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
    _stabilisedPoint = null;
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
      _stabilisedPoint = null;
      _lastRawPoint = null;
      _disposeCachedImage();
      return;
    }

    _isDrawingValidContent = false;

    _catchUpSmoothing();

    _startPoint = null;
    _smoothedPoint = null;
    _stabilisedPoint = null;
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
  ///
  /// Contents that only take paint away — the eraser — are left out: they do
  /// not make the drawing any bigger, see [PaintContent.affectsBounds]. What
  /// they took away is still counted, though, because this works from paths
  /// rather than pixels; [getVisibleBoundingBox] is the one that knows.
  Rect? getBoundingBox() {
    if (_history.isEmpty || _currentIndex == 0) {
      return null;
    }

    Rect? combinedBounds;
    for (int i = 0; i < _currentIndex && i < _history.length; i++) {
      final PaintContent content = _history[i];
      if (!content.affectsBounds) {
        continue;
      }
      final Rect? bounds = content.boundingBox;
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

  /// Whether any committed content only takes paint away.
  ///
  /// When false, [getBoundingBox] is already exact and the pixel scan of
  /// [getVisibleBoundingBox] has nothing to add.
  bool get hasErasedContent {
    for (int i = 0; i < _currentIndex && i < _history.length; i++) {
      if (!_history[i].affectsBounds) {
        return true;
      }
    }
    return false;
  }

  /// The smallest rectangle around the pixels the committed history actually
  /// leaves on the board, or null when it leaves none.
  ///
  /// [getBoundingBox] works from the contents' paths, which is cheap and exact
  /// for anything that only adds paint. It cannot know what an eraser took
  /// away: a stroke that was later rubbed out entirely still has a path, and
  /// still claims its corner of the box. This rasterises the history — the
  /// same display list the board paints from — and scans the alpha channel, so
  /// what it measures is what is visible.
  ///
  /// [size] is the board the contents were drawn on. It is only used when the
  /// history has never been painted; otherwise the size it was painted at
  /// wins, so the scan sees exactly what the board shows.
  ///
  /// [sampleScale] trades precision for speed: at 0.5 the scan reads a quarter
  /// of the bytes and the box is accurate to two board units, which is inside
  /// any stroke width. [alphaThreshold] is how opaque a pixel has to be to
  /// count, so antialiased fringes and near-transparent airbrush dust do not
  /// stretch the box.
  ///
  /// Falls back to [getBoundingBox] when the board has no size to render at.
  Future<Rect?> getVisibleBoundingBox({
    Size? size,
    double sampleScale = 0.5,
    int alphaThreshold = 8,
  }) async {
    if (_history.isEmpty || _currentIndex == 0) {
      return null;
    }
    final Size? boardSize =
        _historyPictureSize ?? size ?? drawConfig.value.size;
    if (boardSize == null || boardSize.isEmpty) {
      return getBoundingBox();
    }
    final ui.Picture? picture = historyPicture(boardSize);
    if (picture == null) {
      return null;
    }

    final double scale = sampleScale <= 0 ? 1.0 : sampleScale;
    final int width = math.max(1, (boardSize.width * scale).ceil());
    final int height = math.max(1, (boardSize.height * scale).ceil());

    // Rendered into a transparent buffer with no layer of its own, so the
    // eraser's `BlendMode.clear` punches through to alpha 0 — which is exactly
    // what makes an erased region read as empty below.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawPicture(picture);
    final ui.Picture scaled = recorder.endRecording();
    final ui.Image image = await scaled.toImage(width, height);
    scaled.dispose();

    final ByteData? data;
    try {
      data = await image.toByteData();
    } finally {
      image.dispose();
    }
    if (data == null) {
      return getBoundingBox();
    }

    final Rect? pixels = visibleBounds(
      data,
      width: width,
      height: height,
      alphaThreshold: alphaThreshold,
    );
    if (pixels == null) {
      return null;
    }

    // Back to board units. A sample pixel covers 1 / scale board units, and
    // the antialiased edge just under the threshold sits in the next one out.
    final Rect bounds = Rect.fromLTRB(
      pixels.left / scale,
      pixels.top / scale,
      pixels.right / scale,
      pixels.bottom / scale,
    ).inflate(1 / scale);
    return bounds.intersect(Offset.zero & boardSize);
  }

  /// The pixel rectangle of [rgba] whose alpha is above [alphaThreshold], in
  /// whole pixels — `right` and `bottom` are one past the last opaque column
  /// and row. Null when no pixel qualifies.
  ///
  /// [rgba] is the buffer `ui.Image.toByteData` returns for
  /// `ImageByteFormat.rawRgba`: four bytes per pixel, rows of [width] pixels.
  @visibleForTesting
  static Rect? visibleBounds(
    ByteData rgba, {
    required int width,
    required int height,
    int alphaThreshold = 8,
  }) {
    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;
    final Uint8List bytes = rgba.buffer.asUint8List(
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    final int rowStride = width * 4;
    for (int y = 0; y < height; y++) {
      final int rowStart = y * rowStride;
      // Alpha is the fourth byte of every pixel.
      for (int i = rowStart + 3, x = 0; x < width; i += 4, x++) {
        if (bytes[i] <= alphaThreshold) {
          continue;
        }
        if (x < minX) {
          minX = x;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
    }
    if (maxX < 0) {
      return null;
    }
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      maxX + 1.0,
      maxY + 1.0,
    );
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
    final int end =
        _currentIndex < _history.length ? _currentIndex : _history.length;

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

  /// How much of the remaining distance the stabilised point covers per event.
  ///
  /// The slider maps geometrically rather than linearly, so every step lengthens
  /// the filter's time constant by the same factor instead of crowding all the
  /// useful values at the top of the range.
  ///
  /// Zooming in gets extra help: at high magnification the hand moves slowly and
  /// deliberately, so tremor makes up much more of the motion and needs harder
  /// filtering to keep a curve clean.
  double _followFactor(double smoothness) {
    final double base = math.pow(_kMinFollow, smoothness).toDouble();
    final double zoom = drawConfig.value.inputScale.clamp(1.0, _kMaxZoomBoost);
    return (base / math.sqrt(zoom)).clamp(0.0, 1.0);
  }

  /// Same as [_followFactor] for the second pass. It stays much looser than the
  /// first one: its job is to round off what the first pass and the leash emit,
  /// not to add another helping of lag.
  double _secondPassFollowFactor(double smoothness) =>
      math.pow(_kMinSecondPassFollow, smoothness).toDouble().clamp(0.0, 1.0);

  /// Longest distance the stabilised point may trail the finger, in board units.
  ///
  /// Without this the strongest settings would fall arbitrarily far behind on a
  /// fast stroke. Dividing by the zoom keeps the trailing distance from growing
  /// with the magnification — but only by its square root, because dividing it
  /// out entirely would shrink the leash to nothing exactly when the canvas is
  /// zoomed in and the stroke is expected to be at its cleanest.
  double _maxLag(double smoothness) {
    final double zoom = drawConfig.value.inputScale.clamp(1.0, _kMaxZoomBoost);
    final double reach =
        _kMaxLagAtRest * math.pow(smoothness, _kLagCurve).toDouble();
    return reach / math.sqrt(zoom);
  }

  /// Pull the previous position part of the way towards [raw] instead of
  /// jumping to it, which filters out hand tremor and makes clean shapes far
  /// easier to draw.
  Offset _stabilise(Offset raw, PaintContent? content) {
    final double smoothness = drawConfig.value.smoothness.clamp(0.0, 1.0);
    final Offset? previous = _smoothedPoint;
    final Offset? previousStabilised = _stabilisedPoint;
    if (smoothness <= 0 ||
        previous == null ||
        previousStabilised == null ||
        !(content?.supportsInputSmoothing ?? true)) {
      _smoothedPoint = raw;
      _stabilisedPoint = raw;
      return raw;
    }

    Offset smoothed = previous + (raw - previous) * _followFactor(smoothness);
    Offset stabilised = previousStabilised +
        (smoothed - previousStabilised) * _secondPassFollowFactor(smoothness);

    // Leash the emitted point to the finger so heavy smoothing stays usable.
    final Offset behind = raw - stabilised;
    final double lag = behind.distance;
    final double maxLag = _maxLag(smoothness);
    if (lag > maxLag) {
      final Offset leashed = raw - behind * (maxLag / lag);
      // Carry both passes forward by the same correction. Leaving them where
      // they were would pin them against the leash for the rest of the stroke,
      // and a saturated filter simply copies the finger — tremor included —
      // which is the one thing the strongest settings must not do.
      smoothed += leashed - stabilised;
      stabilised = leashed;
    }

    _smoothedPoint = smoothed;
    _stabilisedPoint = stabilised;
    return stabilised;
  }

  /// Bring the stabilised stroke back onto the last real pointer position, so a
  /// stroke always ends where the finger was lifted instead of trailing behind.
  void _catchUpSmoothing() {
    final PaintContent? content = eraserContent ?? currentContent;
    final Offset? raw = _lastRawPoint;
    Offset? smoothed = _smoothedPoint;
    Offset? stabilised = _stabilisedPoint;
    if (content == null ||
        raw == null ||
        smoothed == null ||
        stabilised == null ||
        !content.supportsInputSmoothing ||
        (raw - stabilised).distance <= 1) {
      return;
    }

    final double smoothness = drawConfig.value.smoothness.clamp(0.0, 1.0);
    final double follow = _followFactor(smoothness);
    final double secondFollow = _secondPassFollowFactor(smoothness);
    final double startLag = (raw - stabilised).distance;

    // Step count follows the gap: the strongest settings trail far enough that
    // a fixed number of steps would join the stroke up with visible facets.
    final int steps = (startLag ~/ _kSmoothingCatchUpSpacing).clamp(
      _kMinSmoothingCatchUpSteps,
      _kMaxSmoothingCatchUpSteps,
    );

    for (int i = 1; i <= steps; i++) {
      // Keep running the filter against the point the finger stopped on, and
      // reel the leash in to nothing as it goes. The tail then curves onto the
      // finger along the direction the stroke was already travelling, instead
      // of cutting across to it in a straight line.
      smoothed = smoothed! + (raw - smoothed) * follow;
      stabilised = stabilised! + (smoothed - stabilised) * secondFollow;

      final double maxLag = startLag * (1 - i / steps);
      final Offset behind = raw - stabilised;
      final double lag = behind.distance;
      if (lag > maxLag) {
        final Offset leashed = lag == 0 ? raw : raw - behind * (maxLag / lag);
        smoothed += leashed - stabilised;
        stabilised = leashed;
      }

      content.drawing(stabilised);
    }

    _smoothedPoint = raw;
    _stabilisedPoint = raw;
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
