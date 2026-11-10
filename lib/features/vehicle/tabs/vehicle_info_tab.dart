import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/geocoder.dart';
import '../../../data/models/route.dart';
import '../../../data/models/user_trip.dart';
import '../../../data/models/vehicle.dart';

import '../../../providers/core_providers.dart';
import '../../../providers/fleet_provider.dart';
import '../../../providers/route_provider.dart';
import '../../../providers/trip_provider.dart';
import '../../../shared/widgets/live_address.dart';

import 'package:local_auth/local_auth.dart';

class VehicleInfoTab extends ConsumerWidget {
  const VehicleInfoTab({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vehicle? v = ref.watch(vehicleByIdProvider(vehicleId));
    final ThemeData theme = Theme.of(context);

    if (v == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.x4l),
      children: <Widget>[
        if (v.isExpiringSoon || v.isExpired) ...<Widget>[
          _RenewalBanner(vehicle: v),
          const SizedBox(height: Gap.lg),
        ],

        _ImmobilizerCard(vehicle: v),
        const SizedBox(height: Gap.lg),

        _Section(
          title: 'VEHICLE',
          rows: <(String, String)>[
            ('Registration', v.registrationNumber.isEmpty ? '—' : v.registrationNumber),
            ('Name', v.name.isEmpty ? '—' : v.name),
            ('Type', v.type.toUpperCase()),
            if (v.speedLimit != null)
              ('Speed limit', '${v.speedLimit!.round()} km/h'),
            ('Status', v.isActive ? 'Active' : 'Inactive'),
          ],
        ),

        const SizedBox(height: Gap.lg),

        _AssignedRoutesCard(vehicle: v),

        const SizedBox(height: Gap.lg),

        _Section(
          title: 'DEVICE',
          vehicle: v,
          rows: <(String, String)>[
            ('IMEI', v.imei.isEmpty ? '—' : v.imei),
            if (v.deviceId.isNotEmpty) ('Device ID', v.deviceId),
            ('Last packet', Fmt.full(v.lastPacketAt)),
            ('Address', v.address ?? 'Location unavailable'),
            if (v.satellites != null) ('Satellites', '${v.satellites}'),
            if (v.gsmSignal != null) ('GSM signal', '${v.gsmSignal}${v.gsmSignal! > 5 ? '%' : '/5'}'),
          ],
          customWidgets: <String, Widget>{
            'Address': LiveAddress(
              vehicle: v,
              
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          },
          copyable: const <String>{'IMEI', 'Address', 'Device ID'},
        ),

        if (v.driverName != null || v.driverPhone != null) ...<Widget>[
          const SizedBox(height: Gap.lg),
          _Section(
            title: 'DRIVER',
            rows: <(String, String)>[
              if (v.driverName != null) ('Name', v.driverName!),
              if (v.driverPhone != null) ('Phone', v.driverPhone!),
            ],
            copyable: const <String>{'Phone'},
          ),
        ],

        const SizedBox(height: Gap.lg),

        _Section(
          title: 'SUBSCRIPTION',
          rows: <(String, String)>[
            ('Expiry date', Fmt.date(v.expiryDate)),
            ('Status', Fmt.expiry(v.daysToExpiry)),
          ],
        ),

        const SizedBox(height: Gap.lg),

        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10B981).withOpacity(0.12),
            foregroundColor: const Color(0xFF059669),
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.3)),
          ),
          onPressed: () =>
              context.push('/vehicle/${v.id}/fitment-certificate'),
          icon: const Icon(Icons.verified_user_rounded, size: 18),
          label: const Text(
            'View & Download Fitment Certificate',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: Gap.xxl),

        OutlinedButton.icon(
          onPressed: () => context.go('/reports?vehicle=${v.id}'),
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Run a report for this vehicle'),
        ),

        const SizedBox(height: Gap.lg),

        Center(
          child: Text(
            'Vehicle data is managed by your service provider.\n'
            'Contact them to update registration or driver details.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    this.customWidgets = const <String, Widget>{},
    this.copyable = const <String>{},
    this.vehicle,
  });

  final String title;
  final List<(String, String)> rows;
  final Map<String, Widget> customWidgets;
  final Set<String> copyable;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: Gap.sm),
          child: Text(
            title,
            style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Column(
          children: <Widget>[
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              _InfoRow(
                label: rows[i].$1,
                value: rows[i].$2,
                customWidget: customWidgets[rows[i].$1],
                copyable: copyable.contains(rows[i].$1),
                vehicle: vehicle,
              ),
              if (i < rows.length - 1)
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ],
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.customWidget,
    required this.copyable,
    this.vehicle,
  });

  final String label;
  final String value;
  final Widget? customWidget;
  final bool copyable;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: copyable && value != '—'
          ? () {
              String textToCopy = value;
              final Vehicle? v = vehicle;
              if (label == 'Address' && v != null && v.hasLocation) {
                textToCopy = Geocoder.getCachedAddress(v.latitude!, v.longitude!) ??
                    (v.address != null && v.address!.isNotEmpty ? v.address! : value);
              }
              Clipboard.setData(ClipboardData(text: textToCopy));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('$label copied')));
            }
          : null,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(label, style: theme.textTheme.bodySmall),
            ),
            Expanded(
              child: customWidget ??
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
            ),
            if (copyable && value != '—') ...<Widget>[
              const SizedBox(width: Gap.sm),
              Icon(
                Icons.copy_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RenewalBanner extends StatelessWidget {
  const _RenewalBanner({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool expired = vehicle.isExpired;
    final Color color = expired ? AppColors.danger : AppColors.idle;

    return Container(
      padding: Gap.card,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: Corners.rLg,
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            expired ? Icons.error_rounded : Icons.schedule_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  expired ? 'Subscription expired' : 'Renewal due soon',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.expiry(vehicle.daysToExpiry),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          FilledButton(
            onPressed: () => context.push('/renewals'),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            ),
            child: const Text('Renew'),
          ),
        ],
      ),
    );
  }
}

class _ImmobilizerCard extends ConsumerStatefulWidget {
  const _ImmobilizerCard({required this.vehicle});

  final Vehicle vehicle;

  @override
  ConsumerState<_ImmobilizerCard> createState() => _ImmobilizerCardState();
}

class _ImmobilizerCardState extends ConsumerState<_ImmobilizerCard> {
  bool _loading = false;
  final LocalAuthentication _auth = LocalAuthentication();

  Future<void> _handleToggle() async {
    final bool isImmobilized = widget.vehicle.isImmobilized;
    final bool proceed = await _showWarningDialog(isImmobilized);
    if (!proceed || !mounted) return;

    final bool authenticated = await _authenticate();
    if (!authenticated || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required to proceed.')),
        );
      }
      return;
    }

    setState(() => _loading = true);

    try {
      await ref
          .read(vehicleRepositoryProvider)
          .sendImmobilizerCommand(widget.vehicle.id, !isImmobilized);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isImmobilized
                ? 'Engine restored successfully.'
                : 'Engine cut command sent.'),
            backgroundColor: isImmobilized ? AppColors.moving : AppColors.danger,
          ),
        );
      }
      
      // Trigger a silent foreground re-sync to get the new attributes back
      unawaited(ref.read(fleetProvider.notifier).load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _authenticate() async {
    try {
      final bool canAuthenticate = await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
      if (!canAuthenticate) {
        // Fallback: if device has no security, we allow it since the dialog was accepted.
        return true;
      }
      return await _auth.authenticate(
        localizedReason: 'Confirm identity to control engine',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> _showWarningDialog(bool isImmobilized) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          icon: Icon(
            isImmobilized ? Icons.settings_backup_restore_rounded : Icons.power_settings_new_rounded,
            color: isImmobilized ? AppColors.moving : AppColors.danger,
            size: 40,
          ),
          title: Text(isImmobilized ? 'Restore Engine?' : 'Cut Engine?'),
          content: Text(
            isImmobilized
                ? 'This will restore the ignition circuit, allowing the vehicle to be started again.'
                : 'WARNING: This will disable the vehicle\'s ignition circuit. '
                  'The vehicle will not be able to start again until you restore the engine. '
                  'Ensure the vehicle is in a safe location.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: isImmobilized ? AppColors.moving : AppColors.danger,
              ),
              child: Text(isImmobilized ? 'Restore' : 'Proceed'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isImmobilized = widget.vehicle.isImmobilized;
    final Color color = isImmobilized ? AppColors.danger : AppColors.moving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: Gap.sm),
          child: Text(
            'ENGINE CONTROL',
            style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.sm),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: Corners.rSm,
                ),
                child: Icon(
                  isImmobilized ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isImmobilized ? 'Engine Immobilized' : 'Engine Normal',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isImmobilized
                          ? 'Vehicle cannot be started.'
                          : 'Ignition circuit is active.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(right: Gap.sm),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _handleToggle,
                  icon: Icon(
                    isImmobilized ? Icons.settings_backup_restore_rounded : Icons.power_settings_new_rounded,
                    size: 16,
                  ),
                  label: Text(isImmobilized ? 'Restore' : 'Cut Engine'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isImmobilized ? null : AppColors.danger,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssignedRoutesCard extends ConsumerWidget {
  const _AssignedRoutesCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<AppRoute> routes = ref.watch(routeProvider).routes;
    final List<AppRoute> assigned = routes
        .where((AppRoute r) => r.vehicleIds.contains(vehicle.id))
        .toList();
    final List<UserTrip> trips = ref.watch(tripProvider).trips;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: Gap.sm),
          child: Text(
            'ASSIGNED ROUTES & TRIPS',
            style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant),
          ),
        ),
        if (assigned.isEmpty)
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: Corners.rMd,
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.route_rounded, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'No route assigned to this vehicle.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/routes'),
                  child: const Text('Assign Route', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          )
        else
          ...assigned.map((AppRoute r) {
            final List<UserTrip> onThisRoute = trips
                .where((UserTrip t) =>
                    t.vehicleId == vehicle.id &&
                    (t.routeId == r.id ||
                        (t.routeName != null && t.routeName == r.name)))
                .toList();

            return Container(
              margin: const EdgeInsets.only(bottom: Gap.sm),
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: Corners.rMd,
                border: Border.all(color: AppColors.brand.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.alt_route_rounded,
                          size: 20, color: AppColors.brand),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          r.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '±${r.toleranceMeters.round()} m',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Length: ${r.approxLengthKm.toStringAsFixed(1)} km · '
                    '${onThisRoute.length} trip${onThisRoute.length == 1 ? '' : 's'} made through this route',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (onThisRoute.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Gap.sm),
                    const Divider(height: 1),
                    const SizedBox(height: Gap.xs),
                    for (final UserTrip t in onThisRoute.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              t.isCompleted
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.play_circle_outline_rounded,
                              size: 13,
                              color:
                                  t.isCompleted ? Colors.green : AppColors.brand,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                t.name,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              t.distanceLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }
}

