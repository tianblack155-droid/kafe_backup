import 'dart:convert';

class AppConfig {
  AppConfig({
    required this.apiBase,
    required this.wsUrl,
    required this.wsOrigin,
    required this.supabaseUrl,
    required this.supabaseKey,
  }) {
    _endpoint(apiBase, 'https');
    _endpoint(wsUrl, 'wss');
    final origin = _parse(wsOrigin);
    _endpoint(origin, 'https');
    if (origin.path.isNotEmpty && origin.path != '/') {
      throw const FormatException('Invalid websocket origin');
    }
    _endpoint(_parse(supabaseUrl), 'https');
    if (supabaseKey.isEmpty ||
        supabaseKey.trim() != supabaseKey ||
        supabaseKey.startsWith('sb_secret')) {
      throw const FormatException('A public Supabase key is required');
    }
    if (!supabaseKey.startsWith('sb_publishable_')) {
      try {
        final parts = supabaseKey.split('.');
        if (parts.length != 3) throw const FormatException();
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (claims is! Map || claims['role'] != 'anon') {
          throw const FormatException();
        }
      } catch (_) {
        throw const FormatException('A public Supabase key is required');
      }
    }
  }
  final Uri apiBase, wsUrl;
  final String wsOrigin, supabaseUrl, supabaseKey;
  // Used only as a secure-storage namespace, never as authentication.
  String get storageScope =>
      base64Url.encode(utf8.encode('${apiBase.toString()}|$supabaseUrl'));
  factory AppConfig.fromEnvironment() => AppConfig(
    apiBase: _parse(
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://teraskayumanis.alrizky.id/api/core/',
      ),
    ),
    wsUrl: _parse(
      const String.fromEnvironment(
        'WS_URL',
        defaultValue: 'wss://teraskayumanis.alrizky.id/ws',
      ),
    ),
    wsOrigin: const String.fromEnvironment(
      'WS_ORIGIN',
      defaultValue: 'https://teraskayumanis.alrizky.id',
    ),
    supabaseUrl: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://aiptdjypuccoakyfvdyl.supabase.co',
    ),
    supabaseKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static Uri _parse(String value) {
    try {
      return Uri.parse(value);
    } catch (_) {
      throw const FormatException('Invalid endpoint configuration');
    }
  }

  static void _endpoint(Uri uri, String scheme) {
    if (uri.scheme != scheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Secure endpoint configuration required');
    }
  }
}
