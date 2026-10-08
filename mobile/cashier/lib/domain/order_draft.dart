class OrderDraftLine {
  OrderDraftLine({
    required this.productId,
    this.quantity = 1,
    List<String> variantIds = const [],
    List<String> addonIds = const [],
    this.notes = '',
  }) : variantIds = List.unmodifiable(variantIds),
       addonIds = List.unmodifiable(addonIds);
  final String productId, notes;
  final int quantity;
  final List<String> variantIds, addonIds;
  factory OrderDraftLine.fromJson(Map<String, dynamic> json) => OrderDraftLine(
    productId: json['product_id'] as String,
    quantity: json['quantity'] as int,
    variantIds: (json['variant_ids'] as List).cast<String>(),
    addonIds: (json['addon_ids'] as List).cast<String>(),
    notes: json['notes'] as String,
  );
  OrderDraftLine copyWith({
    String? productId,
    int? quantity,
    List<String>? variantIds,
    List<String>? addonIds,
    String? notes,
  }) => OrderDraftLine(
    productId: productId ?? this.productId,
    quantity: quantity ?? this.quantity,
    variantIds: variantIds ?? this.variantIds,
    addonIds: addonIds ?? this.addonIds,
    notes: notes ?? this.notes,
  );
  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
    'variant_ids': variantIds,
    'addon_ids': addonIds,
    'notes': notes,
  };
}

class ReorderDraft {
  ReorderDraft({
    required this.customerName,
    required List<OrderDraftLine> items,
  }) : items = List.unmodifiable(items);
  final String customerName;
  final List<OrderDraftLine> items;
  factory ReorderDraft.fromJson(Map<String, dynamic> json) => ReorderDraft(
    customerName: json['customer_name'] as String? ?? '',
    items: (json['items'] as List)
        .map(
          (v) => OrderDraftLine.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'customer_name': customerName,
    'payment_method': 'cash',
    'items': items.map((v) => v.toJson()).toList(),
  };
}
