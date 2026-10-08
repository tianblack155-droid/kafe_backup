import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide RealtimeClient;

import 'package:http/http.dart' as http;

import 'core/deadline_client.dart';
import 'app.dart';
import 'core/app_config.dart';
import 'data/auth_session.dart';
import 'data/cashier_api.dart';
import 'data/secure_store.dart';
import 'core/realtime_client.dart';
import 'features/cashier/cashier_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = AppConfig.fromEnvironment();
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseKey,
      httpClient: DeadlineClient(http.Client()),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: true,
        detectSessionInUri: false,
        localStorage: SecureSessionStorage(),
      ),
    );
    final auth = SupabaseAuthSession(Supabase.instance.client);
    final api = CashierApi(config: config, auth: auth);
    runApp(
      CashierApp(
        controller: CashierController(
          api: api,
          auth: auth,
          realtime: RealtimeClient(config, auth),
          store: SecureAttemptStore(),
        ),
      ),
    );
  } catch (_) {
    // Never echo config, session or storage exception values onto the screen/log.
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Konfigurasi atau penyimpanan aman belum siap. '
                  'Ikuti mobile/cashier/README.md dan jalankan dengan '
                  '--dart-define-from-file=config/preview.json. '
                  'Gunakan hanya Supabase publishable/anon key, bukan service_role.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
