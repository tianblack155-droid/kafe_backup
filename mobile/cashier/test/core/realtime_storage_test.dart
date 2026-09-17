import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/data/secure_store.dart';

import 'api_models_test.dart' show config, FakeAuth;

class FakeSocket implements RealtimeSocket {
  final frames = StreamController<dynamic>.broadcast(sync: true);
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<dynamic> get messages => frames.stream;
  @override
  void send(String message) {
    sent.add(message);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('secure session storage preserves full refresh session and never uses preferences', () async {
    final values = <String, String>{};
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            methods.add(call.method);
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final key = args['key'] as String;
            switch (call.method) {
              case 'read':
                return values[key];
              case 'write':
                values[key] = args['value'] as String;
                return null;
              case 'delete':
                values.remove(key);
                return null;
              default:
                throw StateError(call.method);
            }
          },
        );
    final storage = SecureSessionStorage();
    await storage.initialize();
    const session =
        '{"access_token":"a","refresh_token":"r","user":{"id":"u"}}';
    await storage.persistSession(session);
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), session);
    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(methods, containsAll(['write', 'read', 'delete']));
  });
  test('ready handshake, explicit Origin, fresh dedup and connected reconciliation', () {
    fakeAsync((clock) {
      final auth = FakeAuth();
      final socket = FakeSocket();
      var invalidates = 0;
      var sounds = 0;
      final statuses = <RealtimeStatus>[];
      final rt = RealtimeClient(
        config(),
        auth,
        connector: (url, headers) async {
          expect(url, config().wsUrl);
          expect(headers['Origin'], 'https://example.test');
          return socket;
        },
      );
      rt.start(
        onInvalidate: () => invalidates++,
        onStatus: statuses.add,
        onNewOrder: () => sounds++,
      );
      clock.flushMicrotasks();
      expect(jsonDecode(socket.sent.single), {
        'type': 'subscribe',
        'channel': 'cashier',
        'access_token': 'token',
      });
      expect(statuses.last, RealtimeStatus.connecting);
      socket.frames.add('{"type":"ready"}');
      expect(statuses.last, RealtimeStatus.connected);
      expect(invalidates, 1);
      expect(sounds, 0);
      final frame = {
        'type': 'order.changed',
        'event_id': 'e',
        'order_id': 'o',
        'version': 1,
        'event_type': 'ORDER_CREATED',
      };
      socket.frames.add(jsonEncode(frame));
      socket.frames.add(jsonEncode(frame));
      socket.frames.add(jsonEncode({...frame, 'event_id': 'e2'}));
      expect(invalidates, 2);
      expect(sounds, 1);
      clock.elapse(const Duration(seconds: 30));
      expect(invalidates, 3);
      rt.stop();
      clock.elapse(const Duration(seconds: 60));
      expect(invalidates, 3);
      expect(socket.closed, isTrue);
      expect(statuses.last, RealtimeStatus.stopped);
      rt.dispose();
      auth.events.close();
    });
  });
  test('ready deadline falls back; malformed binary is bounded; stopped late connect closes', () {
    fakeAsync((clock) {
      final auth = FakeAuth();
      final socket = FakeSocket();
      var connects = 0;
      var invalidates = 0;
      final statuses = <RealtimeStatus>[];
      final rt = RealtimeClient(
        config(),
        auth,
        connector: (url, headers) async {
          connects++;
          return socket;
        },
      );
      rt.start(
        onInvalidate: () => invalidates++,
        onStatus: statuses.add,
        onNewOrder: () {},
      );
      clock.flushMicrotasks();
      socket.frames.add([255]);
      socket.frames.add('not json');
      clock.elapse(const Duration(seconds: 8));
      expect(statuses, contains(RealtimeStatus.polling));
      expect(socket.closed, isTrue);
      clock.elapse(const Duration(seconds: 10));
      expect(invalidates, greaterThanOrEqualTo(1));
      expect(connects, greaterThan(1));
      rt.dispose();
      auth.events.close();
      final late = Completer<RealtimeSocket>();
      final other = FakeSocket();
      final rt2 = RealtimeClient(
        config(),
        FakeAuth(),
        connector: (u, h) => late.future,
      );
      rt2.start(onInvalidate: () {}, onStatus: (_) {}, onNewOrder: () {});
      clock.flushMicrotasks();
      rt2.stop();
      late.complete(other);
      clock.flushMicrotasks();
      expect(other.closed, isTrue);
      rt2.dispose();
    });
  });
}
