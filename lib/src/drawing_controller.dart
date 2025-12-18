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
  });

  /// Rotation angle (0:0°, 1:90°, 2:180°, 3:270°)
  final int angle;

  final Type contentType;

  final int fingerCount;

  final Size? size;

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

  ui.Image? cachedImage;

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
    cachedImage = null;
    _refreshDeep();
  }

  /// Add multiple data items
  void addContents(List<PaintContent> contents) {
    _history.addAll(contents);
    _currentIndex += contents.length;
    cachedImage = null;
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
    if (_paintContent is Eraser) {
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
  }

  /// Drawing in progress
  void drawing(Offset nowPaint) {
    if (!hasPaintingContent) {
      return;
    }

    _isDrawingValidContent = true;

    if (_paintContent is Eraser) {
      eraserContent?.drawing(nowPaint);
      _refresh();
      _refreshDeep();
    } else {
      currentContent?.drawing(nowPaint);
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
      return;
    }

    _isDrawingValidContent = false;

    _startPoint = null;
    final int hisLen = _history.length;

    if (hisLen > _currentIndex) {
      _history.removeRange(_currentIndex, hisLen);
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

    _refresh();
    _refreshDeep();
    notifyListeners();
  }

  /// Undo
  void undo() {
    cachedImage = null;
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
    cachedImage = null;
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
    cachedImage = null;
    _history.clear();
    _currentIndex = 0;
    _refreshDeep();
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
