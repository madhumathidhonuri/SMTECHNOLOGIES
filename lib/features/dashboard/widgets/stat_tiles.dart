import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/alerts_provider.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/fleet_provider.dart';
import 'fleet_3d_pie_chart.dart';

/// The hero panel: total fleet count with a proportional status bar and
/// four tappable status filters underneath.
///
/// Design rationale: an operator's first question is "is anything wrong right
/// now?" — so the composition bar answers it pre-attentively, before any
/// number is read.
class FleetOverviewCard extends ConsumerWidget {
  const FleetOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final FleetStats stats = ref.watch(fleetStatsProvider);
    final VehicleStatus? active = ref.watch(fleetFilterProvider);
    final int overspeedCount = ref.watch(unreadOverspeedCountProvider);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Gap.sm),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.55),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // ── Section Header ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x6610B981),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'FLEET OVERVIEW',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFF0D1B36),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (overspeedCount > 0)
                      Material(
                        color: const Color(0xFFF43F5E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => context.push('/alerts?type=overspeed'),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.speed_rounded,
                                  size: 12,
                                  color: Color(0xFFF43F5E),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$overspeedCount alert',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFF43F5E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(
                            alpha: isDark ? 0.20 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.brand.withValues(
                              alpha: isDark ? 0.38 : 0.20,
                            ),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          '${stats.total} total',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF818CF8)
                                : AppColors.brand,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),

          // ── Hero Visualization: 3D Isometric Pie Chart ─────────────
          const Fleet3DPieChart(),

          // ── Active Filter Bar / Reset Badge ───────────────────────
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Material(
                color: _getStatusColor(active).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () =>
                      ref.read(fleetFilterProvider.notifier).state = null,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_rounded,
                          size: 12,
                          color: _getStatusColor(active),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Showing ${_getStatusName(active)} • Tap to reset',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _getStatusColor(active),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: _getStatusColor(active),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.moving:
        return const Color(0xFF15803D); // Dark Green
      case VehicleStatus.idle:
        return const Color(0xFFEAB308); // Yellow
      case VehicleStatus.stopped:
        return const Color(0xFF64748B); // Grey
      case VehicleStatus.offline:
        return const Color(0xFFEF4444); // Red
      case VehicleStatus.noData:
        return const Color(0xFF18181B); // Black
    }
  }

  String _getStatusName(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.moving:
        return 'Moving';
      case VehicleStatus.idle:
        return 'Idle';
      case VehicleStatus.stopped:
        return 'Stopped';
      case VehicleStatus.offline:
        return 'Offline';
      case VehicleStatus.noData:
        return 'Unreachable';
    }
  }
}


class _OnlineRing extends StatelessWidget {
  const _OnlineRing({
    required this.percent,
    required this.online,
    required this.isDark,
  });

  final double percent;
  final int online;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      const Color(0xFF10B981).withOpacity(isDark ? 0.15 : 0.08),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 76,
            height: 76,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: percent),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.fastOutSlowIn,
              builder: (BuildContext _, double v, Widget? __) =>
                  CircularProgressIndicator(
                value: v,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                backgroundColor:
                    isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${(percent * 100).round()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1E2432),
                ),
              ),
              const Text(
                'online',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF10B981),
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

Widget _buildNoDataDropdown(
  BuildContext context,
  WidgetRef ref,
  double thresholdHours,
  bool isDark,
  Color color,
) {
  final String label = thresholdHours == 1.0 ? '1 hr' : '${thresholdHours.toInt()} hr';

  return Theme(
    data: Theme.of(context).copyWith(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
    child: PopupMenuButton<double>(
      initialValue: thresholdHours,
      tooltip: 'No Data Rule: 1hr by default, 3hr, 6hr, 24hr',
      padding: EdgeInsets.zero,
      elevation: 8,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      onSelected: (double val) {
        ref.read(noDataThresholdProvider.notifier).setThreshold(val);
        final String optName = val == 1.0 ? '1 hr (Default)' : '${val.toInt()} hr';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No Data Rule threshold set to $optName'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      itemBuilder: (BuildContext ctx) => AppConfig.noDataThresholdOptions.map((double opt) {
        final String optLabel = opt == 1.0 ? '1 hr (Default)' : '${opt.toInt()} hr';
        final bool isSelected = thresholdHours == opt;
        return PopupMenuItem<double>(
          value: opt,
          height: 38,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: isSelected ? const Color(0xFF0EA5E9) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                optLabel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0EA5E9).withValues(alpha: isDark ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF0EA5E9).withValues(alpha: 0.45),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0EA5E9),
              ),
            ),
            const SizedBox(width: 1),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 14,
              color: Color(0xFF0EA5E9),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.dropdown,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final Widget? dropdown;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count vehicles',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: color, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: selected
                  ? color.withValues(alpha: 0.22)
                  : const Color(0xFFC7D7EC).withOpacity(0.5),
              blurRadius: selected ? 8 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: Corners.rMd,
            splashColor: color.withValues(alpha: 0.2),
            highlightColor: color.withValues(alpha: 0.1),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 2.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? color
                        : (isDark ? color.withValues(alpha: 0.8) : color),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1E2432),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.2,
                      color: selected
                          ? color
                          : (isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B)),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (dropdown != null) ...[
                    const SizedBox(height: 4),
                    dropdown!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Attention strip: only rendered when something actually needs action.
class AttentionStrip extends ConsumerWidget {
  const AttentionStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FleetStats stats = ref.watch(fleetStatsProvider);

    final List<Widget> items = <Widget>[];

    if (stats.expiringSoon > 0) {
      items.add(_AttentionChip(
        icon: Icons.event_busy_rounded,
        label: '${stats.expiringSoon} expiring soon',
        color: AppColors.idle,
        onTap: () {},
      ));
    }

    if (stats.totalDistanceToday > 0) {
      items.add(_AttentionChip(
        icon: Icons.route_rounded,
        label: '${Fmt.distance(stats.totalDistanceToday)} today',
        color: AppColors.signal,
        onTap: () {},
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: Gap.sm),
          itemBuilder: (BuildContext _, int i) => items[i],
        ),
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withOpacity(0.12),
        borderRadius: Corners.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: Corners.rPill,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}
