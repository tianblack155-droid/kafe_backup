import 'dart:async';
import 'dart:convert';

import '../core/app_config.dart';
import '../core/realtime_client.dart';
import '../data/auth_session.dart';
import '../data/cashier_api.dart';
import '../data/secure_store.dart';
import '../domain/models.dart';
import '../features/cashier/cashier_controller.dart';

// ponytail: volatile, single-device UI simulator; use Go + Auth for integration QA.
CashierController createDemoController() {
  final auth = DemoAuth();
  final api = DemoApi(auth);
  return CashierController(
    api: api,
    auth: auth,
    realtime: _DemoRealtime(api.config, auth),
    store: _MemoryStore(),
  );
}

class DemoAuth implements AuthSession {
  String? _user = 'demo';
  @override
  String? get userId => _user;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<void> signIn(String email, String password) async {
    _user = 'demo';
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }
}

class _MemoryStore implements AttemptStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _DemoRealtime extends RealtimeClient {
  _DemoRealtime(super.config, super.auth);
  @override
  void start({
    required void Function() onInvalidate,
    required void Function(RealtimeStatus) onStatus,
    required void Function() onNewOrder,
  }) => onStatus(RealtimeStatus.stopped);
  @override
  void reconnect() {}
}

class DemoApi extends CashierApi {
  DemoApi(AuthSession auth)
    : super(
        auth: auth,
        config: AppConfig(
          apiBase: Uri.parse('https://demo.invalid/api/core/'),
          wsUrl: Uri.parse('wss://demo.invalid/ws'),
          wsOrigin: 'https://demo.invalid',
          supabaseUrl: 'https://demo.invalid',
          supabaseKey: 'sb_publishable_demo',
        ),
      ) {
    _add('Dina', [
      OrderDraftLine(productId: 'coffee', variantIds: ['iced']),
    ]);
    _add('Budi', [
      OrderDraftLine(productId: 'toast', quantity: 2),
    ]).addAll({'status': 'confirmed', 'payment_status': 'paid', 'version': 3});
    _add('Sari', [OrderDraftLine(productId: 'tea')]).addAll({
      'status': 'expired',
      'expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
  }
  final _orders = <Map<String, dynamic>>[];
  final _attempts = <String, ({String payload, String token, String id})>{};
  final _payments = <String, ({int version, int received})>{};
  final _catalog = Catalog.fromJson({
    'settings': {'require_customer_name': true},
    'products': [
      {
        'id': 'coffee',
        'name': 'Kopi Susu',
        'price': 18000,
        'is_available': true,
        'variants': [
          {
            'id': 'hot',
            'name': 'Panas',
            'group_name': 'Suhu',
            'price_modifier': 0,
            'is_available': true,
          },
          {
            'id': 'iced',
            'name': 'Dingin',
            'group_name': 'Suhu',
            'price_modifier': 2000,
            'is_available': true,
          },
        ],
        'addons': [
          {
            'id': 'shot',
            'name': 'Extra shot',
            'price': 5000,
            'is_available': true,
          },
        ],
      },
      {
        'id': 'tea',
        'name': 'Es Teh Manis',
        'price': 5000,
        'is_available': true,
      },
      {
        'id': 'toast',
        'name': 'Roti Bakar Cokelat',
        'price': 15000,
        'is_available': true,
      },
      {
        'id': 'sold-out',
        'name': 'Kentang Goreng (Habis)',
        'price': 12000,
        'is_available': false,
      },
    ],
  });

  Never _conflict() => throw const ApiException(
    'Data demo berubah atau input tidak valid.',
    status: 409,
  );
  Map<String, dynamic> _find(String id) =>
      _orders.firstWhere((o) => o['id'] == id);
  OrderRecord _snapshot(Map<String, dynamic> order) =>
      OrderRecord.fromJson(order);

  List<Map<String, dynamic>> _price(List<OrderDraftLine> items) {
    if (items.isEmpty || items.length > 50) _conflict();
    return items.map((line) {
      final p = _catalog.products
          .where((p) => p.id == line.productId)
          .firstOrNull;
      if (p == null ||
          !p.available ||
          line.quantity < 1 ||
          line.quantity > 50 ||
          line.variantIds.length > 20 ||
          line.addonIds.length > 20) {
        _conflict();
      }
      final variants = p.variants
          .where((v) => line.variantIds.contains(v.id))
          .toList();
      final addons = p.addons
          .where((a) => line.addonIds.contains(a.id))
          .toList();
      final groups = variants.map((v) => v.groupName).toSet();
      if (variants.length != line.variantIds.length ||
          addons.length != line.addonIds.length ||
          groups.length != variants.length ||
          variants.any((v) => !v.available) ||
          addons.any((a) => !a.available) ||
          p.variants.any((v) => v.available && !groups.contains(v.groupName))) {
        _conflict();
      }
      final unit =
          p.price + variants.fold(0, (sum, v) => sum + v.priceModifier);
      final extra = addons.fold(0, (sum, a) => sum + a.price);
      return <String, dynamic>{
        ...line.toJson(),
        'product_name': p.name,
        'variant_name': variants.map((v) => v.name).join(' · '),
        'unit_price': unit,
        'subtotal': (unit + extra) * line.quantity,
        'order_item_addons': addons.map((a) => {'addon_name': a.name}).toList(),
        'notes': String.fromCharCodes(line.notes.runes.take(200)),
      };
    }).toList();
  }

  Map<String, dynamic> _add(String name, List<OrderDraftLine> items) {
    if (name.trim().isEmpty) _conflict();
    final priced = _price(items), number = _orders.length + 1;
    final order = <String, dynamic>{
      'id': '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
      'order_number': 'DEMO-A$number',
      'customer_name': name,
      'status': 'pending',
      'payment_status': 'unpaid',
      'version': 1,
      'reviewed_version': null,
      'expires_at': DateTime.now()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'total': priced.fold<int>(0, (sum, i) => sum + (i['subtotal'] as int)),
      'order_items': priced,
    };
    _orders.insert(0, order);
    return order;
  }

  @override
  Future<Catalog> menu() async => _catalog;
  @override
  Future<List<OrderRecord>> listOrders({
    String tab = 'active',
    bool expiredOnly = false,
    int offset = 0,
  }) async {
    for (final o in _orders) {
      if (o['status'] == 'pending' && _snapshot(o).isExpired) {
        o['status'] = 'expired';
        o['version'] = (o['version'] as int) + 1;
      }
    }
    return _orders
        .where((o) {
          final active = ['pending', 'confirmed'].contains(o['status']);
          return (tab == 'active' ? active : !active) &&
              (!expiredOnly || o['status'] == 'expired');
        })
        .skip(offset)
        .take(100)
        .map(_snapshot)
        .toList();
  }

  @override
  Future<OrderRecord> review(
    String id,
    int version,
    List<OrderDraftLine> items,
  ) async {
    final o = _find(id);
    if (!_snapshot(o).canReview(DateTime.now()) || o['version'] != version) {
      _conflict();
    }
    final priced = _price(items);
    o.addAll({
      'order_items': priced,
      'version': version + 1,
      'reviewed_version': version + 1,
      'total': priced.fold<int>(0, (sum, i) => sum + (i['subtotal'] as int)),
    });
    return _snapshot(o);
  }

  @override
  Future<OrderRecord> confirmCash(String id, int version, int received) async {
    final o = _find(id), previous = _payments[id];
    if (previous != null) {
      if (previous.version != version || previous.received != received) {
        _conflict();
      }
      return _snapshot(o);
    }
    if (!_snapshot(o).canPay(DateTime.now()) ||
        o['version'] != version ||
        received < (o['total'] as int) ||
        received > 1000000000000) {
      _conflict();
    }
    _payments[id] = (version: version, received: received);
    o.addAll({
      'status': 'confirmed',
      'payment_status': 'paid',
      'version': version + 1,
    });
    return _snapshot(o);
  }

  @override
  Future<OrderRecord> complete(String id) async {
    final o = _find(id);
    if (o['status'] == 'completed') return _snapshot(o);
    if (!_snapshot(o).canComplete) _conflict();
    o.addAll({'status': 'completed', 'version': (o['version'] as int) + 1});
    return _snapshot(o);
  }

  @override
  Future<ReorderDraft> reorder(String id) async {
    final o = _snapshot(_find(id));
    if (!o.isExpired) _conflict();
    return ReorderDraft(
      customerName: o.customerName,
      items: o.items.map((i) => i.toDraft()).toList(),
    );
  }

  @override
  Future<OrderRecord> createOrder(
    ReorderDraft draft,
    String key,
    String orderToken,
  ) async {
    final payload = jsonEncode(draft.toJson()), previous = _attempts[key];
    if (previous != null) {
      if (previous.payload != payload || previous.token != orderToken) {
        _conflict();
      }
      return _snapshot(_find(previous.id));
    }
    final o = _add(draft.customerName, draft.items);
    _attempts[key] = (
      payload: payload,
      token: orderToken,
      id: o['id'] as String,
    );
    return _snapshot(o);
  }
}
