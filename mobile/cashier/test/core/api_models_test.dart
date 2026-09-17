import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cashier/core/app_config.dart';
import 'package:cashier/data/auth_session.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';

AppConfig config({
  String key = 'sb_publishable_test',
  String base = 'https://example.test/api/core/',
}) => AppConfig(
  apiBase: Uri.parse(base),
  wsUrl: Uri.parse('wss://example.test/ws'),
  wsOrigin: 'https://example.test',
  supabaseUrl: 'https://auth.test',
  supabaseKey: key,
);

class FakeAuth implements AuthSession {
  String? id = 'alice';
  String? token = 'token';
  final events = StreamController<void>.broadcast(sync: true);
  @override
  String? get userId => id;
  @override
  Future<String?> accessToken() async => token;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<void> signIn(String email, String password) async {
    id = email;
    events.add(null);
  }

  @override
  Future<void> signOut() async {
    id = null;
    events.add(null);
  }
}

Map<String, dynamic> orderJson({
  String id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  String status = 'pending',
  String payment = 'unpaid',
  int version = 2,
  int? reviewed = 2,
}) => {
  'id': id,
  'order_number': 'TKM-1',
  'customer_name': 'A',
  'status': status,
  'payment_status': payment,
  'version': version,
  'reviewed_version': reviewed,
  'total': 12500,
  'expires_at': '2099-01-01T00:00:00Z',
  // tkm.order_json (0005_shared_qr_checkout.sql), not checkout's items.
  'tables': null,
  'order_items': [
    {
      'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'order_item_addons': [
        {'addon_id': 'a', 'addon_name': 'Milk', 'price': 0},
      ],
      'product_id': 'p',
      'product_name': 'Coffee',
      'quantity': 2,
      'unit_price': 6000,
      'subtotal': 12000,
      'variant_ids': ['v'],
      'addon_ids': ['a'],
      'notes': 'hot',
    },
  ],
};
void main() {
  test('config rejects unsafe endpoints and privileged keys without leaking values', () {
    for (final base in [
      'http://example.test/',
      'https://u:secret@example.test/',
      'https://example.test/?secret=x',
      'https://example.test/#x',
    ]) {
      expect(() => config(base: base), throwsFormatException);
    }
    for (final key in [
      'sb_secret_secret',
      'e30.${base64Url.encode(utf8.encode('{"role":"service_role"}')).replaceAll('=', '')}.sig',
      '',
    ]) {
      expect(() => config(key: key), throwsFormatException);
    }
    expect(config().apiBase.path, '/api/core/');
  });
  test(
    'models retain choices, backend totals, strict payment and expiry guards',
    () {
      final o = OrderRecord.fromJson(orderJson());
      expect(o.total, 12500);
      expect(o.canPay(DateTime.utc(2026)), isTrue);
      expect(o.canPay(DateTime.utc(2099)), isFalse);
      expect(
        OrderRecord.fromJson(orderJson(reviewed: 1)).canPay(DateTime.utc(2026)),
        isFalse,
      );
      expect(
        OrderRecord.fromJson(orderJson(status: 'confirmed', payment: 'paid'))
            .canComplete,
        isTrue,
      );
      expect(o.items.single.toDraft().toJson(), {
        'product_id': 'p',
        'quantity': 2,
        'variant_ids': ['v'],
        'addon_ids': ['a'],
        'notes': 'hot',
      });
      final draft = ReorderDraft.fromJson({
        'customer_name': 'A',
        'payment_method': 'cash',
        'items': [o.items.single.toDraft().toJson()],
      });
      expect(draft.toJson().containsKey('table_token'), isFalse);
      expect(draft.toJson()['payment_method'], 'cash');
      expect(() => o.items.add(o.items.first), throwsUnsupportedError);
    },
  );
  test('menu uses actual backend settings and availability fields', () {
    final menu = Catalog.fromJson({
      'settings': {'require_customer_name': true},
      'products': [
        {
          'id': 'p',
          'name': 'Coffee',
          'price': 100,
          'is_available': false,
          'variants': [
            {
              'id': 'v',
              'name': 'L',
              'group_name': 'Size',
              'price_modifier': 20,
              'is_available': true,
            },
          ],
          'addons': [
            {'id': 'a', 'name': 'Milk', 'price': 30, 'is_available': false},
          ],
        },
      ],
    });
    expect(menu.requireCustomerName, isTrue);
    expect(menu.products.single.available, isFalse);
    expect(menu.products.single.variants.single.groupName, 'Size');
    expect(menu.products.single.addons.single.price, 30);
  });
  test('API exact routing, auth, integer payload and no POST retry', () async {
    final requests = <http.Request>[];
    final api = CashierApi(
      config: config(),
      auth: FakeAuth(),
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('admin/orders') ? [orderJson()] : orderJson(),
          ),
          200,
        );
      }),
    );
    await api.listOrders(tab: 'history', expiredOnly: true, offset: 100);
    expect(
      requests.last.url.toString(),
      'https://example.test/api/core/admin/orders?tab=history&status=expired&offset=100',
    );
    expect(requests.last.headers['Authorization'], 'Bearer token');
    await api.confirmCash(orderJson()['id'], 2, 15000);
    expect(jsonDecode(requests.last.body), {
      'expected_version': 2,
      'received_rp': 15000,
    });
    await api.complete(orderJson()['id']);
    expect(requests.last.body, '{}');
    expect(() => api.complete('../escape'), throwsA(isA<ApiException>()));
    expect(requests.length, 3);
    api.close();
  });
  test(
    'API preserves uncertain conflicts and respects Retry-After without replay',
    () async {
      var calls = 0;
      final api = CashierApi(
        config: config(),
        auth: FakeAuth(),
        client: MockClient((r) async {
          calls++;
          return http.Response(
            '{"error":"secret backend text","code":"checkout_rejected"}',
            429,
            headers: {'retry-after': '60'},
          );
        }),
      );
      final draft = ReorderDraft(
        customerName: 'A',
        items: [OrderDraftLine(productId: 'p')],
      );
      try {
        await api.createOrder(
          draft,
          '1234567890123456',
          '123456789012345678901234',
        );
        fail('must fail');
      } on ApiException catch (e) {
        expect(e.status, 429);
        expect(e.checkoutRejected, isFalse);
        expect(e.toString(), isNot(contains('secret backend text')));
      }
      await expectLater(api.listOrders(), throwsA(isA<ApiException>()));
      expect(calls, 1);
      api.close();
    },
  );
}
