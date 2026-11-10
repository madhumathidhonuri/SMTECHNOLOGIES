import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/vehicle.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/connectivity_banner.dart';
import 'widgets/stat_tiles.dart';
import 'widgets/vehicle_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(fleetProvider.notifier).load();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final FleetState fleet = ref.watch(fleetProvider);
    final int alertCount = ref.watch(unreadAlertsCountProvider);
    final List<Vehicle> vehicles = ref.watch(filteredVehiclesProvider);
    final String? name = ref.watch(authProvider).user?.name;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 100,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            // ── Header ─────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              toolbarHeight: 88,
              backgroundColor: theme.colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              titleSpacing: Gap.lg,
              title: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: [
                        Text(
                          _timeGreeting(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('👋', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (name ?? '').trim().isNotEmpty
                          ? (name ?? '').trim()
                          : 'Operator',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 11,
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          Fmt.date(DateTime.now()),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Direct Bell Icon (No card, bold rounded bell)
                      IconButton(
                        tooltip: 'Alerts',
                        onPressed: () => context.push('/alerts'),
                        icon: Badge(
                          isLabelVisible: alertCount > 0,
                          backgroundColor: const Color(0xFFEF4444),
                          textColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          label: Text(alertCount > 99 ? '99+' : '$alertCount'),
                          child: Icon(
                            alertCount > 0
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_rounded,
                            size: 24,
                            color: isDark
                                ? const Color(0xFFFBBF24) // Radiant Gold
                                : const Color(0xFFD97706), // Rich Metallic Gold
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Direct Person Icon (No letter avatar, no card box)
                      IconButton(
                        tooltip: 'Profile',
                        onPressed: () => context.push('/profile-settings'),
                        icon: Icon(
                          Icons.person_rounded,
                          size: 26,
                          color: isDark ? const Color(0xFF818CF8) : AppColors.brand,
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                    ],
                  ),
                ),
              ],
            ),

            // ── Overview ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const OfflineNotice(),
                    // ── Search Bar directly above Total Fleet card ───────
                    Container(
                      margin: const EdgeInsets.only(top: 2, bottom: Gap.sm),
                      padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: const Color(0xFFC7D7EC).withOpacity(0.55),
                            blurRadius: 14,
                            spreadRadius: 0,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Left Highlighted Search Icon Badge
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F6FD),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: Color(0xFF1E60FF),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Search Text Field
                          Expanded(
                            child: TextField(
                              controller: _search,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0D1B36),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search plate, name, driver or IMEI...',
                                hintStyle: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF7A8FA8),
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onPressed: () {
                                          _search.clear();
                                          ref.read(fleetSearchProvider.notifier).state = '';
                                          setState(() {});
                                        },
                                      ),
                              ),
                              onChanged: (String v) {
                                ref.read(fleetSearchProvider.notifier).state = v;
                                setState(() {});
                              },
                            ),
                          ),

                          ],
                      ),
                    ),
                    const FleetOverviewCard()
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.08),
                    const AttentionStrip(),
                  ],
                ),
              ),
            ),

            // ── List header ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xs),
                child: Row(
                  children: <Widget>[
                    Text('Vehicles', style: theme.textTheme.titleLarge),
                    const SizedBox(width: Gap.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: Corners.rPill,
                      ),
                      child: Text(
                        '${vehicles.length}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const Spacer(),
                    if (_search.text.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          _search.clear();
                          ref.read(fleetSearchProvider.notifier).state = '';
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        label: const Text('Clear search'),
                      ),
                    if (ref.watch(fleetFilterProvider) != null)
                      TextButton.icon(
                        onPressed: () =>
                            ref.read(fleetFilterProvider.notifier).state = null,
                        icon:
                            const Icon(Icons.filter_alt_off_rounded, size: 16),
                        label: const Text('Clear filter'),
                      ),
                  ],
                ),
              ),
            ),

            // ── Refresh indicator (after resume from background) ─────
            if (fleet.isRefreshing && fleet.vehicles.isNotEmpty)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),

            // ── Body ─────────────────────────────────────────────────
            if (fleet.isLoading && fleet.vehicles.isEmpty)
              const SliverToBoxAdapter(child: ListSkeleton())
            else if (fleet.error != null && fleet.vehicles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(message: fleet.error!, onRetry: _refresh),
              )
            else if (vehicles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: fleet.vehicles.isEmpty
                      ? Icons.no_transfer_rounded
                      : Icons.search_off_rounded,
                  title:
                      fleet.vehicles.isEmpty ? 'No vehicles yet' : 'No matches',
                  message: fleet.vehicles.isEmpty
                      ? 'Vehicles added to your account by your provider will '
                          'appear here automatically.'
                      : 'Try a different search term or clear the active filter.',
                  actionLabel: fleet.vehicles.isEmpty ? null : 'Clear filters',
                  onAction: fleet.vehicles.isEmpty
                      ? null
                      : () {
                          _search.clear();
                          ref.read(fleetSearchProvider.notifier).state = '';
                          ref.read(fleetFilterProvider.notifier).state = null;
                          setState(() {});
                        },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    Gap.lg, 0, Gap.lg, Gap.navClearance),
                sliver: SliverList.builder(
                  itemCount: vehicles.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Vehicle v = vehicles[index];
                    return VehicleCard(
                      key: ValueKey<String>(v.id.isNotEmpty ? v.id : 'veh_$index'),
                      vehicle: v,
                      onTap: () => context.push('/vehicle/${v.id}'),
                      onTrack: () {
                        if (v.hasLocation) {
                          context.push('/vehicle-map?focus=${v.id}');
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _timeGreeting() {
    final int hour = DateTime.now().hour;
    return hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
  }

  String _greeting(String? name) {
    final String part = _timeGreeting();
    final String clean = (name ?? '').trim();
    return clean.isEmpty ? part : '$part,\n$clean';
  }
}
