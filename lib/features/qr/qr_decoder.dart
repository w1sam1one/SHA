import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:zxing2/qrcode.dart';

/// The brightness of one camera frame: the Y plane of a YUV 4:2:0 image, as
/// the camera gives it. Each row is [bytesPerRow] bytes, which can be more
/// than [width].
class LuminanceFrame {
  const LuminanceFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;

  bool get _fits =>
      width > 0 &&
      height > 0 &&
      bytesPerRow >= width &&
      bytes.length >= bytesPerRow * (height - 1) + width;
}

/// The text of the QR code in [frame], or null if there is none.
///
/// Decision 0012 (C1): zxing2, ZXing in pure Dart. The frame comes from the
/// camera, which anyone can point at anything, so it is read in memory-safe
/// code. Only QR codes are looked for.
///
/// zxing2's detector misses some codes in one orientation that it reads
/// turned. Measured 2026-11-18 with perfect pixels and random `shaid:2`
/// codes: 3 of 120 failed as drawn, and `pureBarcode` read all of them, so
/// the fault is in finding the code, not in decoding it. Turned a quarter,
/// 2 of 1000 still failed; turned a half, those were read too. The camera's
/// frames come in any orientation anyway, so a frame that gives nothing is
/// tried turned a quarter and a half. Light modules on a dark background are
/// tried last.
String? decodeQr(LuminanceFrame frame) {
  if (!frame._fits) return null;
  final source = _PlaneLuminanceSource(frame);
  final quarter = _turnedQuarter(source);
  return _read(source) ??
      _read(quarter) ??
      _read(_turnedQuarter(quarter)) ??
      _read(source.invert());
}

/// Row [y] of [frame] as zxing2 sees it (its threshold uses single rows).
@visibleForTesting
Int8List luminanceRow(LuminanceFrame frame, int y) =>
    _PlaneLuminanceSource(frame).getRow(y, null);

/// [source] turned a quarter clockwise.
LuminanceSource _turnedQuarter(LuminanceSource source) {
  final width = source.width;
  final height = source.height;
  final matrix = source.getMatrix();
  final turned = Int8List(width * height);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    final column = height - 1 - y;
    for (var x = 0; x < width; x++) {
      turned[x * height + column] = matrix[row + x];
    }
  }
  return _MatrixLuminanceSource(turned, height, width);
}

String? _read(LuminanceSource source) {
  final hints = DecodeHints()
    ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode]);
  try {
    return QRCodeReader()
        .decode(BinaryBitmap(HybridBinarizer(source)), hints: hints)
        .text;
  } on ReaderException {
    return null;
  }
}

/// A Y plane with rows of [LuminanceFrame.bytesPerRow] bytes, without
/// copying it.
class _PlaneLuminanceSource extends LuminanceSource {
  _PlaneLuminanceSource(LuminanceFrame frame)
    : _data = Int8List.sublistView(frame.bytes),
      _stride = frame.bytesPerRow,
      super(frame.width, frame.height);

  final Int8List _data;
  final int _stride;

  @override
  Int8List getRow(int y, Int8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    final out = (row == null || row.length < width) ? Int8List(width) : row;
    out.setRange(0, width, _data, y * _stride);
    return out;
  }

  @override
  Int8List getMatrix() {
    if (_stride == width) {
      return Int8List.sublistView(_data, 0, width * height);
    }
    final matrix = Int8List(width * height);
    for (var y = 0; y < height; y++) {
      matrix.setRange(y * width, (y + 1) * width, _data, y * _stride);
    }
    return matrix;
  }
}

/// A whole image, one byte per pixel, rows without padding.
class _MatrixLuminanceSource extends LuminanceSource {
  _MatrixLuminanceSource(this._matrix, int width, int height)
    : super(width, height);

  final Int8List _matrix;

  @override
  Int8List getRow(int y, Int8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    final out = (row == null || row.length < width) ? Int8List(width) : row;
    out.setRange(0, width, _matrix, y * width);
    return out;
  }

  @override
  Int8List getMatrix() => _matrix;
}

/// Reads camera frames for a QR code, one at a time.
///
/// The camera sends many frames a second. A frame that arrives while one is
/// being read, or sooner than [minInterval] after the last read began, is
/// dropped. Reading runs in a background isolate, so the preview stays
/// smooth. A frame that cannot be read is simply not a code.
class QrFrameReader {
  QrFrameReader({
    required this.onCode,
    Future<String?> Function(LuminanceFrame frame)? decode,
    this.minInterval = const Duration(milliseconds: 150),
    DateTime Function()? clock,
  }) : _decode = decode ?? _decodeInBackground,
       _clock = clock ?? DateTime.now;

  /// Called with the text of each code found.
  final void Function(String code) onCode;
  final Future<String?> Function(LuminanceFrame frame) _decode;
  final DateTime Function() _clock;
  final Duration minInterval;

  bool _busy = false;
  bool _closed = false;
  DateTime? _lastRead;

  void add(LuminanceFrame frame) {
    if (_busy || _closed) return;
    final now = _clock();
    final last = _lastRead;
    if (last != null && now.difference(last) < minInterval) return;
    _busy = true;
    _lastRead = now;
    unawaited(
      _decode(frame)
          .then<void>((code) {
            if (!_closed && code != null) onCode(code);
          }, onError: (Object _) {})
          .whenComplete(() => _busy = false),
    );
  }

  /// No more codes are delivered after this, not even from a read that has
  /// already begun.
  void close() => _closed = true;
}

Future<String?> _decodeInBackground(LuminanceFrame frame) =>
    compute(decodeQr, frame);
