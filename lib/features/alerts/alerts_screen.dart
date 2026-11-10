import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/backend_capabilities.dart';
import '../../core/network/api_exception.dart';
import '../../core/realtime/socket_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/geocoder.dart';
import '../../core/utils/vehicle_icons.dart';
import '../../data/models/alert.dart';
import '../../data/models/vehicle.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/core_providers.dart';
import '../../core/notifications/push_service.dart';
import '../../providers/fleet_provider.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/connectivity_banner.dart';

/// Paginated historical alerts, grouped by day.
///
/// Foreground `alert:new` socket events prepend to the list; while the app is
/// backgrounded the same events arrive as FCM push instead.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key, this.vehicleId, this.alertId, this.typeFilter});

  final String? vehicleId;
  final String? alertId;
  final String? typeFilter;

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  final ScrollController _scroll = ScrollController();

  final List<FleetAlert> _alerts = <FleetAlert>[];
  String? _typeFilter;
  String? _selectedVehicleId;
  String _timeFilter = 'all'; // 'all', 'today', 'yesterday', 'week'
  bool _sortNewestFirst = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;

  StreamSubscription<SocketEvent>? _socketSub;

  static const List<(String?, String)> _filters = <(String?, String)>[
    (null, 'All'),
    ('critical', 'Critical'),
    ('overspeed', 'Overspeed'),
    ('idle', 'Idling & Parking'),
    ('geofence', 'Geofence'),
    ('ignition', 'Ignition & Movement'),
    ('power', 'Power & Battery'),
    ('sos', 'SOS & Theft'),
    ('harsh', 'Harsh Events'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedVehicleId = (widget.vehicleId != null && widget.vehicleId!.isNotEmpty) ? widget.vehicleId : null;
    _typeFilter = (widget.typeFilter != null && widget.typeFilter!.isNotEmpty) ? widget.typeFilter : null;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(reset: true);
      _listenToSocket();
    });
  }

  bool _matchesFilter(FleetAlert alert, String? filter) {
    if (filter == null || filter.isEmpty) return true;

    final String type = alert.type.toLowerCase().trim();
    final String title = alert.title.toLowerCase();
    final String message = alert.message.toLowerCase();

    return switch (filter) {
      'critical' =>
        alert.severity == AlertSeverity.critical ||
            alert.isContinuousOverspeed ||
            type == 'main_battery_disconnected' ||
            type == 'power_cut' ||
            type == 'sos',
      'geofence' || 'geofence_enter' || 'geofence_exit' || 'geofenceenter' || 'geofenceexit' =>
        type.contains('geofence') ||
            title.contains('geofence') ||
            message.contains('geofence') ||
            message.contains('fence'),
      'overspeed' || 'overspeeding' =>
        alert.isOverspeed,
      'idle' || 'excessive_idle' || 'parking' || 'stoppage' =>
        alert.isExcessiveIdle ||
            type == 'stoppage' ||
            type == 'parking' ||
            type == 'idle' ||
            title.contains('idling') ||
            title.contains('stoppage') ||
            title.contains('parking') ||
            message.contains('idling') ||
            message.contains('parked') ||
            message.contains('stopped'),
      'sos' || 'safety' =>
        type == 'sos' ||
            type == 'panic' ||
            type == 'theft' ||
            type == 'theft_alarm' ||
            type == 'safety_park' ||
            type == 'tamper' ||
            type == 'tow' ||
            type == 'crash' ||
            type == 'accident' ||
            title.contains('safety') ||
            message.contains('safety park') ||
            message.contains('safety parking') ||
            title.contains('sos') ||
            title.contains('panic') ||
            title.contains('theft') ||
            title.contains('tamper') ||
            title.contains('crash') ||
            title.contains('tow') ||
            message.contains('sos') ||
            message.contains('theft'),
      'ignition' || 'ignition_on' || 'movement' =>
        type.contains('ignition') ||
            type.contains('trip') ||
            type == 'moving' ||
            type == 'start_moving' ||
            type == 'trip_started' ||
            type == 'trip_start' ||
            type == 'stopped' ||
            title.contains('ignition') ||
            title.contains('engine') ||
            title.contains('trip') ||
            title.contains('moving') ||
            message.contains('trip') ||
            message.contains('engine'),
      'power' || 'power_cut' || 'battery' =>
        alert.isMainBatteryAlert ||
            type == 'main_battery_disconnected' ||
            type == 'main_battery_connected' ||
            type == 'power_cut' ||
            type == 'power_disconnected' ||
            type == 'low_battery' ||
            type.contains('power') ||
            type.contains('battery') ||
            title.contains('power') ||
            title.contains('battery') ||
            message.contains('battery') ||
            message.contains('power'),
      'harsh' || 'harsh_braking' =>
        type.contains('harsh') ||
            type == 'harsh_braking' ||
            type == 'harsh_acceleration' ||
            title.contains('harsh') ||
            title.contains('braking') ||
            title.contains('acceleration'),
      _ =>
        type == filter.toLowerCase() ||
            type.contains(filter.toLowerCase()) ||
            title.contains(filter.toLowerCase()) ||
            message.contains(filter.toLowerCase()),
    };
  }

  void _listenToSocket() {
    _socketSub = ref.read(socketServiceProvider).events$.listen((event) {
      if (event.name == 'alert:new' || event.name == 'geofence:event') {
        try {
          FleetAlert newAlert = FleetAlert.fromJson(event.payload);
          if (newAlert.vehicleName == null || newAlert.vehicleName!.isEmpty) {
            final String? vId = newAlert.vehicleId;
            if (vId != null) {
              final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
              final Vehicle? matched = vehicles.where((Vehicle v) => v.id == vId).firstOrNull;
              if (matched != null) {
                newAlert = newAlert.copyWith(vehicleName: matched.displayName);
              }
            }
          }
          final bool matchesVehicle = _selectedVehicleId == null ||
              _selectedVehicleId!.isEmpty ||
              newAlert.vehicleId == _selectedVehicleId;
          if (matchesVehicle && _matchesFilter(newAlert, _typeFilter)) {
            if (!mounted) return;
            setState(() {
              _alerts.insert(0, newAlert);
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _socketSub?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }

    try {
      final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
      final List<String> vIds = vehicles.map((Vehicle v) => v.id).toList();

      final List<FleetAlert> data =
          await ref.read(alertRepositoryProvider).getAlerts(
                page: _page,
                type: _typeFilter,
                vehicleId: _selectedVehicleId,
                vehicleIds: vIds,
              );

      if (!mounted) return;
      if (reset && widget.alertId != null && widget.alertId!.isNotEmpty) {
        final bool exists = data.any((FleetAlert a) => a.id == widget.alertId);
        if (!exists) {
          final List<Map<String, dynamic>> local = await PushService.getLocalAlerts();
          final Map<String, dynamic>? match = local.where((Map<String, dynamic> m) => m['id']?.toString() == widget.alertId).firstOrNull;
          if (match != null) {
            try {
              data.insert(0, FleetAlert.fromJson(match));
            } catch (_) {}
          }
        }
        unawaited(ref.read(alertRepositoryProvider).markAsRead(widget.alertId!));
      }

      setState(() {
        if (reset) _alerts.clear();
        _alerts.addAll(data);
        _hasMore = data.length >= 30;
        _loading = false;
        _loadingMore = false;
      });
      final int unreadCount = _alerts.where((FleetAlert a) => !a.isRead).length;
      ref.read(unreadAlertsCountProvider.notifier).setCount(unreadCount);
      final int unreadOverspeed = _alerts.where((FleetAlert a) => !a.isRead && a.isOverspeed).length;
      ref.read(unreadOverspeedCountProvider.notifier).setCount(unreadOverspeed);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _load();
  }

  bool _markingRead = false;

  Future<void> _markAllAsRead() async {
    final List<FleetAlert> visibleAlerts = _typeFilter == null
        ? _alerts
        : _alerts.where((FleetAlert a) => _matchesFilter(a, _typeFilter)).toList();
    final int countToMark = visibleAlerts.where((FleetAlert a) => !a.isRead).length;
    if (countToMark == 0) return;

    unawaited(HapticFeedback.mediumImpact());
    setState(() => _markingRead = true);

    try {
      await ref.read(alertRepositoryProvider).markAllAsRead();
      if (!mounted) return;

      setState(() {
        for (int i = 0; i < _alerts.length; i++) {
          if (_matchesFilter(_alerts[i], _typeFilter)) {
            _alerts[i] = _alerts[i].copyWith(isRead: true);
          }
        }
        _markingRead = false;
      });
      final int unreadCount = _alerts.where((FleetAlert a) => !a.isRead).length;
      ref.read(unreadAlertsCountProvider.notifier).setCount(unreadCount);
      final int unreadOverspeed = _alerts.where((FleetAlert a) => !a.isRead && a.isOverspeed).length;
      ref.read(unreadOverspeedCountProvider.notifier).setCount(unreadOverspeed);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: Gap.sm),
              Text('$countToMark alert${countToMark > 1 ? 's' : ''} marked as read'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _markingRead = false);
    }
  }

  void _markSingleAsRead(FleetAlert alert) {
    if (alert.isRead) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(ref.read(alertRepositoryProvider).markAsRead(alert.id));
    setState(() {
      final int i = _alerts.indexWhere((FleetAlert a) => a.id == alert.id);
      if (i != -1) _alerts[i] = alert.copyWith(isRead: true);
    });
    final int unreadCount = _alerts.where((FleetAlert a) => !a.isRead).length;
    ref.read(unreadAlertsCountProvider.notifier).setCount(unreadCount);
    final int unreadOverspeed = _alerts.where((FleetAlert a) => !a.isRead && a.isOverspeed).length;
    ref.read(unreadOverspeedCountProvider.notifier).setCount(unreadOverspeed);
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear all alerts?'),
        content: const Text(
          'This will permanently delete all alerts history for this vehicle. This action cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Clear'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (proceed == true) {
      unawaited(HapticFeedback.heavyImpact());
      try {
        final List<String> currentIds = _alerts.map((a) => a.id).where((id) => id.isNotEmpty).toList();
        await ref.read(alertRepositoryProvider).deleteAlerts(currentIds);
        final String? vId = widget.vehicleId ?? _selectedVehicleId;
        if (vId != null && vId.isNotEmpty) {
          await ref.read(alertRepositoryProvider).clearVehicleAlerts(vId);
        } else {
          await ref.read(alertRepositoryProvider).clearAllAlerts();
        }
        if (!mounted) return;
        setState(() {
          _alerts.clear();
        });
        ref.read(unreadAlertsCountProvider.notifier).reset();
        ref.read(unreadOverspeedCountProvider.notifier).reset();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alerts cleared successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear alerts'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Vehicle> allVehicles = ref.watch(fleetProvider).vehicles;

    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final DateTime weekStart = todayStart.subtract(const Duration(days: 7));

    List<FleetAlert> visibleAlerts = _alerts.where((FleetAlert a) {
      if (!_matchesFilter(a, _typeFilter)) return false;
      if (_selectedVehicleId != null && _selectedVehicleId!.isNotEmpty) {
        if (a.vehicleId != _selectedVehicleId) return false;
      }
      final DateTime? alertTime = a.createdAt;
      if (alertTime != null) {
        if (_timeFilter == 'today') {
          if (alertTime.isBefore(todayStart)) return false;
        } else if (_timeFilter == 'yesterday') {
          if (alertTime.isBefore(yesterdayStart) || alertTime.isAfter(todayStart)) return false;
        } else if (_timeFilter == 'week') {
          if (alertTime.isBefore(weekStart)) return false;
        }
      }
      return true;
    }).toList();

    // Sort order: Unseen alerts first, then sorted by timestamp
    visibleAlerts.sort((a, b) {
      if (!a.isRead && b.isRead) return -1;
      if (a.isRead && !b.isRead) return 1;

      final DateTime timeA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime timeB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _sortNewestFirst
          ? timeB.compareTo(timeA)
          : timeA.compareTo(timeB);
    });

    final Map<String, List<FleetAlert>> grouped = _groupByDay(visibleAlerts);
    final int unreadCount = visibleAlerts.where((FleetAlert a) => !a.isRead).length;

    final String currentFilterLabel = _filters.firstWhere(
      ((String?, String) f) => f.$1 == _typeFilter,
      orElse: () => (null, 'All'),
    ).$2;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // ── Header ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
              child: Row(
                children: <Widget>[
                  if (widget.vehicleId == null && Navigator.of(context).canPop()) ...<Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: Gap.md),
                  ],
                  Text('Alerts', style: theme.textTheme.headlineMedium),
                  const Spacer(),
                  // Sort button
                  IconButton(
                    tooltip: _sortNewestFirst ? 'Sort: Newest first' : 'Sort: Oldest first',
                    icon: Icon(_sortNewestFirst ? Icons.south_rounded : Icons.north_rounded, size: 20),
                    onPressed: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
                  ),
                  if (visibleAlerts.isNotEmpty) ...<Widget>[
                    IconButton(
                      tooltip: 'Clear all alerts',
                      icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.danger),
                      onPressed: () => _confirmClearAll(context),
                    ),
                    const SizedBox(width: Gap.xs),
                    if (unreadCount > 0)
                      FilledButton.tonalIcon(
                        onPressed: _markingRead ? null : _markAllAsRead,
                        icon: _markingRead
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.done_all_rounded, size: 16),
                        label: Text('Mark all ($unreadCount)'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.check_circle_outline_rounded,
                                size: 15,
                                color: theme.colorScheme.outline
                                    .withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text(
                              'All read',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.outline
                                    .withOpacity(0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // ── Vehicle & Time Filter Bar (Fleet alerts only) ───
            if (widget.vehicleId == null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
                child: Row(
                  children: [
                    // Vehicle Selector Dropdown
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _selectedVehicleId != null
                                ? theme.colorScheme.primary.withOpacity(0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedVehicleId,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                            hint: Row(
                              children: const [
                                Icon(Icons.directions_car_outlined, size: 16),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text('All Vehicles',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Row(
                                  children: [
                                    Icon(Icons.grid_view_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text('All Vehicles', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              ...allVehicles.map((v) => DropdownMenuItem<String?>(
                                    value: v.id,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.directions_car_rounded, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(v.displayName,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedVehicleId = val);
                              _load(reset: true);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    // Time Filter Dropdown
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _timeFilter != 'all'
                                ? theme.colorScheme.primary.withOpacity(0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _timeFilter,
                            isExpanded: true,
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Time', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              DropdownMenuItem(value: 'today', child: Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              DropdownMenuItem(value: 'yesterday', child: Text('Yesterday', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              DropdownMenuItem(value: 'week', child: Text('Last 7 Days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _timeFilter = val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xs),
            ],

            // ── Alert Type Filter Chips ──────────────────────────
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: Gap.sm),
                itemBuilder: (BuildContext context, int i) {
                  final (String?, String) f = _filters[i];
                  final bool selected = _typeFilter == f.$1;

                  return FilterChip(
                    label: Text(f.$2),
                    selected: selected,
                    showCheckmark: false,
                    avatar: f.$1 == null
                        ? null
                        : Icon(
                            switch (f.$1) {
                              'geofence' => Icons.fence_rounded,
                              'overspeed' => Icons.speed_rounded,
                              'ignition' => Icons.power_settings_new_rounded,
                              'sos' => Icons.warning_amber_rounded,
                              'power' => Icons.battery_alert_rounded,
                              'harsh' => Icons.emergency_rounded,
                              _ => Icons.notifications_active_rounded,
                            },
                            size: 15,
                            color: selected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                    labelStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    selectedColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant.withOpacity(0.5),
                        width: 1.0,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    onSelected: (_) {
                      if (_typeFilter == f.$1) return;
                      setState(() => _typeFilter = f.$1);
                      _load(reset: true);
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: Gap.sm),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.lg),
              child: OfflineNotice(),
            ),

            // ── List ─────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const ListSkeleton(count: 5)
                  : _error != null && visibleAlerts.isEmpty
                      ? ErrorState(
                          message: _error!,
                          onRetry: () => _load(reset: true),
                        )
                      : visibleAlerts.isEmpty
                          ? EmptyState(
                              icon: _typeFilter != null
                                  ? Icons.filter_alt_off_outlined
                                  : (BackendCapabilities.alertsHistory
                                      ? Icons.notifications_off_outlined
                                      : Icons.cloud_sync_outlined),
                              title: _typeFilter != null
                                  ? 'No $currentFilterLabel alerts'
                                  : (BackendCapabilities.alertsHistory
                                      ? 'No alerts'
                                      : 'Alert history coming soon'),
                              message: _typeFilter != null
                                  ? 'No $currentFilterLabel alerts have been recorded.'
                                  : (BackendCapabilities.alertsHistory
                                      ? 'When your vehicles trigger an event — '
                                          'overspeeding, a geofence breach or an '
                                          'SOS — it will appear here.'
                                      : 'Your account is not yet enabled for stored '
                                          'alert history. Live alerts still arrive as '
                                          'push notifications and appear here while '
                                          'the app is open.'),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _load(reset: true),
                              child: ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.fromLTRB(
                                    Gap.lg, Gap.sm, Gap.lg, Gap.navClearance),
                                itemCount: _flatCount(grouped, visibleAlerts.length) +
                                    (_hasMore ? 1 : 0),
                                itemBuilder: (BuildContext context, int index) =>
                                    _buildItem(grouped, index),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  int _flatCount(Map<String, List<FleetAlert>> grouped, int visibleCount) =>
      grouped.length + visibleCount;

  Widget _buildItem(Map<String, List<FleetAlert>> grouped, int index) {
    int cursor = 0;

    for (final MapEntry<String, List<FleetAlert>> entry in grouped.entries) {
      if (index == cursor) return _DayHeader(label: entry.key);
      cursor++;

      if (index < cursor + entry.value.length) {
        final FleetAlert alert = entry.value[index - cursor];
        return Dismissible(
          key: Key(alert.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: AppColors.danger,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Gap.lg),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          onDismissed: (direction) {
            final String alertId = alert.id;
            setState(() {
              _alerts.removeWhere((a) => a.id == alertId);
            });
            ref.read(alertRepositoryProvider).deleteAlert(alertId);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Alert deleted'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: AlertTile(
            alert: alert,
            isHighlighted: alert.id == widget.alertId,
            onTap: () => _openAlert(alert),
            onMarkRead: alert.isRead ? null : () => _markSingleAsRead(alert),
          ),
        );
      }
      cursor += entry.value.length;
    }

    return const Padding(
      padding: EdgeInsets.all(Gap.xl),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  void _openAlert(FleetAlert alert) {
    if (!alert.isRead) {
      ref.read(alertRepositoryProvider).markAsRead(alert.id);
      final int index = _alerts.indexWhere((a) => a.id == alert.id);
      if (index != -1) {
        final FleetAlert updated = alert.copyWith(isRead: true);
        setState(() {
          _alerts[index] = updated;
        });
      }
    }

    // We are already on the Vehicle Detail Screen, no need to push a new route.
  }

  Map<String, List<FleetAlert>> _groupByDay(List<FleetAlert> alerts) {
    final Map<String, List<FleetAlert>> out = <String, List<FleetAlert>>{};
    final DateTime now = DateTime.now();

    for (final FleetAlert a in alerts) {
      final DateTime? t = a.createdAt;
      String key;

      if (t == null) {
        key = 'Earlier';
      } else {
        final int diff = DateTime(now.year, now.month, now.day)
            .difference(DateTime(t.year, t.month, t.day))
            .inDays;
        key = switch (diff) {
          0 => 'Today',
          1 => 'Yesterday',
          < 7 => '$diff days ago',
          _ => Fmt.date(t),
        };
      }

      out.putIfAbsent(key, () => <FleetAlert>[]).add(a);
    }

    // Ensure unseen alerts appear first within each day group
    for (final List<FleetAlert> list in out.values) {
      list.sort((a, b) {
        if (!a.isRead && b.isRead) return -1;
        if (a.isRead && !b.isRead) return 1;
        final DateTime timeA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime timeB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return _sortNewestFirst ? timeB.compareTo(timeA) : timeA.compareTo(timeB);
      });
    }
    return out;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, Gap.lg, 0, Gap.sm),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _AddressText extends StatefulWidget {
  const _AddressText(this.alert);
  final FleetAlert alert;
  @override
  State<_AddressText> createState() => _AddressTextState();
}

class _AddressTextState extends State<_AddressText> {
  String? _address;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void didUpdateWidget(_AddressText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alert.id != widget.alert.id ||
        oldWidget.alert.address != widget.alert.address ||
        oldWidget.alert.latitude != widget.alert.latitude ||
        oldWidget.alert.longitude != widget.alert.longitude) {
      _resolveAddress();
    }
  }

  void _resolveAddress() {
    final String? direct = widget.alert.address;
    if (direct != null &&
        direct.trim().isNotEmpty &&
        direct.toLowerCase() != 'location pending' &&
        direct.toLowerCase() != 'unknown location') {
      _address = direct;
      return;
    }

    if (widget.alert.hasLocation) {
      // 1. Try instantaneous synchronous cache first
      final String? cached = Geocoder.getCachedAddress(
        widget.alert.latitude!,
        widget.alert.longitude!,
      );
      if (cached != null &&
          cached.isNotEmpty &&
          cached != 'Location unavailable') {
        _address = cached;
        return;
      }

      // 2. Fetch reverse geocode asynchronously
      Geocoder.getAddress(widget.alert.latitude!, widget.alert.longitude!)
          .then((String addr) {
        if (mounted && addr.isNotEmpty && addr != 'Location unavailable') {
          setState(() => _address = addr);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayText = _address ??
        (widget.alert.hasLocation ? 'Resolving address' : 'Location unavailable');
    final ThemeData theme = Theme.of(context);
    final bool isResolving = _address == null && widget.alert.hasLocation;

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(
              Icons.location_on_rounded,
              size: 12,
              color: isResolving
                  ? theme.colorScheme.primary.withOpacity(0.6)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              displayText,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0,
                color: isResolving
                    ? theme.colorScheme.primary.withOpacity(0.7)
                    : theme.colorScheme.onSurfaceVariant,
                fontStyle: isResolving ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Returns true for alert types that represent a stoppage / parking / idle
/// event — these cards should display Start, End, and Duration rows.
bool _isStoppageType(String type) {
  const Set<String> stoppageTypes = <String>{
    'stoppage', 'idle', 'excessive_idle', 'excessive_idling', 'parking',
  };
  return stoppageTypes.contains(type.toLowerCase());
}

class AlertTile extends StatelessWidget {
  const AlertTile({
    required this.alert,
    required this.onTap,
    this.onMarkRead,
    this.isHighlighted = false,
    super.key,
  });

  final FleetAlert alert;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;
  final bool isHighlighted;

  Color _getAlertColor(FleetAlert alert) {
    if (alert.isContinuousOverspeed) {
      return const Color(0xFFDC2626); // Deep Critical Red for Continuous Overspeed
    }
    final String type = alert.type.toLowerCase().trim();
    return switch (type) {
      'parking' => const Color(0xFF7C3AED), // Vibrant Indigo / Purple for Parking Alert
      'stoppage' => const Color(0xFFD97706), // Warm Amber / Orange for Long Stoppage
      'idle' || 'excessive_idle' || 'excessive_idling' => const Color(0xFF0284C7), // Electric Cyan / Blue for Excessive Idling
      'overspeed' || 'overspeeding' => const Color(0xFFEF4444), // Vibrant Red
      'main_battery_disconnected' || 'power_cut' || 'power_disconnected' => const Color(0xFFDC2626), // Critical Red
      'main_battery_connected' => const Color(0xFF10B981), // Emerald Green
      'geofence' || 'geofence_enter' || 'geofence_exit' => const Color(0xFF10B981), // Emerald Green
      'ignition_on' => const Color(0xFF10B981), // Green
      'ignition_off' => const Color(0xFF64748B), // Slate Grey
      'sos' || 'panic' || 'theft' || 'tow' => const Color(0xFFDC2626), // Deep Red
      _ => switch (alert.severity) {
          AlertSeverity.critical => AppColors.danger,
          AlertSeverity.warning => AppColors.idle,
          AlertSeverity.info => AppColors.signal,
        },
    };
  }

  String? _getPurposeLabel(FleetAlert alert) {
    if (alert.isContinuousOverspeed) {
      return 'SUSTAINED OVERSPEED';
    }
    final String type = alert.type.toLowerCase().trim();
    return switch (type) {
      'parking' => 'PARKED',
      'stoppage' => 'STOPPAGE',
      'idle' || 'excessive_idle' || 'excessive_idling' => 'ENGINE IDLE',
      'overspeed' || 'overspeeding' => 'OVERSPEED',
      'main_battery_disconnected' => 'BATTERY CUT',
      'main_battery_connected' => 'BATTERY RESTORED',
      'geofence' || 'geofence_enter' || 'geofence_exit' => 'GEOFENCE',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Color color = _getAlertColor(alert);
    final String? purposeLabel = _getPurposeLabel(alert);
    final String? stoppageDuration = alert.formattedStoppageDuration;

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: isHighlighted
            ? theme.colorScheme.primary.withOpacity(0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isHighlighted
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? theme.colorScheme.primary.withOpacity(0.2)
                : const Color(0xFFC7D7EC).withOpacity(0.55),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: Corners.rMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: Corners.rMd,
          child: Padding(
            padding: Gap.cardTight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: color.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    VehicleIcons.forAlert(alert.type),
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (isHighlighted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OPENED FROM NOTIFICATION',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              alert.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: alert.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (purposeLabel != null) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: color.withOpacity(0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                purposeLabel,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        alert.message,
                        softWrap: true,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: alert.isRead
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      // ── Timestamp row(s) ──────────────────────
                      Wrap(
                        spacing: Gap.md,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          if (alert.vehicleName != null) 
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.directions_car_rounded,
                                    size: 12,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  alert.vehicleName!,
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(letterSpacing: 0),
                                ),
                              ],
                            ),
                          if (!_isStoppageType(alert.type))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.schedule_rounded,
                                    size: 12,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  Fmt.full(alert.createdAt),
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(letterSpacing: 0),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // Time range & Duration box — stoppage / parking / idle alerts
                      if (_isStoppageType(alert.type) && alert.createdAt != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: color.withOpacity(0.2),
                              width: 0.8,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(Icons.schedule_rounded, size: 12, color: color),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: <InlineSpan>[
                                          TextSpan(
                                            text: 'From: ',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          TextSpan(
                                            text: alert.calculatedStartTime != null 
                                                ? Fmt.full(alert.calculatedStartTime) 
                                                : 'Unknown',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '   To: ',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          TextSpan(
                                            text: (alert.calculatedEndTime != null &&
                                                    alert.calculatedStartTime != null &&
                                                    alert.calculatedEndTime!.difference(alert.calculatedStartTime!).inSeconds.abs() >= 60)
                                                ? Fmt.full(alert.calculatedEndTime)
                                                : 'Ongoing',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: (alert.calculatedEndTime != null &&
                                                      alert.calculatedStartTime != null &&
                                                      alert.calculatedEndTime!.difference(alert.calculatedStartTime!).inSeconds.abs() >= 60)
                                                  ? theme.colorScheme.onSurface
                                                  : color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (stoppageDuration != null &&
                                  stoppageDuration != '0m' &&
                                  stoppageDuration != '0 min' &&
                                  stoppageDuration != '0s') ...<Widget>[
                                const SizedBox(height: 3),
                                Row(
                                  children: <Widget>[
                                    Icon(Icons.timelapse_rounded, size: 12, color: color),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Duration: $stoppageDuration',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        letterSpacing: 0,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (alert.isContinuousOverspeed) ...<Widget>[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color.withOpacity(0.25), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.speed_rounded, size: 13, color: color),
                              const SizedBox(width: 5),
                              Text(
                                alert.effectiveDurationMinutes != null
                                    ? 'Sustained for ${alert.effectiveDurationMinutes} mins above speed limit'
                                    : 'Sustained overspeeding observed',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _AddressText(alert),
                      if (alert.hasLocation) ...<Widget>[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (alert.latitude != null && alert.longitude != null) {
                              final Uri url = Uri.parse('https://maps.google.com/?q=${alert.latitude},${alert.longitude}');
                              launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.map_rounded, size: 14),
                          label: const Text('View in Google Maps'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            foregroundColor: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!alert.isRead && onMarkRead != null) ...<Widget>[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Mark as read',
                    icon: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: onMarkRead,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
