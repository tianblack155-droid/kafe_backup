import 'package:flutter_test/flutter_test.dart';
import 'package:cashier/demo/demo_cashier.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/app.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('demo opens cashier without credentials on phone-sized screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CashierApp(controller: createDemoController(), demo: true),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO • Data lokal'), findsOneWidget);
    expect(find.text('DEMO-A1'), findsOneWidget);
    expect(find.text('Email staf'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('demo review, payment, completion and exact reorder retry', () async {
    final api = DemoApi(DemoAuth());
    addTearDown(api.close);
    final order = (await api.listOrders()).firstWhere(
      (o) => o.status == 'pending',
    );
    await expectLater(
      api.confirmCash(order.id, order.version, 50000),
      throwsA(isA<ApiException>()),
    );
    final reviewed = await api.review(
      order.id,
      order.version,
      order.items.map((i) => i.toDraft()).toList(),
    );
    expect(reviewed.items.single.variantName, 'Dingin');
    final paid = await api.confirmCash(reviewed.id, reviewed.version, 50000);
    expect(paid.paymentStatus, 'paid');
    expect(
      (await api.confirmCash(reviewed.id, reviewed.version, 50000)).version,
      paid.version,
    );
    expect((await api.complete(paid.id)).status, 'completed');
    final expired = (await api.listOrders(
      tab: 'history',
      expiredOnly: true,
    )).single;
    final draft = await api.reorder(expired.id);
    final created = await api.createOrder(draft, 'demo-key', 'demo-token');
    expect(
      (await api.createOrder(draft, 'demo-key', 'demo-token')).id,
      created.id,
    );
    expect(created.id, isNot(expired.id));
    expect(
      (await api.listOrders(tab: 'history', expiredOnly: true)).single.id,
      expired.id,
    );
    await expectLater(
      api.review(created.id, created.version, [
        OrderDraftLine(productId: 'coffee'),
      ]),
      throwsA(isA<ApiException>()),
    );
  });
}
