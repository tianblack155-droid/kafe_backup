import 'dart:async';
import 'dart:io';

/// Small transport seam for deterministic tests; production uses native IO.
abstract class RealtimeSocket {
  Stream<dynamic> get messages;
  void send(String message);
  Future<void> close();
}

typedef RealtimeConnector = Future<RealtimeSocket> Function(
  Uri url,
  Map<String, String> headers,
);

/// WebSocket.connect calls customClient.openUrl, not getUrl. Set the flag on
/// the actual handshake request; an Origin header does not constrain redirects.
class _NoRedirectClient implements HttpClient {
  _NoRedirectClient(this.client);
  final HttpClient client;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await client.openUrl(method, url);
    request.followRedirects = false;
    return request;
  }

  @override
  void close({bool force = false}) => client.close(force: force);

  // Only openUrl is used by the SDK handshake. Fail closed for other methods.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<RealtimeSocket> connectNative(
  Uri url,
  Map<String, String> headers,
) async {
  final client = _NoRedirectClient(HttpClient());
  try {
    final socket =
        await WebSocket.connect(
          url.toString(),
          headers: headers,
          customClient: client,
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            client.close(force: true);
            throw TimeoutException('WebSocket handshake timed out');
          },
        );
    // The upgraded socket is detached from HttpClient by the SDK. Closing the
    // owned pool does not close that socket; its lifetime belongs to the caller.
    return _NativeSocket(socket);
  } finally {
    client.close(force: true);
  }
}

class _NativeSocket implements RealtimeSocket {
  _NativeSocket(this.socket);
  final WebSocket socket;
  @override
  Stream<dynamic> get messages => socket;
  @override
  void send(String message) => socket.add(message);
  @override
  Future<void> close() async {
    await socket.close();
  }
}
