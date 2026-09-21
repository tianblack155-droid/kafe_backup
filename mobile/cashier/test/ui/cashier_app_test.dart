import 'package:cashier/data/cash_attempt.dart';
import 'package:cashier/app.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

OrderRecord order({
  bool reviewed = false,
  bool expired = false,
  bool paid = false,
}) => OrderRecord.fromJson({
  'id': 'order-1',
  'order_number': 'TKM-123',
  'customer_name': 'Sari',
  'status': expired
      ? 'expired'
      : paid
      ? 'confirmed'
      : 'pending',
  'payment_status': paid ? 'paid' : 'unpaid',
  'version': 2,
  'reviewed_version': reviewed ? 2 : null,
  'total': 25000,
  'expires_at': DateTime.now()
      .add(Duration(hours: expired ? -1 : 1))
      .toUtc()
      .toIso8601String(),
  'order_items': [
    {
      'product_id': 'coffee',
      'product_name': 'Kopi',
      'quantity': 1,
      'unit_price': 25000,
      'subtotal': 25000,
      'variant_ids': <String>[],
      'addon_ids': <String>[],
      'notes': '',
    },
  ],
});

Catalog catalog() => Catalog.fromJson({
  'settings': {'require_customer_name': true},
  'products': [
    {
      'id': 'coffee',
      'name': 'Kopi',
      'price': 25000,
      'is_available': true,
      'variants': [
        {
          'id': 'hot',
          'name': 'Panas',
          'group_name': 'Suhu',
          'price_modifier': 0,
          'is_available': true,
        },
      ],
      'addons': [
        {'id': 'milk', 'name': 'Susu', 'price': 3000, 'is_available': true},
      ],
    },
    {
      'id': 'tea',
      'name': 'Teh',
      'price': 10000,
      'is_available': true,
      'variants': [],
      'addons': [],
    },
  ],
});

class FakeController extends ChangeNotifier implements CashierController {
  @override
  bool signedIn = true;
  @override
  bool busy = false;
  @override
  bool loading = false;
  @override
  String? error;
  @override
  List<OrderRecord> orders = [order()];
  @override
  String tab = 'active';
  @override
  bool expiredOnly = false;
  @override
  int offset = 0;
  @override
  RealtimeStatus realtimeStatus = RealtimeStatus.connected;
  @override
  int newOrderSerial = 0;
  @override
  bool hasPendingAttempt = false;
  int initializes = 0,
      menus = 0,
      pays = 0,
      completes = 0,
      submits = 0,
      retries = 0,
      refreshes = 0;
  String? email, password;
  int? received;
  List<OrderDraftLine>? reviewedItems;
  final foreground = <bool>[];
  void emit() => notifyListeners();
  @override
  Future<void> initialize() async {
    initializes++;
  }

  @override
  Future<void> login(String email, String password) async {
    this.email = email;
    this.password = password;
    signedIn = true;
    emit();
  }

  @override
  Future<void> logout() async {
    signedIn = false;
    emit();
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    emit();
  }

  @override
  Future<void> changeTab(String value) async {
    tab = value;
    offset = 0;
    expiredOnly = false;
    emit();
  }

  @override
  Future<void> setExpiredOnly(bool value) async {
    expiredOnly = value;
    offset = 0;
    emit();
  }

  @override
  Future<void> nextPage() async {
    offset += 100;
    emit();
  }

  @override
  Future<void> previousPage() async {
    offset -= 100;
    emit();
  }

  @override
  void setForeground(bool value) {
    foreground.add(value);
  }

  @override
  Future<Catalog> menu() async {
    menus++;
    return catalog();
  }

  @override
  Future<OrderRecord?> review(
    OrderRecord record,
    List<OrderDraftLine> items,
  ) async {
    reviewedItems = items;
    orders = [order(reviewed: true)];
    emit();
    return orders.first;
  }

  @override
  CashAttempt? pendingCashFor(String orderId) => null;
  @override
  Future<OrderRecord?> retryCash(OrderRecord order) async => null;
  @override
  Future<OrderRecord?> pay(OrderRecord record, int value) async {
    pays++;
    received = value;
    return order(paid: true);
  }

  @override
  Future<OrderRecord?> complete(OrderRecord record) async {
    completes++;
    return record;
  }

  @override
  Future<ReorderDraft> prepareReorder(OrderRecord record) async => ReorderDraft(
    customerName: 'Sari',
    items: [
      OrderDraftLine(productId: 'coffee', variantIds: ['hot']),
    ],
  );
  @override
  Future<OrderRecord?> submitReorder(ReorderDraft draft) async {
    submits++;
    hasPendingAttempt = true;
    error = 'Hasil belum pasti';
    emit();
    return null;
  }

  @override
  Future<OrderRecord?> retryPending() async {
    retries++;
    hasPendingAttempt = false;
    emit();
    return order();
  }

  @override
  void clearError() {
    error = null;
    emit();
  }
}

Future<void> mount(WidgetTester tester, FakeController controller) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.binding.setSurfaceSize(const Size(1000, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(CashierApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'initialize once; login validates and submits credentials, no catalog on launch',
    (tester) async {
      final c = FakeController()..signedIn = false;
      await mount(tester, c);
      expect(c.initializes, 1);
      expect(c.menus, 0);
      await tap(tester, 'login-submit');
      expect(c.email, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        ' staff@example.com ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'secret123',
      );
      await tap(tester, 'login-submit');
      expect(c.email, 'staff@example.com');
      expect(c.password, 'secret123');
      c.emit();
      await tester.pump();
      expect(c.initializes, 1);
      expect(find.text('TKM-123'), findsOneWidget);
    },
  );

  testWidgets('history, expired and pagination call controller', (
    tester,
  ) async {
    final c = FakeController();
    await mount(tester, c);
    await tap(tester, 'tab-history');
    expect(c.tab, 'history');
    await tap(tester, 'expired-filter');
    expect(c.expiredOnly, isTrue);
    await tap(tester, 'next-page');
    expect(c.offset, 100);
    await tap(tester, 'previous-page');
    expect(c.offset, 0);
    await tap(tester, 'refresh');
    expect(c.refreshes, 1);
  });

  testWidgets('unreviewed order cannot accept cash', (tester) async {
    final c = FakeController();
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    expect(find.byKey(const ValueKey('cash-received')), findsNothing);
    expect(find.byKey(const ValueKey('open-review')), findsOneWidget);
    expect(c.pays, 0);
  });

  testWidgets(
    'cash integer validation, state survives refresh, cancel and confirm',
    (tester) async {
      final c = FakeController()..orders = [order(reviewed: true)];
      await mount(tester, c);
      await tap(tester, 'order-order-1');
      final input = find.byKey(const ValueKey('cash-received'));
      await tester.enterText(input, '100');
      await tap(tester, 'cash-submit');
      expect(c.pays, 0);
      expect(find.byKey(const ValueKey('confirm-yes')), findsNothing);
      await tester.enterText(input, '30000');
      c.emit();
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(input).controller!.text, '30000');
      await tap(tester, 'cash-submit');
      expect(c.pays, 0);
      await tap(tester, 'confirm-no');
      expect(c.pays, 0);
      await tap(tester, 'cash-submit');
      await tap(tester, 'confirm-yes');
      expect(c.pays, 1);
      expect(c.received, 30000);
    },
  );

  testWidgets(
    'fresh catalog editor changes qty variants addons notes and product list',
    (tester) async {
      final c = FakeController();
      await mount(tester, c);
      await tap(tester, 'order-order-1');
      await tap(tester, 'open-review');
      expect(c.menus, 1);
      await tap(tester, 'qty-plus-0');
      await tap(tester, 'variant-0-hot');
      await tap(tester, 'addon-0-milk');
      await tester.enterText(
        find.byKey(const ValueKey('notes-0')),
        'Tanpa gula',
      );
      c.emit();
      await tester.pumpAndSettle();
      await tap(tester, 'add-product');
      await tap(tester, 'product-tea');
      await tap(tester, 'remove-line-1');
      await tap(tester, 'editor-save');
      expect(c.reviewedItems, hasLength(1));
      expect(c.reviewedItems!.single.quantity, 2);
      expect(c.reviewedItems!.single.variantIds, ['hot']);
      expect(c.reviewedItems!.single.addonIds, ['milk']);
      expect(c.reviewedItems!.single.notes, 'Tanpa gula');
      expect(c.pays, 0);
    },
  );

  testWidgets('completion requires explicit confirmation', (tester) async {
    final c = FakeController()..orders = [order(paid: true)];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    await tap(tester, 'complete-order');
    expect(c.completes, 0);
    await tap(tester, 'confirm-no');
    await tap(tester, 'complete-order');
    await tap(tester, 'confirm-yes');
    expect(c.completes, 1);
  });

  testWidgets('expired reorder confirmation and persistent recovery action', (
    tester,
  ) async {
    final c = FakeController()..orders = [order(expired: true)];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    await tap(tester, 'reorder-order');
    expect(c.submits, 0);
    expect(c.menus, 1);
    await tap(tester, 'editor-save');
    expect(c.submits, 0);
    await tap(tester, 'confirm-yes');
    expect(c.submits, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-pending')), findsOneWidget);
    await tap(tester, 'retry-pending');
    expect(c.retries, 1);
  });

  testWidgets('pending recovery prominent on relaunch; busy blocks retry', (
    tester,
  ) async {
    final c = FakeController()
      ..hasPendingAttempt = true
      ..busy = true;
    await mount(tester, c);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('retry-pending')))
          .onPressed,
      isNull,
    );
    c.busy = false;
    c.emit();
    await tester.pumpAndSettle();
    await tap(tester, 'retry-pending');
    expect(c.retries, 1);
  });

  testWidgets('foreground-only serial snackbar and sound; lifecycle forwarded', (
    tester,
  ) async {
    final c = FakeController();
    final sounds = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        sounds.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(tester, c);
    c.newOrderSerial++;
    c.emit();
    // The listener queues presentation after this frame; render it next frame.
    await tester.pump();
    await tester.pump();
    expect(find.text('Pesanan baru masuk'), findsOneWidget);
    expect(sounds.where((e) => e.method == 'SystemSound.play'), hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    c.newOrderSerial++;
    c.emit();
    await tester.pump();
    expect(sounds.where((e) => e.method == 'SystemSound.play'), hasLength(1));
    expect(c.foreground.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(c.foreground.last, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(c.foreground.last, isFalse);
  });
}
