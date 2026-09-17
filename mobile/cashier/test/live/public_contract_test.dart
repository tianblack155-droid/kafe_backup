// Explicit opt-in only. Run with a private temporary fixture, never real user credentials.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide RealtimeClient;
import 'package:uuid/uuid.dart';
import 'package:cashier/core/app_config.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/data/auth_session.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';

void main() {
  final fixturePath = Platform.environment['TKM_FLUTTER_LIVE_FIXTURE'];
  test(
    'native Dart services against public Auth, REST and WSS',
    () async {
      final file = File(fixturePath!);
      final fixture =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final config = AppConfig(
        apiBase: Uri.parse('https://teraskayumanis.alrizky.id/api/core/'),
        wsUrl: Uri.parse('wss://teraskayumanis.alrizky.id/ws'),
        wsOrigin: 'https://teraskayumanis.alrizky.id',
        supabaseUrl: 'https://aiptdjypuccoakyfvdyl.supabase.co',
        supabaseKey: fixture['publicKey'] as String,
      );
      final supabase = SupabaseClient(config.supabaseUrl, config.supabaseKey);
      final auth = SupabaseAuthSession(supabase);
      final api = CashierApi(config: config, auth: auth);
      final realtime = RealtimeClient(config, auth);
      final ready = Completer<void>(), created = Completer<void>();
      try {
        await auth.signIn(
          fixture['email'] as String,
          fixture['password'] as String,
        );
        await api.listOrders();
        realtime.start(
          onInvalidate: () {},
          onStatus: (s) {
            if (s == RealtimeStatus.connected && !ready.isCompleted) {
              ready.complete();
            }
          },
          onNewOrder: () {
            if (!created.isCompleted) created.complete();
          },
        );
        await ready.future.timeout(const Duration(seconds: 15));
        final menu = await api.menu();
        final product = menu.products.firstWhere(
          (p) => p.available && p.variants.isEmpty && p.addons.isEmpty,
        );
        final draft = ReorderDraft(
          customerName: 'TEMP FLUTTER VERIFY',
          items: [OrderDraftLine(productId: product.id)],
        );
        final key = const Uuid().v4(),
            token = const Uuid().v4() + const Uuid().v4();
        fixture['keys'] = [key];
        await file.writeAsString(jsonEncode(fixture));
        final order = await api.createOrder(draft, key, token);
        expect(order.items.single.productId, product.id);
        expect(order.items.single.quantity, 1);
        expect(order.items.single.name, product.name);
        await created.future.timeout(const Duration(seconds: 15));
        final listed = (await api.listOrders()).singleWhere(
          (o) => o.id == order.id,
        );
        expect(
          listed.items.single.toDraft().toJson(),
          draft.items.single.toJson(),
        );
        final reviewed = await api.review(order.id, order.version, draft.items);
        expect(
          reviewed.items.single.toDraft().toJson(),
          draft.items.single.toJson(),
        );
        expect(reviewed.canPay(DateTime.now()), isTrue);
        final paid = await api.confirmCash(
          reviewed.id,
          reviewed.version,
          reviewed.total,
        );
        expect(paid.paymentStatus, 'paid');
        expect(paid.items.single.productId, product.id);
        final done = await api.complete(paid.id);
        expect(done.status, 'completed');
        expect((await api.createOrder(draft, key, token)).id, order.id);
        expect(
          (await api.listOrders(tab: 'history')).any((o) => o.id == order.id),
          isTrue,
        );
      } finally {
        realtime.dispose();
        api.close();
        await auth.signOut();
        await supabase.dispose();
      }
    },
    skip: fixturePath == null
        ? 'Opt-in temporary live fixture required'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
