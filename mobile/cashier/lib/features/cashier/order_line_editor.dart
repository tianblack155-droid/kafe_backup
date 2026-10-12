import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
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
    return SectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.neutralSurface,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product?.name ??
                          'Produk tidak ditemukan (${line.productId})',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (product != null)
                      Text(
                        'Harga dasar katalog: ${rupiah(product.price)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('remove-line-$index'),
                tooltip: 'Hapus produk',
                onPressed: disabled ? null : widget.onRemove,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.errorText,
                ),
              ),
            ],
          ),
          if (product == null || !product.available)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: InfoBanner.warning(
                'Tidak tersedia. Hapus atau ganti produk ini.',
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.backgroundAlt,
              borderRadius: BorderRadius.circular(AppRadius.badge),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: AppSpacing.xs),
                    child: Text(
                      'Jumlah',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${line.quantity}',
                        key: ValueKey('qty-value-$index'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
              ],
            ),
          ),
          if (product != null && product.variants.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Varian • Pilih maksimal satu per kelompok',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (product != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
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
            ),
          if (product != null && product.addons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Tambahan',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (product != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
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
            ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: ValueKey('notes-$index'),
            controller: _notes,
            enabled: !disabled,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Catatan produk',
              hintText: 'Contoh: tanpa gula, es sedikit',
            ),
            onChanged: (value) =>
                widget.onChanged(widget.line.copyWith(notes: value)),
          ),
        ],
      ),
    );
  }
}
