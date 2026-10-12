import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../data/cash_attempt.dart';
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
  Timer? _ticker;
  String? _lastCountdown;

  @override
  void initState() {
    super.initState();
    _cash.addListener(_cashChanged);
    _lastCountdown = _countdownText();
    // Local clock only; keeps review/payment buttons honest between refreshes.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final label = _countdownText();
      if (label != _lastCountdown) {
        setState(() => _lastCountdown = label);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cash.removeListener(_cashChanged);
    _cash.dispose();
    super.dispose();
  }

  bool get _countdownVisible =>
      _order.status == 'pending' && _order.paymentStatus == 'unpaid';

  String? _countdownText() {
    if (!_countdownVisible) return null;
    return countdownLabel(_order.expiresAt.difference(DateTime.now()));
  }

  void _cashChanged() {
    if (mounted) setState(() {});
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
          '${snapshot.orderNumber} • ${snapshot.customerName}\nTotal server: ${rupiah(snapshot.total)}\nDiterima: ${rupiah(received)}\nKembalian: ${rupiah(received - snapshot.total)}\n\nPastikan uang sudah diterima. Pembayaran hanya untuk pesanan yang telah ditinjau.',
      action: 'Uang sudah diterima',
    );
    if (!yes || !mounted || !widget.controller.signedIn) return;
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

  int? get _received {
    final text = _cash.text;
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Widget _buildQuickCashChips(bool disabled) {
    final total = _order.total;
    final suggestions = <int>[total];
    for (final denom in const [20000, 50000, 100000]) {
      if (denom > total && !suggestions.contains(denom)) {
        suggestions.add(denom);
      }
    }
    if (total >= 100000) {
      final next50 = ((total + 49999) ~/ 50000) * 50000;
      if (next50 > total && !suggestions.contains(next50)) {
        suggestions.add(next50);
      }
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final amount in suggestions)
          ActionChip(
            label: Text(
              amount == total ? 'Uang Pas' : rupiah(amount),
              style: TextStyle(
                fontSize: 12,
                fontWeight: amount == total ? FontWeight.w700 : FontWeight.w600,
                color: amount == total
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
            ),
            backgroundColor: amount == total
                ? AppColors.errorSurface
                : AppColors.card,
            side: BorderSide(
              color: amount == total ? AppColors.primary : AppColors.border,
            ),
            onPressed: disabled
                ? null
                : () {
                    _cash.text = '$amount';
                  },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
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
            !(_order.status == 'completed' && current.status != 'completed')) {
          _order = current;
        }
      }
      final disabled = c.busy || _working || _confirming;
      final pendingCash = c.pendingCashFor(_order.id);
      final canReview = pendingCash == null && _order.canReview(DateTime.now());
      final canPay = pendingCash == null && _order.canPay(DateTime.now());
      final received = _received;
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            _order.orderNumber,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (c.busy || _working) const LinearProgressIndicator(),
              _SummaryCard(
                order: _order,
                countdown: _countdownText(),
                pendingCash: pendingCash,
                onRetryCash: disabled
                    ? null
                    : () => _run(() async {
                        final result = await c.retryCash(_order);
                        if (mounted && result != null) {
                          setState(() => _order = result);
                        }
                      }),
              ),
              const SizedBox(height: AppSpacing.lg),
              PendingRecovery(controller: c),
              if (_error ?? c.error case final String error)
                ErrorNotice(
                  message: error,
                  onClose: () {
                    setState(() => _error = null);
                    c.clearError();
                  },
                ),
              if (_order.items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('Item pesanan'),
                      for (var i = 0; i < _order.items.length; i++) ...[
                        if (i > 0)
                          const Divider(height: AppSpacing.lg, thickness: 1),
                        _ItemRow(line: _order.items[i]),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('Ringkasan pembayaran'),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Total server',
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
                              rupiah(_order.total),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canReview) ...[
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle('Pembayaran tunai'),
                      if (canPay)
                        Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                  prefixText: 'Rp ',
                                  helperText: 'Rupiah bulat tanpa titik atau koma, contoh 30000',
                                ),
                                validator: (value) {
                                  final amount = int.tryParse(value ?? '');
                                  return amount == null || amount < _order.total
                                      ? 'Uang diterima minimal ${rupiah(_order.total)}'
                                      : null;
                                },
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _buildQuickCashChips(disabled),
                              const SizedBox(height: AppSpacing.md),
                              if (received != null)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: received >= _order.total
                                        ? AppColors.successSurface
                                        : AppColors.neutralSurface,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.badge,
                                    ),
                                  ),
                                  child: Text(
                                    'Kembalian: ${rupiah(received - _order.total)}',
                                    style: TextStyle(
                                      color: received >= _order.total
                                          ? AppColors.success
                                          : AppColors.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.lg),
                              FilledButton(
                                key: const ValueKey('cash-submit'),
                                onPressed: disabled ? null : _pay,
                                child: const Text('Periksa pembayaran tunai'),
                              ),
                            ],
                          ),
                        ),
                      if (!canPay)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              key: const ValueKey('open-review'),
                              onPressed: disabled ? null : () => _edit(),
                              child: const Text('Tinjau & edit pesanan'),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Text(
                              'Tinjau dan simpan pesanan terlebih dahulu sebelum menerima tunai.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      if (canPay)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: TextButton(
                            key: const ValueKey('open-review'),
                            onPressed: disabled ? null : () => _edit(),
                            child: const Text('Ubah tinjauan pesanan'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (_order.canComplete) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  key: const ValueKey('complete-order'),
                  onPressed: disabled ? null : _complete,
                  child: const Text('Selesaikan pesanan'),
                ),
              ],
              if (_order.isExpired) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: const ValueKey('reorder-order'),
                  onPressed: disabled || c.hasPendingAttempt
                      ? null
                      : () => _edit(reorder: true),
                  icon: const Icon(Icons.replay),
                  label: const Text('Buat draf pesanan ulang'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Pesanan lama tetap kedaluwarsa. Pesanan baru hanya dibuat setelah konfirmasi draf.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.order,
    required this.countdown,
    required this.pendingCash,
    this.onRetryCash,
  });
  final OrderRecord order;
  final String? countdown;
  final CashAttempt? pendingCash;
  final VoidCallback? onRetryCash;

  @override
  Widget build(BuildContext context) {
    final expired = order.isExpired;
    final stateStyle = orderStateBadge(order);
    final cd = countdown;
    final attempt = pendingCash;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  order.orderNumber,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              StatusBadge(
                label: stateStyle.label,
                foreground: stateStyle.foreground,
                background: stateStyle.background,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            order.customerName.isEmpty
                ? 'Tanpa nama pelanggan'
                : order.customerName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (order.status == 'pending' && order.paymentStatus == 'unpaid')
                StatusBadge.of(order, payment: true),
              if (order.status == 'pending' && order.paymentStatus == 'unpaid')
                order.reviewedVersion == order.version
                    ? const StatusBadge(
                        label: 'Sudah ditinjau',
                        foreground: AppColors.info,
                        background: AppColors.infoSurface,
                      )
                    : const StatusBadge(
                        label: 'Perlu ditinjau',
                        foreground: AppColors.warning,
                        background: AppColors.warningSurface,
                      ),
              if (expired && order.status == 'pending')
                const StatusBadge(
                  label: 'Kedaluwarsa',
                  foreground: AppColors.errorText,
                  background: AppColors.errorSurface,
                ),
              if (order.paymentStatus == 'paid')
                const StatusBadge(
                  label: 'Lunas',
                  foreground: AppColors.success,
                  background: AppColors.successSurface,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _MetaRow(
            icon: Icons.schedule,
            text: order.createdAt == null
                ? 'Batas pembayaran: ${formatDateTime(order.expiresAt.toLocal())}'
                : 'Dibuat ${formatDateTime(order.createdAt!.toLocal())} • Batas ${formatDateTime(order.expiresAt.toLocal())}',
          ),
          if (cd != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: cd == '00:00'
                    ? AppColors.errorSurface
                    : AppColors.warningSurface,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: cd == '00:00'
                        ? AppColors.errorText
                        : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Sisa waktu bayar',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cd == '00:00'
                            ? AppColors.errorText
                            : AppColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    cd,
                    style: TextStyle(
                      color: cd == '00:00'
                          ? AppColors.errorText
                          : AppColors.warning,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (attempt != null) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBanner.warning(
              'Konfirmasi tunai belum pasti: ${rupiah(attempt.received)}, versi ${attempt.version}. Jangan meminta uang lagi.',
              title: 'Pembayaran tunai tertunda',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onRetryCash,
              child: const Text('Cek ulang konfirmasi tunai yang sama'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.line});
  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final addons = line.addonNames.isNotEmpty
        ? line.addonNames.join(', ')
        : line.addonIds.join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.neutralSurface,
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
            child: Text(
              '${line.quantity}×',
              style: const TextStyle(
                color: AppColors.textPrimary,
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
                  line.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (line.variantName.isNotEmpty)
                  Text(
                    'Varian: ${line.variantName}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                if (addons.isNotEmpty)
                  Text(
                    'Tambahan: $addons',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                if (line.notes.isNotEmpty)
                  Text(
                    'Catatan: ${line.notes}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                Text(
                  '${rupiah(line.unitPrice)} / item',
                  style: const TextStyle(
                    color: AppColors.disabled,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rupiah(line.subtotal),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
