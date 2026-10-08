import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/order_line_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'line editor emits quantity, one variant per group, and addon removals',
    (tester) async {
      final product = CatalogProduct.fromJson({
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
          {
            'id': 'cold',
            'name': 'Dingin',
            'group_name': 'Suhu',
            'price_modifier': 2000,
            'is_available': true,
          },
        ],
        'addons': [
          {'id': 'milk', 'name': 'Susu', 'price': 3000, 'is_available': true},
        ],
      });
      var line = OrderDraftLine(productId: 'coffee');
      var removed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => OrderLineEditor(
                index: 0,
                line: line,
                product: product,
                disabled: false,
                onChanged: (value) => update(() => line = value),
                onRemove: () => removed = true,
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String key) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
      }

      await tap('qty-plus-0');
      expect(line.quantity, 2);
      await tap('qty-minus-0');
      expect(line.quantity, 1);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('qty-minus-0')))
            .onPressed,
        isNull,
      );
      await tap('variant-0-hot');
      expect(line.variantIds, ['hot']);
      await tap('variant-0-cold');
      expect(line.variantIds, ['cold']);
      await tap('variant-0-cold');
      expect(line.variantIds, isEmpty);
      await tap('addon-0-milk');
      expect(line.addonIds, ['milk']);
      await tap('addon-0-milk');
      expect(line.addonIds, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('notes-0')), 'Catatan');
      expect(line.notes, 'Catatan');
      await tap('remove-line-0');
      expect(removed, isTrue);
    },
  );

  testWidgets('unavailable choices are removable, busy actions cannot mutate', (
    tester,
  ) async {
    final product = CatalogProduct.fromJson({
      'id': 'coffee',
      'name': 'Kopi',
      'price': 25000,
      'is_available': false,
      'variants': [
        {
          'id': 'hot',
          'name': 'Panas',
          'group_name': 'Suhu',
          'price_modifier': 0,
          'is_available': false,
        },
      ],
      'addons': [],
    });
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderLineEditor(
            index: 0,
            line: OrderDraftLine(productId: 'coffee', variantIds: ['hot']),
            product: product,
            disabled: true,
            onChanged: (_) => changes++,
            onRemove: () => changes++,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('variant-0-hot')))
          .onSelected,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('qty-plus-0')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('remove-line-0')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('notes-0')))
          .enabled,
      isFalse,
    );
    expect(changes, 0);
  });
}
