import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'cashier_controller.dart';
import 'order_detail_screen.dart';
import 'ui_common.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({
    super.key,
    required this.controller,
    required this.sound,
    required this.onSoundChanged,
    this.demo = false,
  });
  final CashierController controller;
  final bool sound;
  final ValueChanged<bool> onSoundChanged;
  final bool demo;
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  String? _error;
  bool _working = false;
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
          () => _error = 'Permintaan gagal. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final disabled = c.busy || c.loading || _working;
    final initialLoad = c.loading && c.orders.isEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, c, disabled),
            _buildTabs(c, disabled),
            if (c.tab == 'history')
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    key: const ValueKey('expired-filter'),
                    label: const Text('Hanya kedaluwarsa'),
                    selected: c.expiredOnly,
                    onSelected: disabled
                        ? null
                        : (value) => _run(() => c.setExpiredOnly(value)),
                  ),
                ),
              ),
            if (c.loading || _working)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _run(c.refresh),
                child: ListView(
                  key: const ValueKey('order-list'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    PendingRecovery(controller: c),
                    if (_error ?? c.error case final String error)
                      ErrorNotice(
                        message: error,
                        onClose: () {
                          setState(() => _error = null);
                          c.clearError();
                        },
                      ),
                    if (initialLoad)
                      const LoadingView(message: 'Memuat pesanan…')
                    else if (c.orders.isEmpty)
                      _emptyState(c),
                    for (final order in c.orders)
                      _OrderCard(
                        order: order,
                        enabled: !c.busy,
                        onTap: c.busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => OrderDetailScreen(
                                    controller: c,
                                    order: order,
                                  ),
                                ),
                              ),
                      ),
                    if (c.orders.isNotEmpty || initialLoad)
                      _buildPagination(c, disabled),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    CashierController c,
    bool disabled,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.demo)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoBanner(
                icon: Icons.science_outlined,
                tone: BadgeStyle(
                  '',
                  AppColors.warning,
                  AppColors.warningSurface,
                ),
                message:
                    'DEMO • Data lokal — perubahan tidak disimpan ke server.',
              ),
            ),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_cafe,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TerasKayuManis',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      'Kasir • Pembayaran tunai',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('refresh'),
                tooltip: 'Muat ulang pesanan',
                onPressed: disabled ? null : () => _run(c.refresh),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Keluar',
                onPressed: disabled
                    ? null
                    : () async {
                        if (await confirmAction(
                          context,
                          title: 'Keluar dari kasir?',
                          message: 'Percobaan pesanan ulang yang belum pasti tetap tersimpan untuk akun ini.',
                          action: 'Keluar',
                        )) {
                          await _run(c.logout);
                        }
                      },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConnectionStatusIndicator(status: c.realtimeStatus),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.sound ? Icons.volume_up : Icons.volume_off,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Suara pesanan baru',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      key: const ValueKey('sound-toggle'),
                      value: widget.sound,
                      onChanged: disabled ? null : widget.onSoundChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Text(
            'Peringatan hanya saat aplikasi aktif. Suara mengikuti pengaturan perangkat.',
            style: TextStyle(color: AppColors.disabled, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(CashierController c, bool disabled) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        _TabButton(
          key: const ValueKey('tab-active'),
          label: 'Aktif',
          selected: c.tab == 'active',
          onPressed: disabled ? null : () => _run(() => c.changeTab('active')),
        ),
        _TabButton(
          key: const ValueKey('tab-history'),
          label: 'Riwayat',
          selected: c.tab == 'history',
          onPressed: disabled ? null : () => _run(() => c.changeTab('history')),
        ),
      ],
    ),
  );

  Widget _emptyState(CashierController c) => EmptyStateView(
    icon: c.tab == 'active' ? Icons.receipt_long : Icons.history,
    title: c.tab == 'active'
        ? 'Belum ada pesanan aktif'
        : 'Riwayat masih kosong',
    message: c.tab == 'active'
        ? 'Pesanan baru dari pelanggan akan muncul di sini secara langsung.'
        : c.expiredOnly
        ? 'Tidak ada pesanan kedaluwarsa pada halaman ini.'
        : 'Pesanan selesai dan kedaluwarsa akan tampil di sini.',
  );

  Widget _buildPagination(CashierController c, bool disabled) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          key: const ValueKey('previous-page'),
          tooltip: 'Halaman sebelumnya',
          onPressed: disabled || c.offset == 0
              ? null
              : () => _run(c.previousPage),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          'Halaman ${c.offset ~/ 100 + 1}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        IconButton(
          key: const ValueKey('next-page'),
          tooltip: 'Halaman berikutnya',
          onPressed: disabled || c.orders.isEmpty || c.offset >= 100000
              ? null
              : () => _run(c.nextPage),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onPressed,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.enabled, this.onTap});
  final dynamic order;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final record = order;
    final badge = statusBadge(record);
    final created = record.createdAt as DateTime?;
    final customer = (record.customerName as String).isEmpty
        ? 'Tanpa nama'
        : record.customerName as String;
    final timeParts = <String>[
      if (created != null) 'Dibuat ${formatDateTime(created.toLocal())}',
      if (record.status == 'pending' && record.paymentStatus == 'unpaid')
        'Batas ${formatDateTime((record.expiresAt as DateTime).toLocal())}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        key: ValueKey('order-${record.id}'),
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      record.orderNumber as String,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(
                    label: badge.label,
                    foreground: badge.foreground,
                    background: badge.background,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      customer,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (timeParts.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  timeParts.join(' • '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          rupiah(record.total as int),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Detail',
                    style: TextStyle(
                      color: enabled ? AppColors.primary : AppColors.disabled,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: enabled ? AppColors.primary : AppColors.disabled,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
