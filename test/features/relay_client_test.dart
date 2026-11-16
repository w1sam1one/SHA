// P6: the relay client against a small server on this computer.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/features/transport/relay_client.dart';

final Uint8List mailbox = Uint8List.fromList(List.generate(16, (i) => i * 17));
const String mailboxHex = '00112233445566778899aabbccddeeff';

/// A fake server: [handle] answers each request; [requests] records them.
final class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final requests =
      <
        ({
          String method,
          String path,
          Uint8List body,
          HttpHeaders headers,
          int port,
          bool persistent,
        })
      >[];
  Future<void> Function(HttpRequest, Uint8List body)? handle;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<FakeServer> start() async {
    final s = FakeServer._(await HttpServer.bind('127.0.0.1', 0));
    s._server.listen((req) async {
      final body = BytesBuilder();
      await req.forEach(body.add);
      final bytes = body.takeBytes();
      s.requests.add((
        method: req.method,
        path: req.uri.path,
        body: bytes,
        headers: req.headers,
        port: req.connectionInfo!.remotePort,
        persistent: req.persistentConnection,
      ));
      final h = s.handle;
      if (h != null) {
        await h(req, bytes);
      } else {
        req.response.statusCode = HttpStatus.noContent;
      }
      await req.response.close();
    });
    return s;
  }

  Future<void> close() => _server.close(force: true);
}

Uint8List frames(List<List<int>> packets) {
  final out = BytesBuilder();
  for (final p in packets) {
    out
      ..add([
        (p.length >> 24) & 0xff,
        (p.length >> 16) & 0xff,
        (p.length >> 8) & 0xff,
        p.length & 0xff,
      ])
      ..add(p);
  }
  return out.takeBytes();
}

void main() {
  late FakeServer server;
  late HttpRelayClient client;

  setUp(() async {
    server = await FakeServer.start();
    client = HttpRelayClient(server.uri, timeout: const Duration(seconds: 2));
  });
  tearDown(() => server.close());

  test('drop posts the packet to the mailbox, with no User-Agent', () async {
    final packet = Uint8List.fromList(List.generate(322, (i) => i & 0xff));
    await client.drop(mailbox, packet);
    final r = server.requests.single;
    expect(r.method, 'POST');
    expect(r.path, '/v1/mailbox/$mailboxHex');
    expect(r.body, packet);
    expect(r.headers.value('user-agent'), isNull);
    expect(r.headers.contentType?.mimeType, 'application/octet-stream');
  });

  test('every request has its own connection (0004 §9 (b))', () async {
    await client.drop(mailbox, Uint8List(10));
    await client.drop(mailbox, Uint8List(10));
    expect(server.requests.map((r) => r.persistent), [false, false]);
    expect(server.requests[0].port, isNot(server.requests[1].port));
  });

  test('507 is RelayFull', () async {
    server.handle = (req, _) async => req.response.statusCode = 507;
    await expectLater(
      client.drop(mailbox, Uint8List(10)),
      throwsA(isA<RelayFull>()),
    );
  });

  test('429 is RelayBusy with Retry-After, bounded', () async {
    for (final (header, wait) in [
      ('30', const Duration(seconds: 30)),
      (null, HttpRelayClient.defaultRetryAfter),
      ('soon', HttpRelayClient.defaultRetryAfter),
      ('0', HttpRelayClient.defaultRetryAfter),
      ('999999', HttpRelayClient.maxRetryAfter),
    ]) {
      server.handle = (req, _) async {
        req.response.statusCode = HttpStatus.tooManyRequests;
        if (header != null) req.response.headers.set('Retry-After', header);
      };
      for (final call in [
        () => client.drop(mailbox, Uint8List(10)),
        () => client.fetch(mailbox),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<RelayBusy>().having((e) => e.retryAfter, 'retryAfter', wait),
          ),
          reason: '$header',
        );
      }
    }
  });

  test('other answers are RelayUnavailable', () async {
    for (final code in [200, 301, 400, 404, 413, 500, 503]) {
      server.handle = (req, _) async {
        req.response.statusCode = code;
        if (code == 301) req.response.headers.set('Location', '/x');
      };
      await expectLater(
        client.drop(mailbox, Uint8List(10)),
        throwsA(isA<RelayUnavailable>()),
        reason: '$code',
      );
    }
    server.handle = (req, _) async => req.response.statusCode = 204;
    await expectLater(client.fetch(mailbox), throwsA(isA<RelayUnavailable>()));
  });

  test('fetch reads every packet, and an empty mailbox gives none', () async {
    final a = List.generate(322, (i) => 1);
    final b = List.generate(1090, (i) => 2);
    server.handle = (req, _) async => req.response.add(frames([a, b]));
    final got = await client.fetch(mailbox);
    expect(got, [a, b]);
    expect(server.requests.single.method, 'GET');
    expect(server.requests.single.path, '/v1/mailbox/$mailboxHex');

    server.handle = (req, _) async => req.response.statusCode = 200;
    expect(await client.fetch(mailbox), isEmpty);
  });

  test('a broken answer to fetch is RelayUnavailable', () async {
    final good = frames([List.filled(10, 1)]);
    for (final body in [
      good.sublist(0, good.length - 1), // cut in the packet
      Uint8List.fromList([...good, 0, 0]), // cut in a length
      frames([<int>[]]), // an empty packet
      Uint8List.fromList([0, 1, 0, 0xb1]), // 65 713 bytes, too large
    ]) {
      server.handle = (req, _) async => req.response.add(body);
      await expectLater(
        client.fetch(mailbox),
        throwsA(isA<RelayUnavailable>()),
        reason: '$body',
      );
    }
  });

  test('no server and no answer are RelayUnavailable', () async {
    final port = server.uri.port;
    await server.close();
    final gone = HttpRelayClient(Uri.parse('http://127.0.0.1:$port'));
    await expectLater(
      gone.drop(mailbox, Uint8List(10)),
      throwsA(isA<RelayUnavailable>()),
    );

    final silent = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(silent.close);
    silent.listen((_) {}); // accepts and never answers
    final slow = HttpRelayClient(
      Uri.parse('http://127.0.0.1:${silent.port}'),
      timeout: const Duration(milliseconds: 300),
    );
    await expectLater(slow.fetch(mailbox), throwsA(isA<RelayUnavailable>()));
  });

  test('only https, or http to this computer, with nothing but a host', () {
    for (final ok in [
      'https://relay.example.se',
      'https://relay.example.se:8443',
      'https://relay.example.se/',
      'http://127.0.0.1:8080',
      'http://localhost:8080',
    ]) {
      expect(
        HttpRelayClient.isAllowedServer(Uri.parse(ok)),
        isTrue,
        reason: ok,
      );
    }
    for (final bad in [
      'http://relay.example.se',
      'ftp://relay.example.se',
      'https://',
      'https://relay.example.se/v1',
      'https://relay.example.se/?a=1',
      'https://relay.example.se/#x',
      'https://user@relay.example.se',
      'relay.example.se',
    ]) {
      expect(
        HttpRelayClient.isAllowedServer(Uri.parse(bad)),
        isFalse,
        reason: bad,
      );
    }
    expect(
      () => HttpRelayClient(Uri.parse('http://relay.example.se')),
      throwsArgumentError,
    );
  });

  test('a wrong mailbox ID length is refused before any request', () async {
    await expectLater(
      client.drop(Uint8List(15), Uint8List(10)),
      throwsArgumentError,
    );
    expect(server.requests, isEmpty);
  });
}
