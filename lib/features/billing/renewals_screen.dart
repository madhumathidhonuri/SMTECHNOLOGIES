import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/vehicle_icons.dart';
import '../../data/models/vehicle.dart';
import '../../providers/fleet_provider.dart';
import '../../shared/widgets/app_states.dart';
import 'renewal_checkout_sheet.dart';

/// Renewals & Billing screen.
///
/// Shows every vehicle that has an expiry date with a live countdown.
/// Vehicles expiring within 30 days appear first under "Needs Attention".
/// Healthy vehicles are listed below with their remaining days.
class RenewalsScreen extends ConsumerWidget {
  const RenewalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<Vehicle> all = ref.watch(fleetProvider).vehicles;

    // Vehicles expiring within 30 days (sorted most urgent first)
    final List<Vehicle> needsAttention = all
        .where((Vehicle v) => v.expiryDate != null && v.isExpiringSoon)
        .toList()
      ..sort((Vehicle a, Vehicle b) =>
          (a.daysToExpiry ?? 0).compareTo(b.daysToExpiry ?? 0));

    // Healthy vehicles — still show their countdown
    final List<Vehicle> healthy = all
        .where((Vehicle v) => v.expiryDate != null && !v.isExpiringSoon)
        .toList()
      ..sort((Vehicle a, Vehicle b) =>
          (a.daysToExpiry ?? 9999).compareTo(b.daysToExpiry ?? 9999));

    final int expired =
        needsAttention.where((Vehicle v) => v.isExpired).length;

    final bool hasAny = needsAttention.isNotEmpty || healthy.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Renewals & Billing')),
      body: !hasAny
          ? const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Nothing to renew',
              message:
                  'Subscription information for your vehicles will appear here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.lg, Gap.lg, Gap.lg, Gap.x4l),
              children: <Widget>[
                // ── Banner if anything needs attention ────────────────
                if (needsAttention.isNotEmpty)
                  _SummaryBanner(
                    expired: expired,
                    expiring: needsAttention.length - expired,
                  ),

                // ── Notification note ─────────────────────────────────
                const SizedBox(height: Gap.md),
                _NotificationNote(),

                // ── Needs attention ───────────────────────────────────
                if (needsAttention.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Gap.lg),
                  Text(
                    'NEEDS ATTENTION',
                    style: AppTypography.eyebrow(
                        theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.md),
                  ...needsAttention.map(
                    (Vehicle v) => _RenewalCard(
                      vehicle: v,
                      onRenew: () => _openCheckout(context, v),
                    ),
                  ),
                ],

                // ── Active subscriptions with countdown ───────────────
                if (healthy.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Gap.xl),
                  Text(
                    'ACTIVE SUBSCRIPTIONS',
                    style: AppTypography.eyebrow(
                        theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.md),
                  ...healthy.map(
                    (Vehicle v) => _RenewalCard(
                      vehicle: v,
                      onRenew: () => _openCheckout(context, v),
                      showRenewButton: false,
                    ),
                  ),
                ],

                const SizedBox(height: Gap.xl),

                // ── Security note ─────────────────────────────────────
                Container(
                  padding: Gap.card,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: Corners.rMd,
                    border:
                        Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.info_outline_rounded,
                          size: 17,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          'Payments are processed securely. Your renewal is '
                          'confirmed by our servers before any subscription '
                          'is extended.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _openCheckout(BuildContext context, Vehicle vehicle) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => RenewalCheckoutSheet(vehicle: vehicle),
    );
  }
}

// ── Notification info strip ──────────────────────────────────────────────────

class _NotificationNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.08),
        borderRadius: Corners.rSm,
        border: Border.all(color: AppColors.brand.withOpacity(0.2)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.notifications_active_rounded,
              size: 15, color: AppColors.brand),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'You will be notified 30 days before any subscription expires.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.brand,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary banner ───────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.expired, required this.expiring});

  final int expired;
  final int expiring;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool critical = expired > 0;
    final Color color = critical ? AppColors.danger : AppColors.idle;

    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color.withOpacity(0.18), color.withOpacity(0.06)],
        ),
        borderRadius: Corners.rLg,
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            critical ? Icons.error_rounded : Icons.schedule_rounded,
            size: 30,
            color: color,
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  critical
                      ? '$expired ${expired == 1 ? 'vehicle has' : 'vehicles have'} expired'
                      : '$expiring ${expiring == 1 ? 'renewal' : 'renewals'} due soon',
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  critical
                      ? 'Tracking has stopped for expired vehicles. Renew to restore live data.'
                      : 'Renew now to avoid any interruption to tracking.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual renewal card with countdown ───────────────────────────────────

class _RenewalCard extends StatelessWidget {
  const _RenewalCard({
    required this.vehicle,
    required this.onRenew,
    this.showRenewButton = true,
  });

  final Vehicle vehicle;
  final VoidCallback onRenew;
  final bool showRenewButton;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? days = vehicle.daysToExpiry;
    final bool expired = vehicle.isExpired;
    final bool critical = !expired && (days ?? 30) <= 7;
    final bool warning = !expired && !critical && (days ?? 30) <= 30;

    final Color accentColor = expired
        ? AppColors.danger
        : critical
            ? AppColors.idle
            : warning
                ? AppColors.idle.withOpacity(0.7)
                : AppColors.moving;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: Corners.rLg,
          border: Border.all(
            color: expired || critical
                ? accentColor.withOpacity(0.4)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: <Widget>[
              // Vehicle icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.13),
                  borderRadius: Corners.rSm,
                ),
                child: Icon(VehicleIcons.forType(vehicle.type),
                    size: 21, color: accentColor),
              ),
              const SizedBox(width: Gap.md),

              // Vehicle name + expiry date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vehicle.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Icon(Icons.event_rounded,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          vehicle.expiryDate != null
                              ? 'Expires ${Fmt.date(vehicle.expiryDate)}'
                              : 'No expiry set',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: Gap.sm),

              // Countdown badge
              _CountdownBadge(days: days, accentColor: accentColor),

              if (showRenewButton) ...<Widget>[
                const SizedBox(width: Gap.sm),
                FilledButton(
                  onPressed: onRenew,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                    backgroundColor: expired ? AppColors.danger : null,
                  ),
                  child: const Text('Renew'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Countdown badge ──────────────────────────────────────────────────────────

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.days, required this.accentColor});

  final int? days;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (days == null) return const SizedBox.shrink();

    final bool expired = days! < 0;
    final String topLabel = expired ? 'EXPIRED' : '${days!.abs()}';
    final String botLabel = expired ? '' : days == 1 ? 'DAY' : 'DAYS';

    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.12),
        borderRadius: Corners.rSm,
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            topLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: expired ? 9 : 18,
              fontWeight: FontWeight.w800,
              color: accentColor,
              height: 1.1,
            ),
          ),
          if (botLabel.isNotEmpty)
            Text(
              botLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: accentColor.withOpacity(0.8),
                letterSpacing: 0.5,
              ),
            ),
        ],
      ),
    );
  }
}
