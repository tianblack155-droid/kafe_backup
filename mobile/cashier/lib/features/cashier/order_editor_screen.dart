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
                    'Katalog diambil saat editor dibuka. Harga katalog adalah referensi; total akhir selalu dari server.',
                  ),
                  if (!_reorder)
                    Text(
                      'Total server sebelum edit: ${rupiah(widget.order.total)}',
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
                    onPressed: disabled ? null : _addProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah produk'),
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
                          : 'Simpan tinjauan ke server',
                    ),
                  ),
                  const Text(
                    'Perubahan daftar pesanan tidak menimpa draf ini. Jika versi berubah, server dapat menolak; kembali dan buka tinjauan terbaru.',
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
