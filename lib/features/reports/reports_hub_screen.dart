import 'package:flutter/material.dart';

import '../../data/models/report_models.dart';
import 'report_detail_screen.dart';

/// Reports screen entry point: displays the web-matching tabular reports hub.
class ReportsHubScreen extends StatelessWidget {
  final String? initialVehicleId;
  final ReportType? initialType;
  final String? initialFromGeofenceId;
  final String? initialToGeofenceId;
  final String? initialMode;

  const ReportsHubScreen({
    this.initialVehicleId,
    this.initialType,
    this.initialFromGeofenceId,
    this.initialToGeofenceId,
    this.initialMode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ReportDetailScreen(
      type: initialType ?? ReportType.trip,
      initialVehicleId: initialVehicleId,
      initialFromGeofenceId: initialFromGeofenceId,
      initialToGeofenceId: initialToGeofenceId,
      initialMode: initialMode,
    );
  }
}
