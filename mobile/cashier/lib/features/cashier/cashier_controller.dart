import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/realtime_client.dart';
import '../../data/auth_session.dart';
import '../../data/cashier_api.dart';
import '../../data/cash_attempt.dart';
import '../../data/checkout_attempt.dart';
import '../../data/secure_store.dart';
import '../../domain/models.dart';

class CashierController extends ChangeNotifier {
  CashierController({
    required this._api,
    required this._auth,
    required this._realtime,
    required this._store,
  });
  final CashierApi _api;
  final AuthSession _auth;
  final RealtimeClient _realtime;
  final AttemptStore _store;
  bool signedIn = false, busy = false, loading = false;
  String? error;
  List<OrderRecord> orders = const [];
  String tab = 'active';
  bool expiredOnly = false;
  int offset = 0, newOrderSerial = 0;
  RealtimeStatus realtimeStatus = RealtimeStatus.stopped;
  bool get hasPendingAttempt => _pending != null || _pendingBlocked;
  CheckoutAttempt? _pending;
  Map<String, CashAttempt> _cash = {};
  bool _cashBlocked = true;
  bool _pendingBlocked = false,
      _foreground = true,
      _disposed = false,
      _initialized = false;
  bool _dirty = false, _realtimeStarted = false;
  int _generation = 0, _filterRevision = 0, _authOperations = 0;
  String? _user;
  StreamSubscription<void>? _authSubscription;
  Future<void>? _refreshing;
  Future<void> _authQueue = Future.value(), _storageQueue = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int g) =>
      !_disposed && g == _generation && _user != null && _auth.userId == _user;
  String _storeKey(String user) =>
      'tkm.checkout.v1.${_api.storageScope}.${base64Url.encode(utf8.encode(user))}';
  String _cashKey(String user) =>
      'tkm.cash.v1.${_api.storageScope}.${base64Url.encode(utf8.encode(user))}';
  Future<T> _storage<T>(Future<T> Function() work) {
    final result = _storageQueue.then((_) => work());
    _storageQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _reset() {
    ++_generation;
    _refreshing = null;
    _user = null;
    _dirty = false;
    _realtimeStarted = false;
    _realtime.stop();
    signedIn = false;
    busy = false;
    loading = false;
    orders = const [];
    _pending = null;
    _pendingBlocked = false;
    _cash = {};
    _cashBlocked = true;
    error = null;
    tab = 'active';
    expiredOnly = false;
    offset = 0;
    ++_filterRevision;
    newOrderSerial = 0;
    realtimeStatus = RealtimeStatus.stopped;
    _notify();
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _authSubscription = _auth.changes.listen(
      (_) {
        if (_authOperations > 0 || _disposed) return;
        if (_auth.userId != _user) {
          _reset();
          unawaited(_adoptSession(_generation));
        } else if (_user != null && _foreground) {
          _realtime.reconnect();
          unawaited(refresh());
        }
      },
      onError: (Object _) {
        if (!_disposed) {
          _reset();
          error = 'Session unavailable. Please sign in again.';
          _notify();
        }
      },
    );
    await _adoptSession(_generation);
  }

  Future<void> _adoptSession(int g) async {
    if (_disposed || g != _generation) return;
    _user = _auth.userId;
    if (_user == null) return;
    loading = true;
    _pendingBlocked = true;
    _notify();
    final key = _storeKey(_user!);
    try {
      final raw = await _storage(() => _store.read(key));
      if (!_current(g)) return;
      _pending = raw == null ? null : CheckoutAttempt.decode(raw);
      _pendingBlocked = false;
    } catch (_) {
      if (!_current(g)) return;
      // Fail closed: inability to read a previous attempt is not proof of absence.
      error =
          'Saved checkout unavailable. Sign in again before creating an order.';
    }
    if (!_current(g)) return;
    try {
      final key = _cashKey(_user!);
      final raw = await _storage(() => _store.read(key));
      if (!_current(g)) return;
      final entries = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
      _cash = {
        for (final entry in entries)
          (entry as Map)['order_id'] as String: CashAttempt.fromJson(
            Map<String, dynamic>.from(entry),
          ),
      };
      _cashBlocked = false;
    } catch (_) {
      if (!_current(g)) return;
      error = 'Saved cash confirmations unavailable. Cash actions blocked.';
    }
    if (_current(g)) await refresh();
  }

  Future<void> login(String email, String password) {
    if (_disposed) return Future.value();
    _reset();
    final g = _generation;
    busy = true;
    ++_authOperations;
    _notify();
    final task = _authQueue.then((_) async {
      if (_disposed || g != _generation) return;
      try {
        await _auth.signIn(email, password);
        if (g == _generation && !_disposed) await _adoptSession(g);
      } catch (_) {
        if (g == _generation && !_disposed) {
          error = 'Sign in failed. Check credentials and staff access.';
        }
      }
    });
    _authQueue = task.catchError((Object _) {});
    return task.whenComplete(() {
      --_authOperations;
      if (g == _generation && !_disposed) {
        busy = false;
        loading = false;
        _notify();
      }
    });
  }

  Future<void> logout() {
    if (_disposed) return Future.value();
    _reset();
    final g = _generation;
    ++_authOperations;
    final task = _authQueue.then((_) async {
      try {
        await _auth.signOut();
      } catch (_) {
        if (g == _generation && !_disposed) {
          error = 'Local sign out failed. Please retry.';
          _notify();
        }
      }
    });
    _authQueue = task.catchError((Object _) {});
    return task.whenComplete(() => --_authOperations);
  }

  Future<void> refresh() {
    if (_disposed || _user == null) return Future.value();
    _dirty = true;
    final running = _refreshing;
    if (running != null) return running;
    // Assign before starting work: notifications can request another refresh.
    final done = Completer<void>();
    _refreshing = done.future;
    unawaited(
      _drainRefresh(_generation).whenComplete(() {
        if (identical(_refreshing, done.future)) _refreshing = null;
        done.complete();
      }),
    );
    return done.future;
  }

  Future<void> _drainRefresh(int generation) async {
    while (_dirty && _current(generation)) {
      _dirty = false;
      final g = _generation, revision = _filterRevision;
      loading = true;
      _notify();
      try {
        final result = await _api.listOrders(
          tab: tab,
          expiredOnly: expiredOnly,
          offset: offset,
        );
        if (!_current(g) || revision != _filterRevision) continue;
        await _resolveCash(result, g);
        if (!_current(g) || revision != _filterRevision) continue;
        orders = List.unmodifiable(result);
        signedIn = true;
        _startRealtime();
      } catch (e) {
        if (_current(g) && revision == _filterRevision) _failure(e);
      } finally {
        if (_current(g)) {
          loading = false;
          _notify();
        }
      }
    }
  }

  void _startRealtime() {
    if (!_foreground || !signedIn || _realtimeStarted || _disposed) return;
    _realtimeStarted = true;
    final g = _generation;
    _realtime.start(
      onInvalidate: () {
        if (_current(g) && _foreground) unawaited(refresh());
      },
      onStatus: (value) {
        if (_current(g)) {
          realtimeStatus = value;
          _notify();
        }
      },
      onNewOrder: () {
        if (_current(g) && _foreground && signedIn) {
          ++newOrderSerial;
          _notify();
        }
      },
    );
  }

  void _failure(Object e) {
    error = e is ApiException
        ? e.message
        : 'Operation failed. Please retry safely.';
    if (e is ApiException && (e.status == 401 || e.status == 403)) {
      // Detach all reads/mutations from the denied authorization epoch.
      ++_generation;
      _dirty = false;
      _refreshing = null;
      busy = false;
      loading = false;
      signedIn = false;
      orders = const [];
      _realtimeStarted = false;
      _realtime.stop();
      realtimeStatus = RealtimeStatus.stopped;
    }
  }

  Future<void> changeTab(String value) async {
    if (!['active', 'history'].contains(value) || _disposed) return;
    tab = value;
    expiredOnly = false;
    offset = 0;
    ++_filterRevision;
    await refresh();
  }

  Future<void> setExpiredOnly(bool value) async {
    if (_disposed) return;
    expiredOnly = value;
    if (value) tab = 'history';
    offset = 0;
    ++_filterRevision;
    await refresh();
  }

  Future<void> nextPage() async {
    if (offset >= 100000 || _disposed) return;
    offset += 100;
    ++_filterRevision;
    await refresh();
  }

  Future<void> previousPage() async {
    if (offset == 0 || _disposed) return;
    offset = (offset - 100).clamp(0, 100000);
    ++_filterRevision;
    await refresh();
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    if (!value) {
      _realtimeStarted = false;
      _realtime.stop();
      realtimeStatus = RealtimeStatus.stopped;
      _notify();
    } else if (_user != null) {
      _startRealtime();
      unawaited(refresh());
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    final g = _generation;
    if (!signedIn || !_current(g)) {
      throw const ApiException('Staff login required', status: 401);
    }
    try {
      final value = await action();
      if (!_current(g)) throw const ApiException('Session changed');
      return value;
    } catch (e) {
      if (_current(g)) {
        _failure(e);
        _notify();
      }
      throw e is ApiException ? e : const ApiException('Request failed');
    }
  }

  Future<Catalog> menu() => _read(_api.menu);
  Future<ReorderDraft> prepareReorder(OrderRecord order) => _read(() {
    if (!order.isExpired) {
      throw const ApiException('Only expired orders can be reordered');
    }
    return _api.reorder(order.id);
  });
  Future<OrderRecord?> _mutate(
    bool allowed,
    Future<OrderRecord> Function(int g) action,
  ) async {
    if (_disposed || busy) return null;
    final g = _generation;
    if (!signedIn || !_current(g) || !allowed) {
      error = 'Order action unavailable. Refresh and check its state.';
      _notify();
      return null;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final result = await action(g);
      if (!_current(g)) return null;
      await refresh();
      return _current(g) ? result : null;
    } catch (e) {
      if (_current(g)) {
        _failure(e);
        _notify();
      }
      return null;
    } finally {
      if (_current(g)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<OrderRecord?> review(OrderRecord order, List<OrderDraftLine> items) =>
      _mutate(
        !_cashBlocked &&
            !_cash.containsKey(order.id) &&
            order.canReview(DateTime.now()) &&
            items.isNotEmpty,
        (_) => _api.review(order.id, order.version, items),
      );
  CashAttempt? pendingCashFor(String orderId) {
    final attempt = _cash[orderId];
    return attempt != null && !attempt.resolved ? attempt : null;
  }

  Future<OrderRecord?> retryCash(OrderRecord order) {
    final attempt = pendingCashFor(order.id);
    if (attempt == null) return Future.value();
    return pay(order, attempt.received);
  }

  Future<OrderRecord?> pay(OrderRecord order, int received) {
    final previous = _cash[order.id];
    final exactRetry =
        previous != null &&
        !previous.resolved &&
        previous.version == order.version &&
        previous.received == received;
    return _mutate(
      !_cashBlocked &&
          received <= 1000000000000 &&
          received >= order.total &&
          (previous == null ? order.canPay(DateTime.now()) : exactRetry),
      (g) async {
        final attempt =
            previous ?? CashAttempt(order.id, order.version, received);
        final key = _cashKey(_user!);
        if (previous == null) {
          final updated = {..._cash, order.id: attempt};
          await _saveCash(updated, key);
          if (!_current(g)) throw const ApiException('Session changed');
          _cash = updated;
        }
        try {
          final result = await _api.confirmCash(
            attempt.orderId,
            attempt.version,
            attempt.received,
          );
          if (_current(g)) await _resolveCash([result], g);
          return result;
        } catch (e) {
          // Absence/unpaid is NOT proof of rollback: the original POST may
          // still commit. Only paid/terminal state resolves the durable guard.
          if (_current(g)) {
            if (e is ApiException && (e.status == 401 || e.status == 403)) {
              _failure(e);
              _notify();
            } else {
              await refresh();
            }
          }
          rethrow;
        }
      },
    );
  }

  Future<void> _saveCash(Map<String, CashAttempt> values, String key) =>
      _storage(
        () => _store.write(
          key,
          jsonEncode(values.values.map((value) => value.toJson()).toList()),
        ),
      );

  Future<void> _resolveCash(List<OrderRecord> snapshot, int g) async {
    if (_cashBlocked || !_current(g)) return;
    final updated = {..._cash};
    var changed = false;
    for (final order in snapshot) {
      final attempt = updated[order.id];
      // A committed newer unpaid version proves the old version cannot pay:
      // review/payment serialize on the same row and paid never becomes unpaid.
      if (attempt != null &&
          !attempt.resolved &&
          order.paymentStatus == 'unpaid' &&
          order.version > attempt.version) {
        updated.remove(order.id);
        changed = true;
        continue;
      }
      if (attempt != null &&
          !attempt.resolved &&
          (order.paymentStatus == 'paid' ||
              order.status == 'expired' ||
              order.status == 'cancelled')) {
        updated[order.id] = attempt.resolve();
        changed = true;
      }
    }
    if (!changed) return;
    await _saveCash(updated, _cashKey(_user!));
    if (_current(g)) _cash = updated;
  }

  Future<OrderRecord?> complete(OrderRecord order) =>
      _mutate(order.canComplete, (_) => _api.complete(order.id));
  Future<OrderRecord?> submitReorder(
    ReorderDraft draft,
  ) => _mutate(!hasPendingAttempt && draft.items.isNotEmpty, (g) async {
    final attempt = CheckoutAttempt.create(draft), key = _storeKey(_user!);
    // Freeze all three values before durable storage and any network activity.
    await _storage(() => _store.write(key, attempt.encode()));
    if (!_current(g)) throw const ApiException('Session changed');
    _pending = attempt;
    _notify();
    return _sendAttempt(attempt, key, g);
  });
  Future<OrderRecord?> retryPending() => _mutate(
    _pending != null,
    (g) => _sendAttempt(_pending!, _storeKey(_user!), g),
  );
  Future<OrderRecord> _sendAttempt(
    CheckoutAttempt attempt,
    String key,
    int g,
  ) async {
    try {
      final result = await _api.createOrder(
        attempt.draft,
        attempt.key,
        attempt.token,
      );
      if (_current(g)) await _clearAttempt(key, g);
      return result;
    } on ApiException catch (e) {
      if (e.checkoutRejected && _current(g)) await _clearAttempt(key, g);
      rethrow;
    }
  }

  Future<void> _clearAttempt(String key, int g) async {
    await _storage(() => _store.delete(key));
    if (_current(g)) {
      _pending = null;
      _pendingBlocked = false;
      _notify();
    }
  }

  void clearError() {
    error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    unawaited(_authSubscription?.cancel());
    _realtime.dispose();
    _api.close();
    orders = const [];
    _pending = null;
    super.dispose();
  }
}
