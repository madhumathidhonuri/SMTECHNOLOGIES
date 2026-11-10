import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/models/alert.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import '../../core/utils/formatters.dart';
import '../live_map/providers/live_map_providers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';

/// Root shell: owns the bottom navigation and starts the real-time session
/// once, for the whole authenticated experience.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<dynamic>? _socketSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  Future<void> _startSession() async {
    if (!mounted) return;

    // 1 ─ REST snapshot first so the first frame is real data.
    await ref.read(fleetProvider.notifier).load();
    if (!mounted) return;

    // 2 ─ Then bring up the live channel and join the org room.
    await ref.read(socketServiceProvider).connect();
    if (!mounted) return;
    ref.read(fleetProvider.notifier).attachSocket();

    // 3 ─ Global listener for real-time system notifications (replaces snackbar).
    _socketSub = ref.read(socketServiceProvider).events$.listen((event) {
      // FCM background and foreground handlers automatically handle push notifications,
      // so we don't need to manually trigger local notifications from the UI shell.
    });
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  DateTime? _lastPressedAt;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        if (widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
          return;
        }

        final DateTime now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        extendBody: true,
        body: widget.navigationShell,
        bottomNavigationBar: _buildBottomNav(context),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final int current = widget.navigationShell.currentIndex;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    final List<({IconData icon, String label})> tabs = [
      (icon: Icons.dashboard_rounded, label: 'Dashboard'),
      (icon: Icons.explore_rounded, label: 'Map'),
      (icon: Icons.analytics_rounded, label: 'Reports'),
      (icon: Icons.route_rounded, label: 'Trips'),
      (icon: Icons.person_rounded, label: 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.55),
            offset: const Offset(0, -4),
            blurRadius: 18,
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (int index) {
              final bool isSelected = current == index;
              final tab = tabs[index];

              return Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.navigationShell.goBranch(
                      index,
                      initialLocation: index == current,
                    );
                  },
                  splashColor: const Color(0xFF1E60FF).withOpacity(0.08),
                  highlightColor: Colors.transparent,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: isSelected ? 8 : 4,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF1E60FF).withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tab.icon,
                            size: 21,
                            color: isSelected
                                ? const Color(0xFF1E60FF)
                                : const Color(0xFF637691),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tab.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight:
                                    isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? const Color(0xFF1E60FF)
                                    : const Color(0xFF637691),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
