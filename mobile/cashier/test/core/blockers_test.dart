import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cashier/core/realtime_transport.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';

import 'api_models_test.dart' show config, FakeAuth, orderJson;
import 'controller_test.dart' show MemoryStore, FakeRealtime;

class RealHttpOverrides extends HttpOverrides {}

class HungAuth extends FakeAuth {
  final gate = Completer<String?>();
  bool hung = true;
  @override
  Future<String?> accessToken() => hung ? gate.future : super.accessToken();
}

void main() {
  test(
    'native WebSocket rejects redirects before contacting destination',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var destinationCalls = 0;
      destination.listen((request) async {
        destinationCalls++;
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        await socket.close();
      });
      origin.listen((request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${destination.port}/ws',
        );
        await request.response.close();
      });
      try {
        RealtimeSocket? socket;
        Object? failure;
        try {
          socket = await connectNative(
            Uri.parse('ws://127.0.0.1:${origin.port}/ws'),
            {},
          );
        } catch (e) {
          failure = e;
        } finally {
          await socket?.close();
        }
        expect(destinationCalls, 0);
        expect(failure, isA<WebSocketException>());
      } finally {
        await origin.close(force: true);
        await destination.close(force: true);
      }
    }, RealHttpOverrides()),
  );

  test('newer unpaid version releases stale cash intent and excessive cash never sends', () async {
    final auth = FakeAuth(), store = MemoryStore();
    var version = 2, posts = 0;
    final c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            version = 3;
            return http.Response('{}', 409);
          }
          return http.Response(
            jsonEncode([orderJson(version: version, reviewed: version)]),
            200,
          );
        }),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: store,
    );
    await c.initialize();
    await c.pay(c.orders.single, 1000000000001);
    expect(posts, 0);
    await c.pay(c.orders.single, 15000);
    expect(posts, 1);
    await c.pay(c.orders.single, 16000);
    expect(posts, 2);
    c.dispose();
    await auth.events.close();
  });

  test(
    'authorization denial invalidates an outstanding successful snapshot',
    () async {
      final auth = FakeAuth(), store = MemoryStore();
      final rt = FakeRealtime(auth);
      final gate = Completer<http.Response>();
      var hold = false;
      final c = CashierController(
        api: CashierApi(
          config: config(),
          auth: auth,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/menu')) return http.Response('{}', 403);
            return hold
                ? gate.future
                : http.Response(jsonEncode([orderJson()]), 200);
          }),
        ),
        auth: auth,
        realtime: rt,
        store: store,
      );
      await c.initialize();
      hold = true;
      final refresh = c.refresh();
      await Future<void>.delayed(Duration.zero);
      await expectLater(c.menu(), throwsA(isA<ApiException>()));
      gate.complete(http.Response(jsonEncode([orderJson()]), 200));
      await refresh;
      expect(c.signedIn, isFalse);
      expect(c.orders, isEmpty);
      expect(rt.starts, 1);
      c.dispose();
      await auth.events.close();
    },
  );

  test(
    'uncertain cash reconciles and freezes identity across relaunch',
    () async {
      final auth = FakeAuth(), store = MemoryStore();
      final posts = <String>[];
      var gets = 0;
      var paid = false;
      CashierController create() => CashierController(
        api: CashierApi(
          config: config(),
          auth: auth,
          client: MockClient((r) async {
            if (r.method == 'POST') {
              posts.add(r.body);
              expect(
                store.values,
                isNotEmpty,
                reason: 'durable intent before POST',
              );
              return http.Response('unreadable', 200);
            }
            gets++;
            return http.Response(
              jsonEncode([
                paid
                    ? orderJson(
                        status: 'confirmed',
                        payment: 'paid',
                        version: 3,
                      )
                    : orderJson(),
              ]),
              200,
            );
          }),
        ),
        auth: auth,
        realtime: FakeRealtime(auth),
        store: store,
      );
      var c = create();
      await c.initialize();
      final order = c.orders.single;
      final initialGets = gets;
      await c.pay(order, 15000);
      expect(
        gets,
        greaterThan(initialGets),
        reason: 'reconcile uncertainty immediately',
      );
      await c.pay(order, 16000);
      await c.pay(
        OrderRecord.fromJson(orderJson(version: 3, reviewed: 3)),
        15000,
      );
      expect(posts.length, 1);
      c.dispose();
      c = create();
      await c.initialize();
      await c.pay(order, 16000);
      expect(posts.length, 1, reason: 'relaunch cannot change identity');
      await c.pay(order, 15000);
      expect(posts.length, 2);
      expect(posts[1], posts[0]);
      paid = true;
      await c.refresh();
      await c.pay(order, 16000);
      expect(
        posts.length,
        2,
        reason: 'stale unpaid object cannot pay resolved cash',
      );
      expect(c.orders.single.paymentStatus, 'paid');
      c.dispose();
      await auth.events.close();
    },
  );

  testWidgets('token acquisition is bounded and late token never sends HTTP', (
    tester,
  ) async {
    final auth = HungAuth();
    var requests = 0;
    final api = CashierApi(
      config: config(),
      auth: auth,
      client: MockClient((r) async {
        requests++;
        return http.Response('[]', 200);
      }),
    );
    var finished = false;
    final result = api.listOrders().then(
      (_) {
        finished = true;
      },
      onError: (Object _) {
        finished = true;
      },
    );
    await tester.pump(const Duration(seconds: 16));
    expect(finished, isTrue);
    auth.gate.complete('late');
    await tester.pump();
    await result;
    expect(requests, 0);
    api.close();
    await auth.events.close();
  });

  testWidgets('new session detaches old hung controller refresh', (
    tester,
  ) async {
    final auth = HungAuth();
    final c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient(
          (r) async => http.Response(jsonEncode([orderJson()]), 200),
        ),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: MemoryStore(),
    );
    final old = c.initialize();
    await tester.pump();
    await c.logout();
    auth.hung = false;
    var done = false;
    final login = c.login('bob', 'pw').then((_) {
      done = true;
    });
    await tester.pump();
    expect(done, isTrue);
    expect(c.signedIn, isTrue);
    auth.gate.complete('obsolete');
    await tester.pump();
    await Future.wait([old, login]);
    c.dispose();
    await auth.events.close();
  });
}
