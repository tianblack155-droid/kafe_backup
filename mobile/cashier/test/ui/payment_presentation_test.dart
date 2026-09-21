import 'package:cashier/app.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/order_detail_screen.dart';
import 'package:cashier/features/cashier/ui_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/api_models_test.dart' show orderJson;
import 'cashier_app_test.dart' show FakeController, mount, tap, order;

void main() {
  test('rupiah groups integer digits without rounding', () {
    expect(rupiah(5000), 'Rp 5.000');
    expect(rupiah(1234567890), 'Rp 1.234.567.890');
    expect(rupiah(-5000), 'Rp -5.000');
  });

  testWidgets(
    'cash preview updates without losing input and paid hides deadline',
    (tester) async {
      final c = FakeController()..orders = [order(reviewed: true)];
      await mount(tester, c);
      await tap(tester, 'order-order-1');
      expect(find.text('Sisa waktu bayar'), findsOneWidget);
      expect(find.textContaining('Versi '), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('cash-received')),
        '30000',
      );
      await tester.pump();
      expect(find.text('Kembalian: Rp 5.000'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('cash-received')))
            .controller!
            .text,
        '30000',
      );
      c.orders = [order(paid: true)];
      c.emit();
      await tester.pump();
      expect(find.text('Sisa waktu bayar'), findsNothing);
      expect(find.byKey(const ValueKey('complete-order')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('local clock expires payment actions without a REST refresh', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final data = orderJson()
      ..['expires_at'] = DateTime.now()
          .add(const Duration(seconds: 1))
          .toIso8601String();
    final record = OrderRecord.fromJson(data);
    final c = FakeController()..orders = [record];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(controller: c, order: record),
      ),
    );
    expect(find.text('00:01'), findsOneWidget);
    expect(find.byKey(const ValueKey('cash-submit')), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('cash-submit')), findsNothing);
    expect(find.byKey(const ValueKey('open-review')), findsNothing);
    expect(c.pays, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('phone layout remains usable with larger text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(CashierApp(controller: FakeController()));
    await tester.pumpAndSettle();
    await tap(tester, 'order-order-1');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
