import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'ui_common.dart';

class OrderLineEditor extends StatefulWidget {
  const OrderLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.product,
    required this.disabled,
    required this.onChanged,
    required this.onRemove,
  });
  final int index;
  final OrderDraftLine line;
  final CatalogProduct? product;
  final bool disabled;
  final ValueChanged<OrderDraftLine> onChanged;
  final VoidCallback onRemove;
  @override
  State<OrderLineEditor> createState() => _OrderLineEditorState();
}

class _OrderLineEditorState extends State<OrderLineEditor> {
  late final _notes = TextEditingController(text: widget.line.notes);
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _variant(CatalogVariant variant, bool selected) {
    final ids = [...widget.line.variantIds];
    ids.remove(variant.id);
    if (selected) {
      final groupIds = widget.product!.variants
          .where((v) => v.groupName == variant.groupName)
          .map((v) => v.id)
          .toSet();
      ids.removeWhere(groupIds.contains);
      ids.add(variant.id);
    }
    widget.onChanged(widget.line.copyWith(variantIds: ids));
  }

  void _addon(String id, bool selected) {
    final ids = [...widget.line.addonIds]..remove(id);
    if (selected) ids.add(id);
    widget.onChanged(widget.line.copyWith(addonIds: ids));
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final product = widget.product;
    final disabled = widget.disabled;
    final index = widget.index;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product?.name ??
                        'Produk tidak ditemukan (${line.productId})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-line-$index'),
                  tooltip: 'Hapus produk',
                  onPressed: disabled ? null : widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (product != null)
              Text('Harga dasar katalog: ${rupiah(product.price)}'),
            if (product == null || !product.available)
              const Text('Tidak tersedia. Hapus atau ganti produk ini.'),
            Row(
              children: [
                const Text('Jumlah'),
                IconButton(
                  key: ValueKey('qty-minus-$index'),
                  tooltip: 'Kurangi jumlah',
                  onPressed: disabled || line.quantity <= 1
                      ? null
                      : () => widget.onChanged(
                          line.copyWith(quantity: line.quantity - 1),
                        ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${line.quantity}', key: ValueKey('qty-value-$index')),
                IconButton(
                  key: ValueKey('qty-plus-$index'),
                  tooltip: 'Tambah jumlah',
                  onPressed: disabled
                      ? null
                      : () => widget.onChanged(
                          line.copyWith(quantity: line.quantity + 1),
                        ),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (product != null && product.variants.isNotEmpty)
              const Text('Varian • Pilih maksimal satu per kelompok'),
            if (product != null)
              Wrap(
                spacing: 8,
                children: [
                  for (final variant in product.variants)
                    FilterChip(
                      key: ValueKey('variant-$index-${variant.id}'),
                      label: Text(
                        '${variant.groupName}: ${variant.name} (${rupiah(variant.priceModifier)})${variant.available ? '' : ' • Habis'}',
                      ),
                      selected: line.variantIds.contains(variant.id),
                      onSelected:
                          disabled ||
                              (!variant.available &&
                                  !line.variantIds.contains(variant.id))
                          ? null
                          : (selected) => _variant(variant, selected),
                    ),
                  for (final id in line.variantIds.where(
                    (id) => !product.variants.any((v) => v.id == id),
                  ))
                    InputChip(
                      label: Text('Varian tidak tersedia: $id'),
                      onDeleted: disabled
                          ? null
                          : () => widget.onChanged(
                              line.copyWith(
                                variantIds: [...line.variantIds]..remove(id),
                              ),
                            ),
                    ),
                ],
              ),
            if (product != null && product.addons.isNotEmpty)
              const Text('Tambahan'),
            if (product != null)
              Wrap(
                spacing: 8,
                children: [
                  for (final addon in product.addons)
                    FilterChip(
                      key: ValueKey('addon-$index-${addon.id}'),
                      label: Text(
                        '${addon.name} (${rupiah(addon.price)})${addon.available ? '' : ' • Habis'}',
                      ),
                      selected: line.addonIds.contains(addon.id),
                      onSelected:
                          disabled ||
                              (!addon.available &&
                                  !line.addonIds.contains(addon.id))
                          ? null
                          : (selected) => _addon(addon.id, selected),
                    ),
                  for (final id in line.addonIds.where(
                    (id) => !product.addons.any((a) => a.id == id),
                  ))
                    InputChip(
                      label: Text('Tambahan tidak tersedia: $id'),
                      onDeleted: disabled ? null : () => _addon(id, false),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('notes-$index'),
              controller: _notes,
              enabled: !disabled,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Catatan produk'),
              onChanged: (value) =>
                  widget.onChanged(widget.line.copyWith(notes: value)),
            ),
          ],
        ),
      ),
    );
  }
}
