import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/fleet_provider.dart';
import '../../alerts/alerts_screen.dart';

class VehicleAlertsScreen extends ConsumerWidget {
  const VehicleAlertsScreen({required this.vehicleId, this.alertId, super.key});

  final String vehicleId;
  final String? alertId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(vehicleId));
    final String title = vehicle?.displayName ?? 'Alerts';

    return Scaffold(
      appBar: AppBar(
        title: Text('$title - Alerts'),
      ),
      body: AlertsScreen(
        vehicleId: vehicleId,
        alertId: alertId,
      ),
    );
  }
}
