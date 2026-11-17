import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../crypto/crypto.dart';

/// Why the server did not take or give packets. A fixed type: the HTTP
/// library's own error text can contain the address and the mailbox ID, and
/// is never kept, shown or logged.
sealed class RelayException implements Exception {
  const RelayException();
}

/// `429`: too many requests from this address. Wait [retryAfter].
final class RelayBusy extends RelayException {
  const RelayBusy(this.retryAfter);

  final Duration retryAfter;
}

/// `507`: the mailbox or the server is full. The packet stays in the outbox.
final class RelayFull extends RelayException {
  const RelayFull();
}

/// No answer, a timeout, or an answer the app cannot use.
final class RelayUnavailable extends RelayException {
  const RelayUnavailable();
}

/// The server's two functions (relay/README.md, 0002): leave a packet in a
/// mailbox, and fetch what is in a mailbox.
abstract interface class RelayClient {
  /// `POST /v1/mailbox/{id}`. Returns when the server answered `204`.
  Future<void> drop(Uint8List mailboxId, Uint8List packet);

  /// `GET /v1/mailbox/{id}`: every packet in the mailbox. Fetching deletes
  /// nothing, so the same packets come back until they expire.
  Future<List<Uint8List>> fetch(Uint8List mailboxId);
}

/// [RelayClient] over `dart:io` (no new dependency, P6).
///
/// - Every request has its own connection (0004 §9 (b)): a new
///   [HttpClient] that is closed afterwards.
/// - No `User-Agent` header, and no cookies or other state.
/// - `https` only, except `http` to this device itself outside release
///   builds (for tests). `dart:io` does not follow Android's
///   `network_security_config.xml`, so the check is made here.
/// - Responses are not decompressed, so the size limit counts what is
///   read.
final class HttpRelayClient implements RelayClient {
  HttpRelayClient(
    this.server, {
    this.timeout = const Duration(seconds: 30),
    HttpClient Function()? newClient,
  }) : _newClient = newClient ?? HttpClient.new {
    if (!isAllowedServer(server)) {
      throw ArgumentError.value(server, 'server', 'not an allowed address');
    }
  }

  final Uri server;
  final Duration timeout;
  final HttpClient Function() _newClient;

  /// The largest `GET` answer read: the relay's 8 MiB per mailbox plus four
  /// bytes per packet (relay/limits.go).
  static const int maxResponseBytes = (8 << 20) + 4 * 1000;

  /// Used when `429` has no usable `Retry-After`.
  static const Duration defaultRetryAfter = Duration(seconds: 60);
  static const Duration maxRetryAfter = Duration(hours: 1);

  /// `https` with a host and nothing else, or `http` to this device itself
  /// in debug and test builds only.
  static bool isAllowedServer(Uri uri) {
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    return !_release &&
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == '::1' ||
            uri.host == 'localhost');
  }

  @override
  Future<void> drop(Uint8List mailboxId, Uint8List packet) =>
      _request('POST', mailboxId, packet, (response) async {
        await response.drain<void>();
        if (response.statusCode != HttpStatus.noContent) {
          throw const RelayUnavailable();
        }
      });

  @override
  Future<List<Uint8List>> fetch(Uint8List mailboxId) =>
      _request('GET', mailboxId, null, (response) async {
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw const RelayUnavailable();
        }
        return _frames(await _readAll(response));
      });

  Future<T> _request<T>(
    String method,
    Uint8List mailboxId,
    Uint8List? body,
    Future<T> Function(HttpClientResponse) read,
  ) async {
    if (mailboxId.length != PacketV3.mailboxIdLength) {
      throw ArgumentError.value(mailboxId.length, 'mailboxId');
    }
    final client = _newClient()
      ..userAgent = null
      ..connectionTimeout = timeout
      ..idleTimeout = Duration.zero
      ..autoUncompress = false;
    try {
      return await () async {
        final request = await client.openUrl(
          method,
          server.replace(path: '/v1/mailbox/${_hex(mailboxId)}'),
        );
        request
          ..persistentConnection = false
          ..followRedirects = false
          // Ask for the packets as they are: nothing to decompress.
          ..headers.removeAll(HttpHeaders.acceptEncodingHeader);
        if (body != null) {
          request.headers.contentType = ContentType.binary;
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close();
        if (response.statusCode == HttpStatus.tooManyRequests) {
          await response.drain<void>();
          throw RelayBusy(_retryAfter(response.headers));
        }
        if (response.statusCode == 507) {
          await response.drain<void>();
          throw const RelayFull();
        }
        return read(response);
      }().timeout(timeout);
    } on RelayException {
      rethrow;
    } catch (_) {
      // Socket, TLS, timeout or format errors: the text is dropped here.
      throw const RelayUnavailable();
    } finally {
      client.close(force: true);
    }
  }

  static Duration _retryAfter(HttpHeaders headers) {
    final seconds = int.tryParse(headers.value('retry-after') ?? '');
    if (seconds == null || seconds < 1) return defaultRetryAfter;
    final wait = Duration(seconds: seconds);
    return wait > maxRetryAfter ? maxRetryAfter : wait;
  }

  static Future<Uint8List> _readAll(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) {
      throw const RelayUnavailable();
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in response) {
      out.add(chunk);
      if (out.length > maxResponseBytes) throw const RelayUnavailable();
    }
    return out.takeBytes();
  }

  /// The answer to `GET`: for each packet, 4 bytes of length (big-endian)
  /// and then the packet (relay/README.md).
  static List<Uint8List> _frames(Uint8List body) {
    final packets = <Uint8List>[];
    final data = ByteData.sublistView(body);
    var at = 0;
    while (at < body.length) {
      if (body.length - at < 4) throw const RelayUnavailable();
      final length = data.getUint32(at);
      at += 4;
      if (length == 0 ||
          length > PacketV3.maxPacketSize ||
          length > body.length - at) {
        throw const RelayUnavailable();
      }
      packets.add(body.sublist(at, at + length));
      at += length;
    }
    return packets;
  }

  static const bool _release = bool.fromEnvironment('dart.vm.product');

  static String _hex(Uint8List bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
}
