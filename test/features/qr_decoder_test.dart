// 0012 (C1): the QR scanner reads camera frames with zxing2, in pure Dart.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sha/features/qr/my_qr_screen.dart';
import 'package:sha/features/qr/qr_decoder.dart';

/// A code of the same form and length as a real `shaid:2` code (136
/// characters, ContactCode.encode).
String _sampleCode() {
  final random = Random(7);
  final bytes = Uint8List.fromList(
    List.generate(96, (_) => random.nextInt(256)),
  );
  return 'shaid:2:${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The brightness of an RGBA image, as the Y plane of a camera frame with
/// [padding] extra bytes at the end of each row (bytesPerRow > width).
LuminanceFrame _frameFromRgba(
  Uint8List rgba,
  int width,
  int height, {
  int padding = 0,
}) {
  final stride = width + padding;
  final y = Uint8List(stride * height)..fillRange(0, stride * height, 0x55);
  for (var row = 0; row < height; row++) {
    for (var x = 0; x < width; x++) {
      final i = (row * width + x) * 4;
      y[row * stride + x] =
          (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
    }
  }
  return LuminanceFrame(
    bytes: y,
    width: width,
    height: height,
    bytesPerRow: stride,
  );
}

/// Draws the QR card from "Min QR" (logo included) and returns its pixels.
Future<(Uint8List, int, int)> _renderContactQr(
  WidgetTester tester,
  String code,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          // A quiet zone around the card, as on the phone's screen.
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: ContactQrCode(code: code),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (data!.buffer.asUint8List(), image.width, image.height);
    image.dispose();
    return result;
  }))!;
}

/// A code drawn with perfect pixels: [scale] pixels per module and a quiet
/// zone of four modules, by the same `qr` package that "Min QR" uses.
LuminanceFrame _perfectFrame(String text, {int scale = 4}) {
  final image = QrImage(
    QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.H),
  );
  const quiet = 4;
  final modules = image.moduleCount;
  final size = (modules + 2 * quiet) * scale;
  final y = Uint8List(size * size)..fillRange(0, size * size, 255);
  for (var row = 0; row < modules; row++) {
    for (var column = 0; column < modules; column++) {
      if (!image.isDark(row, column)) continue;
      for (var dy = 0; dy < scale; dy++) {
        final start =
            ((row + quiet) * scale + dy) * size + (column + quiet) * scale;
        y.fillRange(start, start + scale, 0);
      }
    }
  }
  return LuminanceFrame(bytes: y, width: size, height: size, bytesPerRow: size);
}

/// Real `shaid:2`-shaped codes that zxing2 0.2.4 could not find as drawn
/// (FormatReaderException; `pureBarcode` read them), measured 2026-11-18.
/// The first three are read turned a quarter, the last two turned a half.
const _codesZxing2MissedAsDrawn = [
  'shaid:2:auJeDUxwPelicxF-VNdh5eNbik-7_EAzJEX8f8YC5H8zyLCSeT49V708JPjH55Y3o8uiijDW4IcX4dkq414_BaJ0v2WQyBva6ZTfOkIiA2S9pjd0vwhryFcwR2xl7fLx',
  'shaid:2:X-onSMG0nYgAjaovhb6ECNHQ-BiXfewYhTZfSkGnTDriDuhFu8wjpn8IN3wmy7p3fizVX_ASJj5Dhtv4hPrW2WtJ3JRSCqqobHTnK75_DtJ1QnZdXaCwhHjURdW91bKd',
  'shaid:2:UxqPJeUe33iNvzPZcWf9ywqYXY4HABr4dtkH5x6UCFDu_A0Hatke1BVv0_AgWbEUJ05q_1NrpQs5sl1SmqDt4sSOd7klypjc1_M92FsQvT2LlaoUXiTNIeoccs9e5DRz',
  'shaid:2:_d26EkYcAHbgh0MNECqfryyF6ty3kWVDrV8F4SDKHTc--Y02uEt4Unk8qjr1idisGW4FaUfIvKviCoZ7aKFC-Ayic0Sa4j7SY_4x-xVC6cH4GHZvAw3SIK4tbFwPMfmr',
  'shaid:2:zI1h7jwgfm7XmH2nCWAWLNb72NhHHL3k8nRlwTlj9KwqRfiDfyOVsIzZpsuTsMHtWK2nLA9qUGKUd6_430Im-IMA3c8bgeYrfjwG2TxyryI8Z-FOUGD6wzYHOLWV1vEb',
];

void main() {
  group('decodeQr', () {
    test('reads the codes zxing2 misses as drawn, by turning the frame', () {
      for (final code in _codesZxing2MissedAsDrawn) {
        expect(decodeQr(_perfectFrame(code)), code);
      }
    });

    test('reads 100 random shaid:2 codes', () {
      final random = Random(19);
      for (var i = 0; i < 100; i++) {
        final bytes = Uint8List.fromList(
          List.generate(96, (_) => random.nextInt(256)),
        );
        final code = 'shaid:2:${base64Url.encode(bytes).replaceAll('=', '')}';
        expect(decodeQr(_perfectFrame(code)), code, reason: 'code $i');
      }
    });

    testWidgets('reads the code that "Min QR" draws, logo and all', (
      tester,
    ) async {
      final code = _sampleCode();
      final (rgba, width, height) = await _renderContactQr(tester, code);
      expect(decodeQr(_frameFromRgba(rgba, width, height)), code);
    });

    testWidgets('reads a frame whose rows are padded (bytesPerRow > width)', (
      tester,
    ) async {
      final code = _sampleCode();
      final (rgba, width, height) = await _renderContactQr(tester, code);
      expect(decodeQr(_frameFromRgba(rgba, width, height, padding: 64)), code);
    });

    test('reads a small padded frame, which zxing2 reads row by row', () {
      // Under 40 pixels zxing2 binarizes row by row (getRow), not the whole
      // matrix: a version 1 code at one pixel per module is 29 pixels.
      final frame = _perfectFrame('SHA', scale: 1);
      final padded = Uint8List(frame.height * (frame.width + 8));
      for (var row = 0; row < frame.height; row++) {
        padded.setRange(
          row * (frame.width + 8),
          row * (frame.width + 8) + frame.width,
          frame.bytes,
          row * frame.width,
        );
      }
      expect(frame.width, lessThan(40));
      expect(
        decodeQr(
          LuminanceFrame(
            bytes: padded,
            width: frame.width,
            height: frame.height,
            bytesPerRow: frame.width + 8,
          ),
        ),
        'SHA',
      );
    });

    test('a row skips the padding at the end of the row before it', () {
      final frame = LuminanceFrame(
        bytes: Uint8List.fromList([1, 2, 3, 99, 99, 4, 5, 6, 99, 99]),
        width: 3,
        height: 2,
        bytesPerRow: 5,
      );
      expect(luminanceRow(frame, 0), [1, 2, 3]);
      expect(luminanceRow(frame, 1), [4, 5, 6]);
    });

    test('returns null when there is no code', () {
      const width = 320, height = 240;
      final random = Random(3);
      final noise = Uint8List.fromList(
        List.generate(width * height, (_) => random.nextInt(256)),
      );
      expect(
        decodeQr(
          LuminanceFrame(
            bytes: noise,
            width: width,
            height: height,
            bytesPerRow: width,
          ),
        ),
        isNull,
      );
    });

    test('returns null for a frame that does not fit its bytes', () {
      expect(
        decodeQr(
          LuminanceFrame(
            bytes: Uint8List(100),
            width: 320,
            height: 240,
            bytesPerRow: 320,
          ),
        ),
        isNull,
      );
      expect(
        decodeQr(
          LuminanceFrame(
            bytes: Uint8List(320 * 240),
            width: 320,
            height: 240,
            bytesPerRow: 100,
          ),
        ),
        isNull,
      );
    });
  });

  group('QrFrameReader', () {
    LuminanceFrame frame() => LuminanceFrame(
      bytes: Uint8List(4),
      width: 2,
      height: 2,
      bytesPerRow: 2,
    );

    test('reads one frame at a time and drops the others meanwhile', () async {
      final pending = <Completer<String?>>[];
      final codes = <String>[];
      final reader = QrFrameReader(
        onCode: codes.add,
        minInterval: Duration.zero,
        decode: (_) {
          final c = Completer<String?>();
          pending.add(c);
          return c.future;
        },
      );
      reader.add(frame());
      reader.add(frame());
      reader.add(frame());
      expect(pending, hasLength(1));
      pending.single.complete('shaid:2:x');
      await pumpEventQueue();
      expect(codes, ['shaid:2:x']);
      reader.add(frame());
      expect(pending, hasLength(2));
    });

    test('waits minInterval between two reads', () async {
      var now = DateTime(2026, 11, 18);
      var reads = 0;
      final reader = QrFrameReader(
        onCode: (_) {},
        minInterval: const Duration(milliseconds: 200),
        clock: () => now,
        decode: (_) async {
          reads++;
          return null;
        },
      );
      reader.add(frame());
      await pumpEventQueue();
      now = now.add(const Duration(milliseconds: 100));
      reader.add(frame());
      await pumpEventQueue();
      expect(reads, 1);
      now = now.add(const Duration(milliseconds: 100));
      reader.add(frame());
      await pumpEventQueue();
      expect(reads, 2);
    });

    test('says nothing after close, and a failed read is not a code', () async {
      final pending = Completer<String?>();
      final codes = <String>[];
      final reader = QrFrameReader(
        onCode: codes.add,
        minInterval: Duration.zero,
        decode: (_) => pending.future,
      );
      reader.add(frame());
      reader.close();
      pending.complete('shaid:2:x');
      await pumpEventQueue();
      expect(codes, isEmpty);

      final failing = QrFrameReader(
        onCode: codes.add,
        minInterval: Duration.zero,
        decode: (_) => Future.error(StateError('decoder crashed')),
      );
      failing.add(frame());
      await pumpEventQueue();
      expect(codes, isEmpty);
      // The reader is not stuck after a failure.
      failing.add(frame());
      await pumpEventQueue();
      expect(codes, isEmpty);
    });
  });
}
