import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/data/secure_store.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';

import 'api_models_test.dart' show config, FakeAuth, orderJson;

class MemoryStore implements AttemptStore {
  final values = <String, String>{};
  bool failWrite = false;
  Completer<String?>? readGate;
  @override
  Future<String?> read(String key) async =>
      readGate == null ? values[key] : await readGate!.future;
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('secret');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeRealtime extends RealtimeClient {
  FakeRealtime(FakeAuth auth) : super(config(), auth);
  int starts = 0, stops = 0;
  void Function()? invalidate, newOrder;
  @override
  void start({
    required void Function() onInvalidate,
    required void Function(RealtimeStatus) onStatus,
    required void Function() onNewOrder,
  }) {
    starts++;
    invalidate = onInvalidate;
    newOrder = onNewOrder;
  }

  @override
  void reconnect() {
    starts++;
  }

  @override
  void stop() {
    stops++;
  }

  @override
  void dispose() {
    stop();
  }
}

void main() {
  late FakeAuth auth;
  late MemoryStore store;
  late FakeRealtime rt;
  late CashierController c;
  late Future<http.Response> Function(http.Request) handler;
  setUp(() {
    auth = FakeAuth();
    store = MemoryStore();
    rt = FakeRealtime(auth);
    handler = (r) async => http.Response(jsonEncode([orderJson()]), 200);
    c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) => handler(r)),
      ),
      auth: auth,
      realtime: rt,
      store: store,
    );
  });
  tearDown(() {
    c.dispose();
    auth.events.close();
  });
  test(
    'authorization gates panel; logout clears PII and ignores late snapshots',
    () async {
      final pending = Completer<http.Response>();
      handler = (r) => pending.future;
      final init = c.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(c.signedIn, isFalse);
      await c.logout();
      pending.complete(http.Response(jsonEncode([orderJson()]), 200));
      await init;
      expect(c.signedIn, isFalse);
      expect(c.orders, isEmpty);
      expect(rt.starts, 0);
    },
  );
  test('invalid staff 401 never authorizes panel', () async {
    handler = (r) async => http.Response('{}', 401);
    await c.initialize();
    expect(c.signedIn, isFalse);
    expect(c.error, isNotNull);
    expect(rt.starts, 0);
  });
  test(
    'refresh is serialized with dirty trailing latest filter snapshot',
    () async {
      await c.initialize();
      final pending = Completer<http.Response>();
      var calls = 0;
      final paths = <Uri>[];
      handler = (r) {
        paths.add(r.url);
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(http.Response('[]', 200));
      };
      final first = c.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = c.changeTab('history');
      final third = c.refresh();
      expect(calls, 1);
      pending.complete(http.Response(jsonEncode([orderJson()]), 200));
      await Future.wait([first, second, third]);
      expect(calls, 2);
      expect(paths.last.queryParameters['tab'], 'history');
      expect(c.orders, isEmpty);
      expect(c.loading, isFalse);
    },
  );
  test('pending is saved before POST; uncertainty retries exact payload across relaunch and user scope', () async {
    await c.initialize();
    final posts = <http.Request>[];
    handler = (r) async {
      if (r.method == 'GET') return http.Response('[]', 200);
      expect(store.values, isNotEmpty);
      posts.add(r);
      return http.Response('{}', 503);
    };
    final draft = ReorderDraft(
      customerName: 'A',
      items: [OrderDraftLine(productId: 'p', notes: 'unchanged')],
    );
    expect(await c.submitReorder(draft), isNull);
    expect(c.hasPendingAttempt, isTrue);
    final saved = store.values.values.single;
    expect(await c.submitReorder(draft), isNull);
    expect(posts.length, 1);
    await c.logout();
    expect(store.values.values.single, saved);
    expect(c.hasPendingAttempt, isFalse);
    await c.login('bob', 'pw');
    expect(c.hasPendingAttempt, isFalse);
    await c.logout();
    await c.login('alice', 'pw');
    expect(c.hasPendingAttempt, isTrue);
    await c.retryPending();
    expect(posts.length, 2);
    expect(posts[1].body, posts[0].body);
    expect(
      posts[1].headers['Idempotency-Key'],
      posts[0].headers['Idempotency-Key'],
    );
    expect(
      posts[1].headers['X-Order-Token'],
      posts[0].headers['X-Order-Token'],
    );
    handler = (r) async => http.Response(
      jsonEncode(r.method == 'POST' ? orderJson() : []),
      r.method == 'POST' ? 201 : 200,
    );
    expect(await c.retryPending(), isNotNull);
    expect(c.hasPendingAttempt, isFalse);
    expect(store.values, isEmpty);
  });
  test('only definitive 409 checkout_rejected clears saved attempt', () async {
    await c.initialize();
    var status = 409;
    var code = 'idempotency_conflict';
    handler = (r) async =>
        http.Response(jsonEncode({'error': 'sensitive', 'code': code}), status);
    final draft = ReorderDraft(
      customerName: 'A',
      items: [OrderDraftLine(productId: 'p')],
    );
    await c.submitReorder(draft);
    expect(c.hasPendingAttempt, isTrue);
    status = 400;
    code = 'checkout_rejected';
    await c.retryPending();
    expect(c.hasPendingAttempt, isTrue);
    status = 409;
    await c.retryPending();
    expect(c.hasPendingAttempt, isFalse);
    expect(store.values, isEmpty);
  });
  test('storage write failure prevents network and safe error', () async {
    await c.initialize();
    store.failWrite = true;
    var posts = 0;
    handler = (r) async {
      posts++;
      return http.Response('{}', 500);
    };
    await c.submitReorder(
      ReorderDraft(
        customerName: 'A',
        items: [OrderDraftLine(productId: 'p')],
      ),
    );
    expect(posts, 0);
    expect(c.error, isNot(contains('secret')));
  });
  test('mutations guard reviewed state and duplicate taps; background suppresses sound', () async {
    await c.initialize();
    var calls = 0;
    final pending = Completer<http.Response>();
    handler = (r) {
      calls++;
      return pending.future;
    };
    expect(
      await c.pay(OrderRecord.fromJson(orderJson(reviewed: 1)), 20000),
      isNull,
    );
    expect(calls, 0);
    final first = c.pay(c.orders.first, 20000);
    await Future<void>.delayed(Duration.zero);
    expect(await c.pay(c.orders.first, 20000), isNull);
    expect(calls, 1);
    c.setForeground(false);
    rt.newOrder?.call();
    expect(c.newOrderSerial, 0);
    handler = (r) async => http.Response('[]', 200);
    pending.complete(
      http.Response(
        jsonEncode(orderJson(status: 'confirmed', payment: 'paid')),
        200,
      ),
    );
    await first;
    expect(c.busy, isFalse);
  });
  test('auth switch during pending storage read cannot reveal previous user attempt', () async {
    final gate = Completer<String?>();
    store.readGate = gate;
    final init = c.initialize();
    await Future<void>.delayed(Duration.zero);
    await c.logout();
    gate.complete(null);
    await init;
    expect(c.signedIn, isFalse);
    expect(c.hasPendingAttempt, isFalse);
    expect(c.orders, isEmpty);
  });
}
