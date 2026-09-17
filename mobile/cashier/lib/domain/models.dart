export 'catalog.dart';
export 'order_draft.dart';
import 'order_draft.dart';

class OrderRecord {
  OrderRecord.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      orderNumber = json['order_number'].toString(),
      customerName = json['customer_name'] as String? ?? '',
      status = json['status'] as String,
      paymentStatus = json['payment_status'] as String,
      version = json['version'] as int,
      reviewedVersion = json['reviewed_version'] as int?,
      total = json['total'] as int,
      expiresAt = DateTime.parse(json['expires_at'] as String),
      items = List.unmodifiable(
        (json['order_items'] as List? ?? []).map(
          (v) => OrderLine.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
  final String id, orderNumber, customerName, status, paymentStatus;
  final int version, total;
  final int? reviewedVersion;
  final DateTime expiresAt;
  final List<OrderLine> items;
  bool canReview(DateTime now) =>
      status == 'pending' &&
      paymentStatus == 'unpaid' &&
      now.isBefore(expiresAt);
  bool canPay(DateTime now) => canReview(now) && reviewedVersion == version;
  bool get canComplete => status == 'confirmed' && paymentStatus == 'paid';
  bool get isExpired =>
      status == 'expired' ||
      (status == 'pending' &&
          paymentStatus == 'unpaid' &&
          !DateTime.now().isBefore(expiresAt));
}

class OrderLine {
  OrderLine.fromJson(Map<String, dynamic> json)
    : productId = json['product_id'] as String? ?? '',
      name = json['product_name'] as String? ?? '',
      variantName = json['variant_name'] as String? ?? '',
      addonNames = List.unmodifiable(
        (json['order_item_addons'] as List? ?? []).map(
          (a) => (a as Map)['addon_name'] as String,
        ),
      ),
      quantity = json['quantity'] as int,
      unitPrice = json['unit_price'] as int,
      subtotal = json['subtotal'] as int,
      variantIds = List.unmodifiable(
        (json['variant_ids'] as List? ?? []).cast<String>(),
      ),
      addonIds = List.unmodifiable(
        (json['addon_ids'] as List? ?? []).cast<String>(),
      ),
      notes = json['notes'] as String? ?? '';
  final String productId, name, notes;
  final String variantName;
  final List<String> addonNames;
  final int quantity, unitPrice, subtotal;
  final List<String> variantIds, addonIds;
  OrderDraftLine toDraft() => OrderDraftLine(
    productId: productId,
    quantity: quantity,
    variantIds: variantIds,
    addonIds: addonIds,
    notes: notes,
  );
}
