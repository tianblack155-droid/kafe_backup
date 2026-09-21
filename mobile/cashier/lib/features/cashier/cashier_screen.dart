import 'package:flutter/material.dart';

import '../../core/realtime_client.dart';
import 'cashier_controller.dart';
import 'order_detail_screen.dart';
import 'ui_common.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({
    super.key,
    required this.controller,
    required this.sound,
    required this.onSoundChanged,
  });
  final CashierController controller;
  final bool sound;
  final ValueChanged<bool> onSoundChanged;
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
    final status = switch (c.realtimeStatus) {
      RealtimeStatus.connected => 'Realtime tersambung',
      RealtimeStatus.connecting => 'Menghubungkan realtime…',
      RealtimeStatus.polling => 'Mode polling • Pembaruan berkala',
      RealtimeStatus.stopped => 'Realtime berhenti',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir TerasKayuManis'),
        actions: [
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
      body: SafeArea(
        child: Column(
          children: [
            if (c.loading || _working) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _run(c.refresh),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          avatar: Icon(
                            c.realtimeStatus == RealtimeStatus.connected
                                ? Icons.wifi
                                : Icons.sync,
                            size: 18,
                          ),
                          label: Text(status),
                        ),
                        FilterChip(
                          key: const ValueKey('sound-toggle'),
                          selected: widget.sound,
                          onSelected: widget.onSoundChanged,
                          avatar: Icon(
                            widget.sound ? Icons.volume_up : Icons.volume_off,
                            size: 18,
                          ),
                          label: const Text('Suara pesanan baru'),
                        ),
                      ],
                    ),
                    const Text(
                      'Peringatan hanya saat aplikasi aktif. Suara mengikuti pengaturan perangkat.',
                    ),
                    PendingRecovery(controller: c),
                    if (_error ?? c.error case final String error)
                      ErrorNotice(
                        message: error,
                        onClose: () {
                          setState(() => _error = null);
                          c.clearError();
                        },
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            key: const ValueKey('tab-active'),
                            label: const Text('Aktif'),
                            selected: c.tab == 'active',
                            onSelected: disabled
                                ? null
                                : (_) => _run(() => c.changeTab('active')),
                          ),
                        ),
                        Expanded(
                          child: ChoiceChip(
                            key: const ValueKey('tab-history'),
                            label: const Text('Riwayat'),
                            selected: c.tab == 'history',
                            onSelected: disabled
                                ? null
                                : (_) => _run(() => c.changeTab('history')),
                          ),
                        ),
                      ],
                    ),
                    if (c.tab == 'history')
                      Align(
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
                    const SizedBox(height: 12),
                    if (c.orders.isEmpty && !c.loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Tidak ada pesanan di halaman ini.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    OrderClock(
                      builder: (context) => Column(
                        children: [
                          for (final order in c.orders)
                            Card(
                              child: ListTile(
                                key: ValueKey('order-${order.id}'),
                                title: Text(
                                  order.orderNumber,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (order.customerName.isNotEmpty)
                                      Text(order.customerName),
                                    Text(
                                      '${orderStatus(order)} • ${rupiah(order.total)}',
                                    ),
                                    PaymentCountdown(order: order),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
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
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
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
                        Text('Halaman ${c.offset ~/ 100 + 1}'),
                        IconButton(
                          key: const ValueKey('next-page'),
                          tooltip: 'Halaman berikutnya',
                          onPressed:
                              disabled || c.orders.isEmpty || c.offset >= 100000
                              ? null
                              : () => _run(c.nextPage),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
