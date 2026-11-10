import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/brand_config.dart';
import '../theme/app_spacing.dart';

/// ─────────────────────────────────────────────────────────────────────
///  PERMISSIONS — STORE-COMPLIANT RATIONALES
/// ─────────────────────────────────────────────────────────────────────
///
/// Both stores reject apps that fire a system permission dialog with no
/// context. Every request here is preceded by an in-app explanation that
/// states plainly *what* is accessed and *why*, and offers a real "Not now".
///
/// Important scope note: this app shows the location of **vehicles**, which
/// comes from GPS trackers over the API — not from the phone. Device location
/// is optional and used only to centre the map on the user and compute
/// distance to a vehicle. We therefore never request "always" / background
/// location, which is the single most common cause of review rejection.
class PermissionService {
  const PermissionService();

  Future<bool> hasLocationPermission() async {
    final PermissionStatus s = await Permission.locationWhenInUse.status;
    return s.isGranted || s.isLimited;
  }

  /// Requests foreground location after showing [_LocationRationaleSheet].
  Future<bool> requestLocation(BuildContext context) async {
    PermissionStatus status = await Permission.locationWhenInUse.status;

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      return _showSettingsDialog(
        context,
        title: 'Location access is turned off',
        body: 'To centre the map on your position, enable Location for '
            '${BrandConfig.appName} in your device settings. Vehicle tracking will keep '
            'working without it.',
      );
    }

    if (!context.mounted) return false;
    final bool proceed = await _showRationale(
      context,
      icon: Icons.my_location_rounded,
      title: 'Show your position on the map',
      reasons: const <(IconData, String, String)>[
        (
          Icons.center_focus_strong_rounded,
          'Centre the map',
          'Jump straight to where you are instead of panning manually.',
        ),
        (
          Icons.route_rounded,
          'Distance to a vehicle',
          'See how far each vehicle is from your current position.',
        ),
        (
          Icons.lock_outline_rounded,
          'Only while using the app',
          'We never collect your location in the background, and it is never '
              'stored on our servers.',
        ),
      ],
      confirmLabel: 'Allow location',
    );

    if (!proceed) return false;

    status = await Permission.locationWhenInUse.request();
    return status.isGranted || status.isLimited;
  }

  Future<bool> hasNotificationPermission() async =>
      (await Permission.notification.status).isGranted;

  /// Requests notification permission with the fleet-safety rationale.
  Future<bool> requestNotifications(BuildContext context) async {
    PermissionStatus status = await Permission.notification.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      return _showSettingsDialog(
        context,
        title: 'Notifications are turned off',
        body: 'Enable notifications for ${BrandConfig.appName} in settings to receive '
            'SOS, overspeeding and geofence alerts while the app is closed.',
      );
    }

    if (!context.mounted) return false;
    final bool proceed = await _showRationale(
      context,
      icon: Icons.notifications_active_rounded,
      title: 'Never miss a critical alert',
      reasons: const <(IconData, String, String)>[
        (
          Icons.sos_rounded,
          'Emergency & tamper alerts',
          'SOS, power disconnection and tow detection reach you instantly.',
        ),
        (
          Icons.speed_rounded,
          'Safety events',
          'Overspeeding and geofence breaches as they happen.',
        ),
        (
          Icons.battery_saver_rounded,
          'Battery friendly',
          'Push is exactly why we close the live connection in the '
              'background — you stay informed without draining your battery.',
        ),
      ],
      confirmLabel: 'Enable alerts',
    );

    if (!proceed) return false;

    status = await Permission.notification.request();
    return status.isGranted;
  }

  // ── UI ───────────────────────────────────────────────────────────

  Future<bool> _showRationale(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<(IconData, String, String)> reasons,
    required String confirmLabel,
  }) async {
    final bool? result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _RationaleSheet(
        icon: icon,
        title: title,
        reasons: reasons,
        confirmLabel: confirmLabel,
      ),
    );
    return result ?? false;
  }

  Future<bool> _showSettingsDialog(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );

    if (open == true) {
      await openAppSettings();
    }
    return false;
  }
}

class _RationaleSheet extends StatelessWidget {
  const _RationaleSheet({
    required this.icon,
    required this.title,
    required this.reasons,
    required this.confirmLabel,
  });

  final IconData icon;
  final String title;
  final List<(IconData, String, String)> reasons;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xxl, Gap.sm, Gap.xxl, Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.14),
                borderRadius: Corners.rMd,
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 28),
            ),
            const SizedBox(height: Gap.lg),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Gap.xxl),
            ...reasons.map(
              ((IconData, String, String) r) => Padding(
                padding: const EdgeInsets.only(bottom: Gap.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(r.$1, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(r.$2, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(r.$3, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ),
            const SizedBox(height: Gap.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
