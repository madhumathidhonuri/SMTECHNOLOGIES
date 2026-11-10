import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/fleet_provider.dart';
import '../tabs/vehicle_playback_tab.dart';

class VehiclePlaybackScreen extends ConsumerWidget {
  const VehiclePlaybackScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(vehicleId));
    final String title = vehicle?.displayName ?? 'History';

    return Scaffold(
      appBar: AppBar(
        title: Text('$title - History'),
      ),
      body: VehiclePlaybackTab(vehicleId: vehicleId),
    );
  }
}
