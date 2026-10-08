import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cashier/core/deadline_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DelayedClient extends http.BaseClient {
  final result = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => result.future;
}

void main() {
  test('login transport timeout cannot install late session', () async {
    final transport = DelayedClient();
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-public',
      httpClient: DeadlineClient(
        transport,
        timeout: const Duration(milliseconds: 10),
      ),
    );
    await expectLater(
      client.auth.signInWithPassword(
        email: 'test@example.test',
        password: 'synthetic',
      ),
      throwsA(anything),
    );
    final session = {
      'access_token': 'header.payload.signature',
      'refresh_token': 'synthetic',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
    transport.result.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(session))),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.auth.currentSession, isNull);
    await client.dispose();
  });
}
