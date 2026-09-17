import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../domain/models.dart';
import 'auth_session.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.code, this.retryAfter});
  final String message;
  final int? status;
  final String? code;
  final Duration? retryAfter;
  bool get checkoutRejected => status == 409 && code == 'checkout_rejected';
  @override
  String toString() => message;
}

class CashierApi {
  CashierApi({required this.config, required this.auth, http.Client? client})
    : _client = client ?? http.Client() {
    _observedUser = auth.userId;
    _authSubscription = auth.changes.listen(
      (_) => _syncIdentity(),
      onError: (Object _) => ++_authGeneration,
    );
  }
  final AppConfig config;
  final AuthSession auth;
  final http.Client _client;
  late final StreamSubscription<void> _authSubscription;
  int _authGeneration = 0;
  String? _observedUser;
  void _syncIdentity() {
    if (_observedUser != auth.userId) {
      _observedUser = auth.userId;
      ++_authGeneration;
    }
  }

  DateTime? _retryAt;
  bool _closed = false;
  String get storageScope => config.storageScope;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  String _orderPath(String id, String action) {
    if (!_uuid.hasMatch(id)) {
      throw const ApiException('Invalid order identifier');
    }
    return 'orders/$id/$action';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String> headers = const {},
    bool staff = true,
  }) async {
    if (_closed) throw const ApiException('Connection closed');
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      throw ApiException(
        'Please wait before retrying',
        status: 429,
        retryAfter: retryAt.difference(DateTime.now()),
      );
    }
    _syncIdentity();
    final user = auth.userId;
    final generation = _authGeneration;
    final clock = Stopwatch()..start();
    Duration remaining() {
      final left = const Duration(seconds: 15) - clock.elapsed;
      if (left <= Duration.zero) throw TimeoutException('Request timed out');
      return left;
    }

    try {
      final token = staff
          ? await auth.accessToken().timeout(remaining())
          : null;
      if (_closed || generation != _authGeneration) {
        throw const ApiException('Session changed');
      }
      if (staff &&
          (user == null ||
              auth.userId != user ||
              token == null ||
              token.isEmpty)) {
        throw const ApiException('Staff login required', status: 401);
      }
      final base = config.apiBase.toString();
      final uri = Uri.parse(base.endsWith('/') ? base : '$base/')
          .resolve(path)
          .replace(queryParameters: query);
      final request = http.Request(method, uri)..followRedirects = false;
      request.headers.addAll({
        'Accept': 'application/json',
        if (staff) 'Authorization': 'Bearer $token',
        ...headers,
      });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(remaining()),
      ).timeout(remaining());
      if (_closed || generation != _authGeneration) {
        throw const ApiException('Session changed');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          final data = jsonDecode(response.body);
          if (data is Map &&
              [
                'checkout_rejected',
                'idempotency_conflict',
              ].contains(data['code'])) {
            code = data['code'] as String;
          }
        } catch (_) {}
        Duration? retry;
        if (response.statusCode == 429) {
          final value = response.headers['retry-after'];
          final seconds = int.tryParse(value ?? '');
          DateTime? date;
          try {
            if (value != null && seconds == null) date = HttpDate.parse(value);
          } catch (_) {}
          retry = seconds != null
              ? Duration(seconds: seconds < 0 ? 0 : seconds)
              : date?.difference(DateTime.now()) ?? const Duration(seconds: 60);
          if (retry.isNegative) retry = Duration.zero;
          _retryAt = DateTime.now().add(retry);
        }
        throw ApiException(
          switch (response.statusCode) {
            401 => 'Staff login required',
            403 => 'Access denied',
            404 => 'Order not found',
            409 => 'Order changed or checkout rejected. Refresh and check before retrying.',
            429 => 'Please wait before retrying',
            _ => 'Request failed. Please retry safely.',
          },
          status: response.statusCode,
          code: code,
          retryAfter: retry,
        );
      }
      return jsonDecode(response.body);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Connection or response failed. Please retry safely.',
      );
    }
  }

  Future<List<OrderRecord>> listOrders({
    String tab = 'active',
    bool expiredOnly = false,
    int offset = 0,
  }) async {
    if (!['active', 'history'].contains(tab) ||
        offset < 0 ||
        offset > 100000 ||
        (expiredOnly && tab != 'history')) {
      throw const ApiException('Invalid order filter');
    }
    final data = await _request(
      'GET',
      'admin/orders',
      query: {
        'tab': tab,
        if (expiredOnly) 'status': 'expired',
        'offset': '$offset',
      },
    );
    return List.unmodifiable(
      (data as List).map(
        (v) => OrderRecord.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    );
  }

  Future<Catalog> menu() async => Catalog.fromJson(
    Map<String, dynamic>.from(
      await _request('GET', 'menu', staff: false) as Map,
    ),
  );
  Future<OrderRecord> _post(
    String path,
    Object body, {
    Map<String, String> headers = const {},
  }) async => OrderRecord.fromJson(
    Map<String, dynamic>.from(
      await _request('POST', path, body: body, headers: headers) as Map,
    ),
  );
  Future<OrderRecord> review(
    String id,
    int version,
    List<OrderDraftLine> items,
  ) => _post(_orderPath(id, 'review'), {
    'expected_version': version,
    'items': items.map((i) => i.toJson()).toList(),
  });
  Future<OrderRecord> confirmCash(String id, int version, int received) =>
      _post(_orderPath(id, 'confirm-cash'), {
        'expected_version': version,
        'received_rp': received,
      });
  Future<OrderRecord> complete(String id) =>
      _post(_orderPath(id, 'complete'), {});
  Future<ReorderDraft> reorder(String id) async => ReorderDraft.fromJson(
    Map<String, dynamic>.from(
      await _request('GET', _orderPath(id, 'reorder')) as Map,
    ),
  );
  Future<OrderRecord> createOrder(
    ReorderDraft draft,
    String key,
    String orderToken,
  ) {
    if (key.length < 16 ||
        key.length > 128 ||
        orderToken.length < 24 ||
        orderToken.length > 256) {
      throw const ApiException('Invalid checkout attempt');
    }
    return _post(
      'orders',
      draft.toJson(),
      headers: {'Idempotency-Key': key, 'X-Order-Token': orderToken},
    );
  }

  void close() {
    _closed = true;
    unawaited(_authSubscription.cancel());
    _client.close();
  }
}
