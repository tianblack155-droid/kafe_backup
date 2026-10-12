import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../domain/models.dart';
import 'cashier_controller.dart';
import 'order_line_editor.dart';
import 'ui_common.dart';

class OrderEditorScreen extends StatefulWidget {
  const OrderEditorScreen({
    super.key,
    required this.controller,
    required this.catalog,
    required this.order,
    this.reorderDraft,
  });
  final CashierController controller;
  final Catalog catalog;
  final OrderRecord order;
  final ReorderDraft? reorderDraft;
  @override
  State<OrderEditorScreen> createState() => _OrderEditorScreenState();
}

class _EditableLine {
  _EditableLine(this.id, this.draft);
  final int id;
  OrderDraftLine draft;
}

class _OrderEditorScreenState extends State<OrderEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _customer = TextEditingController(
    text: widget.reorderDraft?.customerName ?? widget.order.customerName,
  );
  late final List<_EditableLine> _lines;
  int _nextId = 0;
  bool _saving = false;
  bool _confirming = false;
  String? _error;
  bool get _reorder => widget.reorderDraft != null;

  @override
  void initState() {
    super.initState();
    _lines =
        (widget.reorderDraft?.items ??
                widget.order.items.map((line) => line.toDraft()).toList())
            .map((line) => _EditableLine(_nextId++, line))
            .toList();
  }

  @override
  void dispose() {
    _customer.dispose();
    super.dispose();
  }

  CatalogProduct? _product(String id) {
    for (final product in widget.catalog.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  String? _validate() {
    if (_lines.isEmpty) return 'Tambahkan setidaknya satu produk.';
    for (final line in _lines) {
      final draft = line.draft;
      final product = _product(draft.productId);
      if (product == null || !product.available) {
        return 'Produk tidak tersedia. Hapus atau ganti produk sebelum menyimpan.';
      }
      if (draft.quantity < 1) return 'Jumlah produk minimal satu.';
      if (draft.variantIds.any(
            (id) => !product.variants.any((v) => v.id == id && v.available),
          ) ||
          draft.addonIds.any(
            (id) => !product.addons.any((a) => a.id == id && a.available),
          )) {
        return 'Ada varian atau tambahan tidak tersedia. Hapus pilihan tersebut.';
      }
      final groups = <String>{};
      for (final id in draft.variantIds) {
        final variant = product.variants.firstWhere((v) => v.id == id);
        if (!groups.add(variant.groupName)) {
          return 'Pilih satu varian per kelompok.';
        }
      }
    }
    return null;
  }

  Future<void> _addProduct() async {
    final product = await showDialog<CatalogProduct>(
      context: context,
      builder: (context) =>
          _ProductPickerDialog(products: widget.catalog.products),
    );
    if (mounted && product != null) {
      setState(
        () => _lines.add(
          _EditableLine(_nextId++, OrderDraftLine(productId: product.id)),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _confirming ||
        widget.controller.busy ||
        (_reorder && widget.controller.hasPendingAttempt)) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _confirming = _reorder;
      _error = null;
    });
    try {
      final items = _lines.map((line) => line.draft).toList();
      final customerName = _customer.text.trim();
      OrderRecord? result;
      if (_reorder) {
        final summary = _lines
            .map(
              (line) =>
                  '${line.draft.quantity} × ${_product(line.draft.productId)!.name}',
            )
            .join('\n');
        if (!await confirmAction(
          context,
          title: 'Buat pesanan ulang?',
          message:
              '$customerName\n$summary\n\nPesanan baru belum dibayar. Harga akhir dihitung server; tinjau kembali sebelum menerima tunai. Pesanan lama tetap kedaluwarsa.',
          action: 'Ya, buat pesanan',
        )) {
          return;
        }
        if (!mounted ||
            !widget.controller.signedIn ||
            widget.controller.busy ||
            widget.controller.hasPendingAttempt) {
          return;
        }
        setState(() {
          _confirming = false;
          _saving = true;
        });
        result = await widget.controller.submitReorder(
          ReorderDraft(customerName: customerName, items: items),
        );
      } else {
        setState(() => _saving = true);
        result = await widget.controller.review(widget.order, items);
      }
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
      } else {
        setState(
          () => _error = widget.controller.error ?? 'Belum berhasil. Draf tetap tersedia. Periksa status sebelum mencoba lagi.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tidak dapat menyimpan. Draf tidak dihapus. Periksa koneksi dan status pesanan.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.signedIn) return const Scaffold(body: SizedBox.shrink());
      final disabled =
          _saving || _confirming || c.busy || (_reorder && c.hasPendingAttempt);
      return PopScope(
        canPop: !_saving && !_confirming,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(
              _reorder
                  ? 'Draf pesanan ulang'
                  : 'Tinjau ${widget.order.orderNumber}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            bottom: _reorder
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(28),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        widget.order.reviewedVersion == widget.order.version
                            ? 'Sudah ditinjau • siap menerima tunai'
                            : 'Belum ditinjau • perlu tinjauan sebelum bayar',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ),
          body: SafeArea(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_saving || c.busy) const LinearProgressIndicator(),
                  PendingRecovery(controller: c),
                  InfoBanner(
                    icon: Icons.info_outline,
                    tone: const BadgeStyle(
                      '',
                      AppColors.info,
                      AppColors.infoSurface,
                    ),
                    message: 'Katalog diambil saat editor dibuka. Harga katalog adalah referensi; total akhir selalu dari server.',
                  ),
                  if (!_reorder)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: SectionCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Total server sebelum edit',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  rupiah(widget.order.total),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_reorder)
                    TextFormField(
                      key: const ValueKey('reorder-customer'),
                      controller: _customer,
                      enabled: !disabled,
                      decoration: InputDecoration(
                        labelText: widget.catalog.requireCustomerName
                            ? 'Nama pelanggan (wajib)'
                            : 'Nama pelanggan',
                      ),
                      validator: (value) =>
                          widget.catalog.requireCustomerName &&
                              (value == null || value.trim().isEmpty)
                          ? 'Nama pelanggan wajib diisi'
                          : null,
                    ),
                  if (_error ?? c.error case final String error)
                    ErrorNotice(
                      message: error,
                      onClose: () {
                        setState(() => _error = null);
                        c.clearError();
                      },
                    ),
                  for (var index = 0; index < _lines.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: OrderLineEditor(
                        key: ValueKey(_lines[index].id),
                        index: index,
                        line: _lines[index].draft,
                        product: _product(_lines[index].draft.productId),
                        disabled: disabled,
                        onChanged: (draft) =>
                            setState(() => _lines[index].draft = draft),
                        onRemove: () => setState(() => _lines.removeAt(index)),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('add-product'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: disabled ? null : _addProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah produk'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const ValueKey('editor-save'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: disabled ? null : _save,
                    child: Text(
                      _saving
                          ? 'Menyimpan…'
                          : _reorder
                          ? 'Periksa & buat pesanan ulang'
                          : 'Simpan tinjauan ke server',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Perubahan daftar pesanan tidak menimpa draf ini. Jika versi berubah, server dapat menolak; kembali dan buka tinjauan terbaru.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});
  final List<CatalogProduct> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.products.where((p) {
      if (_query.isEmpty) return true;
      return p.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tambah produk',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Cari produk…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: (val) => setState(() => _query = val.trim()),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          widget.products.isEmpty
                              ? 'Katalog kosong.'
                              : 'Tidak ada produk yang cocok.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final product = filtered[i];
                          return SimpleDialogOption(
                            key: ValueKey('product-${product.id}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.md,
                            ),
                            onPressed: product.available
                                ? () => Navigator.pop(context, product)
                                : null,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: TextStyle(
                                          color: product.available
                                              ? AppColors.textPrimary
                                              : AppColors.disabled,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (!product.available)
                                        const Text(
                                          'Tidak tersedia',
                                          style: TextStyle(
                                            color: AppColors.errorText,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  rupiah(product.price),
                                  style: TextStyle(
                                    color: product.available
                                        ? AppColors.primary
                                        : AppColors.disabled,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
