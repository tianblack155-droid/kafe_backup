import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import 'cashier_controller.dart';
import 'order_editor_screen.dart';
import 'ui_common.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.controller,
    required this.order,
  });
  final CashierController controller;
  final OrderRecord order;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late OrderRecord _order = widget.order;
  final _cash = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _working = false;
  bool _confirming = false;
  String? _error;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || widget.controller.busy) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tindakan gagal. Muat ulang dan periksa status sebelum mencoba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit({bool reorder = false}) async {
    if (_working || _confirming || widget.controller.busy) return;
    final snapshot = _order;
    Catalog? catalog;
    ReorderDraft? draft;
    await _run(() async {
      // Fetch on every editor entry, never reuse stale menu data.
      draft = reorder ? await widget.controller.prepareReorder(snapshot) : null;
      catalog = await widget.controller.menu();
    });
    if (!mounted || !widget.controller.signedIn || catalog == null) return;
    // The editor owns its work; waiting for its route is not a request.
    final result = await Navigator.of(context).push<OrderRecord>(
      MaterialPageRoute(
        builder: (_) => OrderEditorScreen(
          controller: widget.controller,
          catalog: catalog!,
          order: snapshot,
          reorderDraft: draft,
        ),
      ),
    );
    if (mounted && result != null) setState(() => _order = result);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    setState(() => _confirming = true);
    try {
      return await confirmAction(
        context,
        title: title,
        message: message,
        action: action,
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _pay() async {
    if (_working || _confirming || widget.controller.busy) return;
    if (!_form.currentState!.validate()) return;
    final received = int.parse(_cash.text);
    final snapshot = _order;
    final yes = await _confirm(
      title: 'Konfirmasi uang tunai',
      message:
          '${snapshot.orderNumber} • ${snapshot.customerName}\nTotal server: ${rupiah(snapshot.total)}\nDiterima: ${rupiah(received)}\nKembalian: ${rupiah(received - snapshot.total)}\n\nPastikan uang sudah diterima. Pembayaran hanya untuk versi yang telah ditinjau.',
      action: 'Uang sudah diterima',
    );
    if (!yes || !mounted || !widget.controller.signedIn) return;
    if (!snapshot.canPay(DateTime.now()) ||
        _order.version != snapshot.version) {
      setState(
        () => _error = 'Pesanan berubah atau waktu habis. Muat ulang sebelum menerima uang.',
      );
      return;
    }
    await _run(() async {
      final result = await widget.controller.pay(snapshot, received);
      if (mounted && result != null) setState(() => _order = result);
    });
  }

  Future<void> _complete() async {
    if (_working || _confirming || widget.controller.busy) return;
    final snapshot = _order;
    if (!await _confirm(
      title: 'Selesaikan pesanan?',
      message:
          '${snapshot.orderNumber} • ${snapshot.customerName}\nPastikan pesanan lunas sudah diserahkan kepada pelanggan.',
      action: 'Ya, selesaikan',
    )) {
      return;
    }
    if (!mounted || !widget.controller.signedIn) return;
    await _run(() async {
      final result = await widget.controller.complete(snapshot);
      if (mounted && result != null) setState(() => _order = result);
    });
  }

  @override
  Widget build(BuildContext context) => OrderClock(
    builder: (context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (!c.signedIn) return const Scaffold(body: SizedBox.shrink());
        // Keep cash controller and route state; only replace the server snapshot.
        for (final current in c.orders) {
          if (current.id == _order.id &&
              current.version >= _order.version &&
              !(_order.paymentStatus == 'paid' &&
                  current.paymentStatus != 'paid') &&
              !(_order.status == 'completed' &&
                  current.status != 'completed')) {
            _order = current;
          }
        }
        final disabled = c.busy || _working || _confirming;
        final pendingCash = c.pendingCashFor(_order.id);
        final canReview =
            pendingCash == null && _order.canReview(DateTime.now());
        final canPay = pendingCash == null && _order.canPay(DateTime.now());
        return Scaffold(
          appBar: AppBar(
            title: Text('Pesanan ${_order.orderNumber}'),
            actions: [
              IconButton(
                tooltip: 'Muat ulang pesanan',
                onPressed: disabled ? null : () => _run(c.refresh),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (c.busy || _working) const LinearProgressIndicator(),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _order.orderNumber,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_order.customerName.isNotEmpty)
                          Text(_order.customerName),
                        const SizedBox(height: 8),
                        Text(
                          orderStatus(_order),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        PaymentCountdown(order: _order),
                        if (_order.status == 'pending' &&
                            _order.paymentStatus == 'unpaid')
                          const Text(
                            'Revisi tidak memperpanjang waktu pembayaran.',
                          ),
                        if (_order.canComplete)
                          const Text(
                            'Tandai selesai setelah seluruh item diantar.',
                          ),
                      ],
                    ),
                  ),
                ),
                PendingRecovery(controller: c),
                if (pendingCash != null) ...[
                  Text(
                    'Konfirmasi tunai belum pasti: ${rupiah(pendingCash.received)}, versi ${pendingCash.version}. Jangan meminta uang lagi.',
                  ),
                  OutlinedButton(
                    onPressed: disabled
                        ? null
                        : () => _run(() async {
                            final result = await c.retryCash(_order);
                            if (mounted && result != null) {
                              setState(() => _order = result);
                            }
                          }),
                    child: const Text('Cek ulang konfirmasi tunai yang sama'),
                  ),
                ],
                if (_error ?? c.error case final String error)
                  ErrorNotice(message: error),
                const SizedBox(height: 16),
                for (final line in _order.items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${line.quantity} × ${line.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${rupiah(line.unitPrice)} / item • ${rupiah(line.subtotal)}',
                          ),
                          if (line.variantName.isNotEmpty)
                            Text('Varian: ${line.variantName}'),
                          if (line.addonNames.isNotEmpty)
                            Text('Tambahan: ${line.addonNames.join(', ')}'),
                          if (line.notes.isNotEmpty)
                            Text('Catatan: ${line.notes}'),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        const Text('Total pesanan'),
                        Text(
                          rupiah(_order.total),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (canReview)
                  OutlinedButton.icon(
                    key: const ValueKey('open-review'),
                    onPressed: disabled ? null : () => _edit(),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Cek menu / revisi sebelum bayar'),
                  ),
                if (!canPay && canReview)
                  const Text(
                    'Tinjau dan simpan pesanan terlebih dahulu sebelum menerima tunai.',
                  ),
                if (canPay)
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          'Menu sudah diperiksa. Total yang disepakati: ${rupiah(_order.total)}',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('cash-received'),
                          controller: _cash,
                          enabled: !disabled,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(16),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Uang diterima (Rp)',
                            helperText:
                                'Masukkan nominal tanpa titik atau koma.',
                          ),
                          validator: (value) {
                            final amount = int.tryParse(value ?? '');
                            if (amount != null && amount > 1000000000000) {
                              return 'Nominal melebihi batas pembayaran.';
                            }
                            return amount == null || amount < _order.total
                                ? 'Uang diterima minimal ${rupiah(_order.total)}'
                                : null;
                          },
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _cash,
                          builder: (context, value, _) {
                            final amount = int.tryParse(value.text);
                            final change = amount == null
                                ? null
                                : amount - _order.total;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                change == null
                                    ? 'Kembalian: —'
                                    : change < 0
                                    ? 'Uang kurang: ${rupiah(-change)}'
                                    : 'Kembalian: ${rupiah(change)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const ValueKey('cash-submit'),
                          onPressed: disabled ? null : _pay,
                          child: const Text('Konfirmasi tunai lunas'),
                        ),
                      ],
                    ),
                  ),
                if (_order.canComplete)
                  FilledButton(
                    key: const ValueKey('complete-order'),
                    onPressed: disabled ? null : _complete,
                    child: const Text('Semua item sudah diantar — Selesai'),
                  ),
                if (_order.isExpired)
                  FilledButton.icon(
                    key: const ValueKey('reorder-order'),
                    onPressed: disabled || c.hasPendingAttempt
                        ? null
                        : () => _edit(reorder: true),
                    icon: const Icon(Icons.replay),
                    label: const Text('Buat draf pesanan ulang'),
                  ),
                if (_order.isExpired)
                  const Text(
                    'Pesanan lama tetap kedaluwarsa. Pesanan baru hanya dibuat setelah konfirmasi draf.',
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
