/// Durable payment identity. Resolved records are retained as tombstones so a
/// stale unpaid snapshot cannot start another cash attempt, even after restart.
class CashAttempt {
  const CashAttempt(
    this.orderId,
    this.version,
    this.received, {
    this.resolved = false,
  });
  factory CashAttempt.fromJson(Map<String, dynamic> json) => CashAttempt(
    json['order_id'] as String,
    json['expected_version'] as int,
    json['received_rp'] as int,
    resolved: json['resolved'] as bool,
  );
  final String orderId;
  final int version, received;
  final bool resolved;
  CashAttempt resolve() =>
      CashAttempt(orderId, version, received, resolved: true);
  Map<String, dynamic> toJson() => {
    'order_id': orderId,
    'expected_version': version,
    'received_rp': received,
    'resolved': resolved,
  };
}
