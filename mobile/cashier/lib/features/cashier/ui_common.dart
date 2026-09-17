import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'cashier_controller.dart';

// All monetary values stay integer Rupiah; no floating-point conversion.
String rupiah(int amount) => 'Rp $amount';
String orderStatus(OrderRecord order) {
  if (order.isExpired) return 'Kedaluwarsa';
  if (order.status == 'completed') return 'Selesai';
  if (order.paymentStatus == 'paid') return 'Lunas';
  if (order.reviewedVersion == order.version) {
    return 'Sudah ditinjau • Belum dibayar';
  }
  return 'Perlu ditinjau • Belum dibayar';
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            key: const ValueKey('confirm-no'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey('confirm-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.onClose});
  final String message;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Tutup pesan',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    ),
  );
}

class PendingRecovery extends StatefulWidget {
  const PendingRecovery({super.key, required this.controller});
  final CashierController controller;
  @override
  State<PendingRecovery> createState() => _PendingRecoveryState();
}

class _PendingRecoveryState extends State<PendingRecovery> {
  bool _retrying = false;
  String? _error;
  Future<void> _retry() async {
    if (_retrying || widget.controller.busy) return;
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      final result = await widget.controller.retryPending();
      if (mounted && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pesanan ${result.orderNumber} berhasil dipulihkan'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Belum dapat memastikan hasil. Coba lagi dengan percobaan tersimpan.',
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.hasPendingAttempt) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pesanan ulang belum pasti',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Jangan buat pesanan baru. Percobaan tersimpan tetap tersedia setelah masuk kembali. Coba lagi memakai permintaan yang sama untuk memastikan hasil tanpa membuat duplikat.',
            ),
            if (_error != null) Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('retry-pending'),
              onPressed: _retrying || widget.controller.busy ? null : _retry,
              child: Text(
                _retrying ? 'Memastikan hasil…' : 'Coba lagi pesanan tersimpan',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
