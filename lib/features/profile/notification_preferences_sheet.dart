import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/json_utils.dart';
import '../../providers/core_providers.dart';
import '../../shared/widgets/duration_alert_card.dart';

class NotificationPreferencesSheet extends ConsumerWidget {
  const NotificationPreferencesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NotificationPreferences prefs = ref.watch(notificationPreferencesProvider);
    final NotificationPreferencesNotifier notifier =
        ref.read(notificationPreferencesProvider.notifier);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Alert & Notification Configuration',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(
              'Customize which notifications you want to receive on this device.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Gap.lg),
            const Divider(),
            const SizedBox(height: Gap.sm),

            _buildPreferenceTile(
              context: context,
              icon: Icons.sos_rounded,
              title: 'SOS & Safety Alerts',
              subtitle: 'Emergency button triggers, crash events, towing, power cut',
              value: prefs.sos,
              onChanged: (_) => notifier.toggleSos(),
            ),
            _buildPreferenceTile(
              context: context,
              icon: Icons.alarm_rounded,
              title: 'Theft Alarms',
              subtitle: 'Unauthorized vehicle movement, vibration or tampering',
              value: prefs.theft,
              onChanged: (_) => notifier.toggleTheft(),
            ),
            _buildPreferenceTile(
              context: context,
              icon: Icons.speed_rounded,
              title: 'Overspeed Alerts',
              subtitle: 'Exceeding designated speed limits',
              value: prefs.overspeed,
              onChanged: (_) => notifier.toggleOverspeed(),
            ),
            _buildPreferenceTile(
              context: context,
              icon: Icons.login_rounded,
              title: 'Geofence Entry/Exit',
              subtitle: 'Vehicles entering or leaving defined zones',
              value: prefs.geofence,
              onChanged: (_) => notifier.toggleGeofence(),
            ),
            _buildPreferenceTile(
              context: context,
              icon: Icons.power_settings_new_rounded,
              title: 'Ignition & Movement',
              subtitle: 'Engine start, stop, idle, moving, stopped',
              value: prefs.ignition,
              onChanged: (_) => notifier.toggleIgnition(),
            ),

            const SizedBox(height: Gap.lg),
            const Divider(),
            const SizedBox(height: Gap.md),

            // ── Vehicle Thresholds ──
            const _ThresholdsSection(),

            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Preferences saved successfully!'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Save Preferences'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.sm,
        vertical: Gap.xs,
      ),
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: value ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ThresholdsSection extends ConsumerStatefulWidget {
  const _ThresholdsSection();

  @override
  ConsumerState<_ThresholdsSection> createState() => _ThresholdsSectionState();
}

class _ThresholdsSectionState extends ConsumerState<_ThresholdsSection> {
  double _speedLimit = 80.0;
  double _idleDuration = 60.0;
  double _parkingDuration = 60.0;
  double _movingDuration = 60.0;
  double _noDataThreshold = 1.0;
  late TextEditingController _idleController;
  late TextEditingController _parkingController;
  late TextEditingController _movingController;
  bool _isSavingThresholds = false;

  @override
  void initState() {
    super.initState();
    _noDataThreshold = AppConfig.noDataThresholdHours;
    _idleController = TextEditingController(text: '${_idleDuration.round()}');
    _parkingController = TextEditingController(text: '${_parkingDuration.round()}');
    _movingController = TextEditingController(text: '${_movingDuration.round()}');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccountThresholds());
  }

  @override
  void dispose() {
    _idleController.dispose();
    _parkingController.dispose();
    _movingController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountThresholds() async {
    try {
      final double localThresh = ref.read(noDataThresholdProvider);
      if (mounted) setState(() => _noDataThreshold = localThresh);

      final Map<String, dynamic>? remote =
          await ref.read(alertRepositoryProvider).getPreferences();
      if (remote != null && mounted) {
        setState(() {
          if (remote['speed_limit'] != null) {
            _speedLimit = toDouble(remote['speed_limit']) ?? _speedLimit;
          }
          if (remote['idle_duration_mins'] != null) {
            _idleDuration = toDouble(remote['idle_duration_mins']) ?? _idleDuration;
            _idleController.text = '${_idleDuration.round()}';
          }
          if (remote['parking_duration_mins'] != null) {
            _parkingDuration = toDouble(remote['parking_duration_mins']) ?? _parkingDuration;
            _parkingController.text = '${_parkingDuration.round()}';
          }
          if (remote['moving_duration_mins'] != null) {
            _movingDuration = toDouble(remote['moving_duration_mins']) ?? _movingDuration;
            _movingController.text = '${_movingDuration.round()}';
          }
          if (remote['nodata_threshold_hours'] != null) {
            _noDataThreshold = toDouble(remote['nodata_threshold_hours']) ?? _noDataThreshold;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveAccountThresholds() async {
    setState(() => _isSavingThresholds = true);
    try {
      final Map<String, dynamic> userPrefs = <String, dynamic>{
        'speed_limit': _speedLimit,
        'idle_duration_mins': _idleDuration,
        'parking_duration_mins': _parkingDuration,
        'moving_duration_mins': _movingDuration,
        'nodata_threshold_hours': _noDataThreshold,
      };
      await ref.read(alertRepositoryProvider).updatePreferences(userPrefs);
      await ref.read(noDataThresholdProvider.notifier).setThreshold(_noDataThreshold);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account alert thresholds saved & applied to all vehicles!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update thresholds: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingThresholds = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: Gap.xs),
            Text(
              'Alert Thresholds Configuration',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Account-wide thresholds governing overspeed limit, idle duration, parking, and moving alerts across all your vehicles.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Gap.md),

        // Account-wide Badge Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF2563EB), size: 18),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'User-Wise (Configures All Vehicles)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF2563EB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),

        // Overspeed threshold slider
        _buildSliderTile(
          title: 'Overspeed Threshold',
          valueText: '${_speedLimit.round()} km/h',
          icon: Icons.speed_rounded,
          color: const Color(0xFFFF9800),
          slider: Slider(
            value: _speedLimit,
            min: 30,
            max: 140,
            divisions: 110,
            activeColor: const Color(0xFFFF9800),
            onChanged: (v) => setState(() => _speedLimit = v),
          ),
        ),

        const SizedBox(height: Gap.md),

        // ── Parking Alert Duration Card ──
        DurationAlertCard(
          title: 'Parking',
          subtitle: 'Alert triggers when vehicle is parked beyond duration',
          icon: Icons.local_parking_rounded,
          iconColor: const Color(0xFF2563EB),
          badgeColor: const Color(0xFF2563EB),
          controller: _parkingController,
          duration: _parkingDuration,
          onDurationChanged: (double v) => setState(() => _parkingDuration = v),
        ),

        const SizedBox(height: Gap.md),

        // ── Moving (After Stoppage) Alert Duration Card ──
        DurationAlertCard(
          title: 'Moving (After Stoppage)',
          subtitle: 'Alert triggers when vehicle starts moving after stoppage',
          icon: Icons.directions_car_rounded,
          iconColor: const Color(0xFF0D9488),
          badgeColor: const Color(0xFF0D9488),
          controller: _movingController,
          duration: _movingDuration,
          onDurationChanged: (double v) => setState(() => _movingDuration = v),
        ),

        const SizedBox(height: Gap.md),

        // ── Idle Duration Card ──
        DurationAlertCard(
          title: 'Idle Duration',
          subtitle: 'Alert triggers when vehicle engine is ON but stationary',
          icon: Icons.hourglass_empty_rounded,
          iconColor: const Color(0xFF9C27B0),
          badgeColor: const Color(0xFF9C27B0),
          controller: _idleController,
          duration: _idleDuration,
          onDurationChanged: (double v) => setState(() => _idleDuration = v),
        ),

        const SizedBox(height: Gap.md),

        // ── No Data Rule (Inactivity Threshold) ──
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFF0EA5E9)),
                  const SizedBox(width: Gap.xs),
                  const Text('No Data Rule (Inactivity Threshold)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_noDataThreshold.toInt()} hr${_noDataThreshold == 1.0 ? '' : 's'}',
                      style: const TextStyle(color: Color(0xFF0EA5E9), fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'Keep vehicle in same state (Running, Idle, Parked) for this duration before marking as No Data.',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: AppConfig.noDataThresholdOptions.map((double h) {
                  final bool isSelected = _noDataThreshold == h;
                  final String label = h == 1.0 ? '1 hr (Default)' : '${h.toInt()} hrs';
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF0EA5E9) : null,
                      fontSize: 12,
                    ),
                    onSelected: (bool selected) {
                      if (selected) setState(() => _noDataThreshold = h);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.md),

        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _isSavingThresholds ? null : _saveAccountThresholds,
            icon: _isSavingThresholds
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(_isSavingThresholds ? 'Saving...' : 'Apply Thresholds to All Vehicles'),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String valueText,
    required IconData icon,
    required Color color,
    required Widget slider,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Gap.xs),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueText,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          slider,
        ],
      ),
    );
  }
}
