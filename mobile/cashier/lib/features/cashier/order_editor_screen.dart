import 'package:flutter/material.dart';

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
    if (_lines.length > 50) return 'Maksimal 50 baris produk.';
    for (final line in _lines) {
      final draft = line.draft;
      final product = _product(draft.productId);
      if (product == null || !product.available) {
        return 'Produk tidak tersedia. Hapus atau ganti produk sebelum menyimpan.';
      }
      if (draft.quantity < 1 || draft.quantity > 50) {
        return 'Jumlah produk harus 1–50.';
      }
      if (draft.variantIds.length > 20 ||
          draft.addonIds.length > 20 ||
          draft.addonIds.toSet().length != draft.addonIds.length) {
        return 'Pilihan tidak valid. Maksimal 20 varian/tambahan tanpa duplikat.';
      }
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
      if (product.variants.any(
        (v) => v.available && !groups.contains(v.groupName),
      )) {
        return 'Pilih satu varian untuk setiap kelompok yang tersedia.';
      }
    }
    return null;
  }

  int? get _estimatedSubtotal {
    if (_validate() != null) return null;
    return _lines.fold<int>(0, (sum, line) {
      final p = _product(line.draft.productId)!;
      final variants = p.variants.where(
        (v) => line.draft.variantIds.contains(v.id),
      );
      final addons = p.addons.where((a) => line.draft.addonIds.contains(a.id));
      return sum +
          line.draft.quantity *
              (p.price +
                  variants.fold<int>(0, (s, v) => s + v.priceModifier) +
                  addons.fold<int>(0, (s, a) => s + a.price));
    });
  }

  Future<void> _addProduct() async {
    final product = await showDialog<CatalogProduct>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tambah produk'),
        children: [
          if (widget.catalog.products.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Katalog kosong.'),
            ),
          for (final product in widget.catalog.products)
            SimpleDialogOption(
              key: ValueKey('product-${product.id}'),
              onPressed: product.available
                  ? () => Navigator.pop(context, product)
                  : null,
              child: Text(
                '${product.name} • ${rupiah(product.price)}${product.available ? '' : ' • Tidak tersedia'}',
              ),
            ),
        ],
      ),
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
  Widget build(BuildContext context) => OrderClock(
    builder: (context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (!c.signedIn) return const Scaffold(body: SizedBox.shrink());
        final disabled =
            _saving ||
            _confirming ||
            c.busy ||
            (_reorder && c.hasPendingAttempt) ||
            (!_reorder && !widget.order.canReview(DateTime.now()));
        return PopScope(
          canPop: !_saving && !_confirming,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                _reorder
                    ? 'Draf pesanan ulang'
                    : 'Tinjau ${widget.order.orderNumber}',
              ),
            ),
            body: SafeArea(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_saving || c.busy) const LinearProgressIndicator(),
                    PendingRecovery(controller: c),
                    const Text(
                      'Pastikan menu tersedia dan sepakati perubahan dengan pelanggan sebelum menerima uang. Harga dihitung ulang saat disimpan.',
                    ),
                    if (!_reorder) PaymentCountdown(order: widget.order),
                    if (!_reorder)
                      Text(
                        'Total sebelum revisi: ${rupiah(widget.order.total)}',
                      ),
                    const SizedBox(height: 16),
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
                      ErrorNotice(message: error),
                    for (var index = 0; index < _lines.length; index++)
                      OrderLineEditor(
                        key: ValueKey(_lines[index].id),
                        index: index,
                        line: _lines[index].draft,
                        product: _product(_lines[index].draft.productId),
                        disabled: disabled,
                        onChanged: (draft) =>
                            setState(() => _lines[index].draft = draft),
                        onRemove: () => setState(() => _lines.removeAt(index)),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('add-product'),
                      onPressed: disabled || _lines.length >= 50
                          ? null
                          : _addProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah produk'),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _estimatedSubtotal == null
                                  ? 'Lengkapi pilihan untuk melihat perkiraan.'
                                  : 'Subtotal perkiraan: ${rupiah(_estimatedSubtotal!)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Pajak dan biaya layanan mengikuti perhitungan server.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('editor-save'),
                      onPressed: disabled ? null : _save,
                      child: Text(
                        _saving
                            ? 'Menyimpan…'
                            : _reorder
                            ? 'Periksa & buat pesanan ulang'
                            : 'Menu tersedia & pelanggan setuju — Simpan',
                      ),
                    ),
                    const Text(
                      'Revisi tidak memperpanjang waktu bayar. Jika pesanan berubah, buka ulang tinjauan terbaru.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
