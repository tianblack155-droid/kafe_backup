import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/realtime_client.dart';
import '../../domain/models.dart';
import 'cashier_controller.dart';

// All monetary values stay integer Rupiah; no floating-point conversion.
String rupiah(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return 'Rp ${negative ? '-' : ''}$buffer';
}

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String formatTime(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

String formatDateTime(DateTime local) =>
    '${local.day} ${_months[local.month - 1]} ${local.year}, ${formatTime(local)}';

/// Remaining time rendered as `mm:ss`, or `h:mm:ss` past an hour. Never goes
/// negative so an expired countdown reads `00:00`.
String countdownLabel(Duration remaining) {
  final ms = remaining.inMilliseconds;
  final seconds = ms <= 0 ? 0 : (ms / 1000).ceil();
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  final two = _pad2;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(secs)}'
      : '${two(minutes)}:${two(secs)}';
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String orderStatus(OrderRecord order) {
  if (order.isExpired) return 'Kedaluwarsa';
  if (order.status == 'completed') return 'Selesai';
  if (order.paymentStatus == 'paid') return 'Lunas';
  if (order.reviewedVersion == order.version) {
    return 'Sudah ditinjau • Belum dibayar';
  }
  return 'Perlu ditinjau • Belum dibayar';
}

/// Semantic badge styling: one pale background, one readable foreground and a
/// short label per state. Color never carries the meaning alone.
class BadgeStyle {
  const BadgeStyle(this.label, this.foreground, this.background);
  final String label;
  final Color foreground;
  final Color background;
}

/// Combined review/payment badge used on order cards. Independent statuses
/// (order status, payment, review) are still rendered separately on details.
BadgeStyle statusBadge(OrderRecord order) {
  if (order.status == 'cancelled') {
    return const BadgeStyle(
      'Dibatalkan',
      AppColors.textSecondary,
      AppColors.neutralSurface,
    );
  }
  if (order.isExpired) {
    return const BadgeStyle(
      'Kedaluwarsa',
      AppColors.errorText,
      AppColors.errorSurface,
    );
  }
  if (order.status == 'completed') {
    return const BadgeStyle(
      'Selesai',
      AppColors.textSecondary,
      AppColors.neutralSurface,
    );
  }
  if (order.paymentStatus == 'paid') {
    return const BadgeStyle(
      'Lunas',
      AppColors.success,
      AppColors.successSurface,
    );
  }
  if (order.reviewedVersion == order.version) {
    return const BadgeStyle(
      'Siap bayar',
      AppColors.info,
      AppColors.infoSurface,
    );
  }
  return const BadgeStyle(
    'Perlu ditinjau',
    AppColors.warning,
    AppColors.warningSurface,
  );
}

BadgeStyle orderStateBadge(OrderRecord order) {
  if (order.status == 'pending') {
    return const BadgeStyle(
      'Menunggu',
      AppColors.textSecondary,
      AppColors.neutralSurface,
    );
  }
  if (order.status == 'confirmed') {
    return const BadgeStyle(
      'Terkonfirmasi',
      AppColors.success,
      AppColors.successSurface,
    );
  }
  if (order.status == 'completed') {
    return const BadgeStyle(
      'Selesai',
      AppColors.textSecondary,
      AppColors.neutralSurface,
    );
  }
  if (order.status == 'cancelled') {
    return const BadgeStyle(
      'Dibatalkan',
      AppColors.textSecondary,
      AppColors.neutralSurface,
    );
  }
  return statusBadge(order);
}

BadgeStyle paymentBadge(OrderRecord order) => order.paymentStatus == 'paid'
    ? const BadgeStyle('Lunas', AppColors.success, AppColors.successSurface)
    : const BadgeStyle('Belum dibayar', AppColors.info, AppColors.infoSurface);

/// Realtime connection pill. States are never faked: each RealtimeStatus
/// maps to its own label and tone.
class ConnectionStatusIndicator extends StatelessWidget {
  const ConnectionStatusIndicator({super.key, required this.status});
  final RealtimeStatus status;

  BadgeStyle get _style => switch (status) {
    RealtimeStatus.connected => const BadgeStyle(
      'Tersambung',
      AppColors.success,
      AppColors.successSurface,
    ),
    RealtimeStatus.connecting => const BadgeStyle(
      'Menghubungkan…',
      AppColors.warning,
      AppColors.warningSurface,
    ),
    RealtimeStatus.polling => const BadgeStyle(
      'Mode polling',
      AppColors.info,
      AppColors.infoSurface,
    ),
    RealtimeStatus.stopped => const BadgeStyle(
      'Terhenti',
      AppColors.errorText,
      AppColors.errorSurface,
    ),
  };

  String get _hint => switch (status) {
    RealtimeStatus.connected => 'Realtime tersambung',
    RealtimeStatus.connecting => 'Menghubungkan realtime…',
    RealtimeStatus.polling => 'Mode polling • Pembaruan berkala',
    RealtimeStatus.stopped => 'Realtime berhenti',
  };

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Tooltip(
      message: _hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: style.foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              style.label,
              style: TextStyle(
                color: style.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
  });
  final String label;
  final Color foreground;
  final Color background;

  factory StatusBadge.of(OrderRecord order, {bool payment = false}) {
    final style = payment ? paymentBadge(order) : statusBadge(order);
    return StatusBadge(
      label: style.label,
      foreground: style.foreground,
      background: style.background,
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.badge),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    ),
  );
}

/// White bordered container used for every grouped block of information.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Small inline banner for warnings and confirmations. `tone` picks the pale
/// surface; text stays readable foreground.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.tone = const BadgeStyle(
      '',
      AppColors.textSecondary,
      AppColors.neutralSurface,
    ),
    this.icon,
    this.title,
    this.onClose,
  });
  final String message;
  final BadgeStyle tone;
  final IconData? icon;
  final String? title;
  final VoidCallback? onClose;

  factory InfoBanner.warning(String message, {String? title}) => InfoBanner(
    message: message,
    title: title,
    icon: Icons.error_outline,
    tone: const BadgeStyle('', AppColors.warning, AppColors.warningSurface),
  );

  factory InfoBanner.error(String message) => InfoBanner(
    message: message,
    icon: Icons.error_outline,
    tone: const BadgeStyle('', AppColors.errorText, AppColors.errorSurface),
  );

  factory InfoBanner.success(String message, {String? title}) => InfoBanner(
    message: message,
    title: title,
    icon: Icons.check_circle_outline,
    tone: const BadgeStyle('', AppColors.success, AppColors.successSurface),
  );

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: tone.background,
      borderRadius: BorderRadius.circular(AppRadius.badge + 2),
      border: Border.all(color: tone.foreground.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Text(
                  title!,
                  style: TextStyle(
                    color: tone.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (title != null) const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: 'Tutup pesan',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    ),
  );
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
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        actions: [
          TextButton(
            key: const ValueKey('confirm-no'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey('confirm-yes'),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
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
  Widget build(BuildContext context) => InfoBanner(
    message: message,
    onClose: onClose,
    icon: Icons.error_outline,
    tone: const BadgeStyle('', AppColors.errorText, AppColors.errorSurface),
  );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'Memuat data…'});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl * 2),
    child: Column(
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    ),
  );
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.neutralSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          icon: Icons.sync_problem,
          tone: const BadgeStyle(
            '',
            AppColors.warning,
            AppColors.warningSurface,
          ),
          title: 'Pesanan ulang belum pasti',
          message: 'Jangan buat pesanan baru. Percobaan tersimpan tetap tersedia setelah masuk kembali. Coba lagi memakai permintaan yang sama untuk memastikan hasil tanpa membuat duplikat.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.errorText, fontSize: 13),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          key: const ValueKey('retry-pending'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warning,
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: _retrying || widget.controller.busy ? null : _retry,
          child: Text(
            _retrying ? 'Memastikan hasil…' : 'Coba lagi pesanan tersimpan',
          ),
        ),
      ],
    );
  }
}
