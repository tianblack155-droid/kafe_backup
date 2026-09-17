import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AttemptStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAttemptStore implements AttemptStore {
  SecureAttemptStore();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Supabase's LocalStorage stores the entire serialized session, not just the
/// access JWT: losing the refresh token here would break cold-start recovery.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _project = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://aiptdjypuccoakyfvdyl.supabase.co',
  );
  String get _key => 'tkm.session.v1.$_project';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
