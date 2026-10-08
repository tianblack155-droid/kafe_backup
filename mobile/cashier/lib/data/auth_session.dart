import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthSession {
  String? get userId;
  Future<String?> accessToken();
  Stream<void> get changes;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class SupabaseAuthSession implements AuthSession {
  SupabaseAuthSession(this.client);
  final SupabaseClient client;
  static const _deadline = Duration(seconds: 10);
  Future<String?>? _refresh;
  String? _refreshIdentity;
  int _generation = 0;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<void> get changes => client.auth.onAuthStateChange.map((_) {});
  @override
  Future<String?> accessToken() async {
    final session = client.auth.currentSession;
    if (session == null) return null;
    final expiry = session.expiresAt;
    if (expiry != null &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 < expiry - 60) {
      return session.accessToken;
    }
    // A new session must never share the old session's pending refresh.
    final identity = session.refreshToken;
    final pending = _refresh;
    if (pending != null && identity == _refreshIdentity) return pending;
    final g = _generation;
    final future = _refreshToken(session, g);
    _refreshIdentity = identity;
    _refresh = future;
    try {
      return await future;
    } finally {
      if (identical(_refresh, future)) {
        _refresh = null;
        _refreshIdentity = null;
      }
    }
  }

  Future<String?> _refreshToken(Session session, int g) async {
    try {
      final result = await client.auth.refreshSession().timeout(_deadline);
      if (g != _generation || userId != session.user.id) return null;
      return result.session?.accessToken;
    } on TimeoutException {
      if (g == _generation &&
          client.auth.currentSession?.refreshToken == session.refreshToken) {
        _detach();
        // Installed GoTrue removes local session synchronously before its
        // logout HTTP call, incrementing _sessionVersion. _doRefresh discards
        // late results for that version. Do not wait on another hung network.
        unawaited(
          client.auth
              .signOut(scope: SignOutScope.local)
              .timeout(_deadline)
              .catchError((Object _) {}),
        );
      }
      rethrow;
    }
  }

  void _detach() {
    ++_generation;
    _refresh = null;
    _refreshIdentity = null;
  }

  @override
  Future<void> signIn(String email, String password) async {
    _detach();
    await client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() {
    _detach();
    return client.auth.signOut(scope: SignOutScope.local).timeout(_deadline);
  }
}
