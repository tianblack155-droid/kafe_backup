import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import '../data/auth_session.dart';
import 'app_config.dart';
import 'realtime_transport.dart';
export 'realtime_transport.dart' show RealtimeSocket, RealtimeConnector;

enum RealtimeStatus { connecting, connected, polling, stopped }

class RealtimeClient {
  RealtimeClient(this.config, this.auth, {RealtimeConnector? connector})
    : _connect = connector ?? connectNative;
  final AppConfig config;
  final AuthSession auth;
  final RealtimeConnector _connect;
  final Random _random = Random();
  final LinkedHashMap<String, int> _versions = LinkedHashMap();
  final LinkedHashSet<String> _events = LinkedHashSet();
  RealtimeSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<void>? _authSubscription;
  Timer? _deadline, _retry, _poll, _expiry;
  void Function()? _invalidate, _newOrder;
  void Function(RealtimeStatus)? _status;
  bool _running = false, _disposed = false, _ready = false;
  int _generation = 0, _failures = 0;
  String? _user;
  void start({
    required void Function() onInvalidate,
    required void Function(RealtimeStatus) onStatus,
    required void Function() onNewOrder,
  }) {
    if (_disposed) return;
    _invalidate = onInvalidate;
    _status = onStatus;
    _newOrder = onNewOrder;
    if (_running) return;
    _running = true;
    _user = auth.userId;
    _authSubscription = auth.changes.listen(
      (_) {
        if (auth.userId != _user) {
          stop();
          return;
        }
        reconnect();
      },
      onError: (Object _) {
        reconnect();
      },
    );
    _setPolling(const Duration(seconds: 10));
    _open();
  }

  bool _current(int g) =>
      _running && !_disposed && g == _generation && auth.userId == _user;
  Future<void> _open() async {
    final g = ++_generation;
    _ready = false;
    _status?.call(RealtimeStatus.connecting);
    // This deadline includes token acquisition and native connection setup.
    _deadline = Timer(const Duration(seconds: 8), () => _failed(g));
    try {
      final token = await auth.accessToken();
      if (!_current(g)) return;
      if (token == null || token.isEmpty) {
        _failed(g);
        return;
      }
      final socket = await _connect(config.wsUrl, {'Origin': config.wsOrigin});
      if (!_current(g)) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _subscription = socket.messages.listen(
        (frame) => _frame(g, frame),
        onError: (Object _) => _failed(g),
        onDone: () => _failed(g),
      );
      socket.send(
        jsonEncode({
          'type': 'subscribe',
          'channel': 'cashier',
          'access_token': token,
        }),
      );
      _scheduleExpiry(g, token);
    } catch (_) {
      _failed(g);
    }
  }

  void _scheduleExpiry(int g, String token) {
    var delay = const Duration(minutes: 4);
    try {
      final parts = token.split('.');
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      final seconds = claims['exp'] as int;
      delay = DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          .subtract(const Duration(seconds: 45))
          .difference(DateTime.now());
      if (delay < const Duration(seconds: 1)) {
        delay = const Duration(seconds: 1);
      }
    } catch (_) {}
    _expiry = Timer(delay, () {
      if (_current(g)) reconnect();
    });
  }

  void _frame(int g, dynamic frame) {
    if (!_current(g)) return;
    if (frame is! String || frame.length > 16384) {
      _failed(g);
      return;
    }
    try {
      final data = jsonDecode(frame);
      if (data is! Map) return;
      if (data['type'] == 'ready' && !_ready) {
        _ready = true;
        _failures = 0;
        _deadline?.cancel();
        _status?.call(RealtimeStatus.connected);
        _setPolling(const Duration(seconds: 30));
        _invalidate?.call();
        return;
      }
      if (!_ready || data['type'] != 'order.changed') return;
      final id = data['order_id'],
          event = data['event_id'],
          version = data['version'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 128 ||
          event is! String ||
          event.isEmpty ||
          event.length > 128 ||
          version is! int ||
          version < 1) {
        return;
      }
      if (_events.contains(event) || (_versions[id] ?? 0) >= version) return;
      _events.add(event);
      _versions.remove(id);
      _versions[id] = version;
      if (_events.length > 256) _events.remove(_events.first);
      if (_versions.length > 256) _versions.remove(_versions.keys.first);
      _invalidate?.call();
      if (data['event_type'] == 'ORDER_CREATED') _newOrder?.call();
    } catch (_) {
      /* Malformed bounded messages are not snapshots. */
    }
  }

  void _setPolling(Duration duration) {
    _poll?.cancel();
    _poll = Timer.periodic(duration, (_) {
      if (_running) _invalidate?.call();
    });
  }

  void _failed(int g) {
    if (!_current(g)) return;
    ++_generation;
    _closeSocket();
    _status?.call(RealtimeStatus.polling);
    // Keep an existing fallback timer: reconnect failures must not postpone it.
    if (_ready) _setPolling(const Duration(seconds: 10));
    _ready = false;
    final ceiling = min(30000, 1000 * (1 << min(_failures++, 5)));
    _retry = Timer(
      Duration(milliseconds: ceiling ~/ 2 + _random.nextInt(ceiling ~/ 2 + 1)),
      () {
        if (_running) _open();
      },
    );
  }

  void _closeSocket() {
    _deadline?.cancel();
    _expiry?.cancel();
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close().catchError((Object _) {}));
  }

  void reconnect() {
    if (!_running || _disposed) return;
    ++_generation;
    _closeSocket();
    if (_ready) _setPolling(const Duration(seconds: 10));
    _open();
  }

  void stop() {
    _running = false;
    ++_generation;
    _closeSocket();
    _poll?.cancel();
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    _versions.clear();
    _events.clear();
    _ready = false;
    _failures = 0;
    _status?.call(RealtimeStatus.stopped);
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    _invalidate = null;
    _newOrder = null;
    _status = null;
  }
}
