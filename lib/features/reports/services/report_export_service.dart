import '../../../core/config/brand_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/report_models.dart';
import 'download_helper/download_helper.dart';

class ReportExportService {
  const ReportExportService._();

  static List<List<dynamic>> _buildRowsForType(ReportType type, List<ReportRow> rows) {
    final List<List<dynamic>> tableData = <List<dynamic>>[];

    switch (type) {
      case ReportType.trip:
        tableData.add(<dynamic>[
          'Start Time',
          'Start Lat',
          'Start Lng',
          'End Time',
          'End Lat',
          'End Lng',
          'Duration (HH:MM:SS)',
          'Moving Time (HH:MM:SS)',
          'Distance (KM)',
          'Max Speed (km/h)',
          'Avg Speed (km/h)',
          'Vehicle',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            Fmt.dateTimeWeb(r.startTime),
            r.startLat ?? '',
            r.startLng ?? '',
            Fmt.dateTimeWeb(r.endTime),
            r.endLat ?? '',
            r.endLng ?? '',
            Fmt.durationWeb(r.durationSecVal),
            Fmt.durationWeb(r.movingSeconds),
            r.distanceTravelled?.toStringAsFixed(2) ?? '',
            r.maxSpeedVal?.toStringAsFixed(0) ?? '',
            r.avgSpeedVal?.toStringAsFixed(0) ?? '',
            r.vehicleName ?? '',
          ]);
        }
        break;

      case ReportType.distance:
        tableData.add(<dynamic>[
          'Vehicle',
          'Plate',
          'Org',
          'Date',
          'Start Odometer',
          'End Odometer',
          'Distance Travelled (KM)',
          'Points Logged',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '',
            r.plate ?? '-',
            r.orgName ?? BrandConfig.appName,
            Fmt.dateWeb(r.date),
            r.startOdometer?.toStringAsFixed(0) ?? '',
            r.endOdometer?.toStringAsFixed(0) ?? '',
            '${r.distanceTravelled?.toStringAsFixed(0) ?? '0'} km',
            r.pointCount,
          ]);
        }
        break;

      case ReportType.overspeeding:
        tableData.add(<dynamic>[
          'Vehicle',
          'Date & Time',
          'OverSpeed (km/h)',
          'OverSpeed Duration',
          'Driver Name',
          'Driver Mobile Number',
          'Latitude',
          'Longitude',
          'Distance Covered (KM)',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '',
            Fmt.dateTimeWeb(r.startTime),
            r.maxSpeedVal?.toStringAsFixed(0) ?? '',
            Fmt.durationWeb(r.durationSecVal),
            r.driverName ?? '-',
            r.driverPhone ?? '-',
            r.latitude ?? '',
            r.longitude ?? '',
            r.distanceTravelled?.toStringAsFixed(2) ?? '0.00',
          ]);
        }
        break;

      case ReportType.stoppages:
      case ReportType.idle:
        tableData.add(<dynamic>[
          'Vehicle',
          'Status',
          'Start Time',
          'End Time',
          'Duration (HH:MM:SS)',
          'Latitude',
          'Longitude',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '',
            r.status ?? (type == ReportType.idle ? 'Idle' : 'Parked'),
            Fmt.dateTimeWeb(r.startTime),
            Fmt.dateTimeWeb(r.endTime),
            Fmt.durationWeb(r.durationSecVal),
            r.latitude ?? '',
            r.longitude ?? '',
          ]);
        }
        break;

      case ReportType.individual:
        tableData.add(<dynamic>[
          'Plate',
          'Total Distance (km)',
          'Running Time (HH:MM:SS)',
          'Idle Time (HH:MM:SS)',
          'Stoppage Time (HH:MM:SS)',
          'Total Time (HH:MM:SS)',
          'Trip Count',
          'Stoppages',
          'Overspeeding',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.plate?.isNotEmpty == true ? r.plate! : (r.vehicleName ?? '-'),
            '${r.distanceTravelled?.toStringAsFixed(0) ?? '0'} km',
            Fmt.secsToHms(r.runningSeconds ?? r.runningMins * 60),
            Fmt.secsToHms(r.idleSeconds ?? r.idleMins * 60),
            Fmt.secsToHms(r.stoppedSeconds ?? r.stoppedMins * 60),
            Fmt.secsToHms(r.totalSeconds),
            r.tripCount,
            r.stoppageCount,
            r.overspeedingCount,
          ]);
        }
        break;

      case ReportType.consolidated:
        tableData.add(<dynamic>[
          'Vehicle',
          'Plate',
          'Distance Travelled (km)',
          'Running Time (HH:MM:SS)',
          'Stopping Time (HH:MM:SS)',
          'Idle Time (HH:MM:SS)',
          'Engine On Time (HH:MM:SS)',
          'Trip Count',
          'Stoppage Count',
          'Overspeeding Count',
          'From Location',
          'To Location',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '-',
            r.plate ?? '-',
            r.distanceTravelled?.toStringAsFixed(1) ?? '0',
            Fmt.secsToHms(r.runningSeconds ?? r.runningMins * 60),
            Fmt.secsToHms(r.stoppedSeconds ?? r.stoppedMins * 60),
            Fmt.secsToHms(r.idleSeconds ?? r.idleMins * 60),
            Fmt.secsToHms((r.engineOnHours * 3600).round()),
            r.tripCount,
            r.stoppageCount,
            r.overspeedingCount,
            r.fromLocation ?? '',
            r.toLocation ?? '',
          ]);
        }
        break;

      case ReportType.fuelConsolidated:
        tableData.add(<dynamic>[
          'Vehicle',
          'Plate',
          'Starting Fuel (L)',
          'Ending Fuel (L)',
          'Consumption (L)',
          'Filling (L)',
          'Theft / Drain (L)',
          'Mileage (km/L)',
          'Hourly Consumption (L/h)',
          'Distance Travelled (km)',
          'Engine Run Time (HH:MM:SS)',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '-',
            r.plate ?? '-',
            r.startFuel?.toStringAsFixed(1) ?? '',
            r.endFuel?.toStringAsFixed(1) ?? '',
            r.consumption?.toStringAsFixed(1) ?? '',
            r.filling?.toStringAsFixed(1) ?? '',
            r.theft?.toStringAsFixed(1) ?? '',
            r.kmpl?.toStringAsFixed(1) ?? '',
            r.lph?.toStringAsFixed(1) ?? '',
            r.distanceTravelled?.toStringAsFixed(1) ?? '0',
            Fmt.secsToHms((r.engineOnHours * 3600).round()),
          ]);
        }
        break;

      case ReportType.geofenceTransit:
        tableData.add(<dynamic>[
          'Vehicle',
          'Plate',
          'Trip Type',
          'Origin Geofence',
          'Departure Time',
          'Destination Geofence',
          'Arrival Time',
          'Duration',
          'Distance (km)',
          'Avg Speed (km/h)',
          'Max Speed (km/h)',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '-',
            r.plate ?? '-',
            r.tripLabel ?? 'Corridor Trip',
            r.fromGeofenceName ?? 'Location A',
            Fmt.dateTimeWeb(r.departureTime ?? r.startTime),
            r.toGeofenceName ?? 'Location B',
            Fmt.dateTimeWeb(r.arrivalTime ?? r.endTime),
            r.durationFormatted ?? Fmt.durationWeb(r.durationSecVal),
            r.distanceTravelled?.toStringAsFixed(2) ?? '0.00',
            r.avgSpeedVal?.toStringAsFixed(0) ?? '-',
            r.maxSpeedVal?.toStringAsFixed(0) ?? '-',
          ]);
        }
        break;

      case ReportType.geofenceSinglePlace:
        tableData.add(<dynamic>[
          'Vehicle',
          'Plate',
          'Place / Geofence',
          'Entry Time',
          'Exit Time',
          'Duration Inside',
          'Idle Time Inside',
          'Max Speed Inside (km/h)',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '-',
            r.plate ?? '-',
            r.geofenceName ?? '-',
            Fmt.dateTimeWeb(r.entryTime ?? r.startTime),
            r.exitTime != null ? Fmt.dateTimeWeb(r.exitTime) : 'Inside / Active',
            r.durationFormatted ?? Fmt.durationWeb(r.durationSecVal),
            r.idleSecondsInside != null && r.idleSecondsInside! > 0
                ? Fmt.durationWeb(r.idleSecondsInside)
                : '0m',
            r.maxSpeedVal?.toStringAsFixed(0) ?? '-',
          ]);
        }
        break;

      case ReportType.dailyTrip:
        tableData.add(<dynamic>[
          'Date',
          'Vehicle',
          'Plate',
          'Start Time',
          'Start Location (Lat,Lng)',
          'End Time',
          'End Location (Lat,Lng)',
          'Total Distance (KM)',
          'Driving Time (HH:MM:SS)',
          'Stoppage Time (HH:MM:SS)',
          'Total Span (HH:MM:SS)',
          'Stops Count',
          'Legs Count',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            Fmt.dateWeb(r.date ?? r.startTime),
            r.vehicleName ?? '-',
            r.plate ?? '-',
            Fmt.dateTimeWeb(r.startTime),
            '${r.startLat ?? ''}, ${r.startLng ?? ''}',
            Fmt.dateTimeWeb(r.endTime),
            '${r.endLat ?? ''}, ${r.endLng ?? ''}',
            (r.totalDistanceVal ?? 0.0).toStringAsFixed(2),
            Fmt.durationWeb(r.drivingSeconds),
            Fmt.durationWeb(r.stoppedSeconds),
            Fmt.durationWeb(r.totalSpanSeconds),
            r.stopsCount,
            r.legsCount,
          ]);
        }
        break;

      case ReportType.ignition:
        tableData.add(<dynamic>[
          'Vehicle',
          'Plate',
          'Event Status',
          'Event Time',
          'Latitude',
          'Longitude',
        ]);
        for (final ReportRow r in rows) {
          tableData.add(<dynamic>[
            r.vehicleName ?? '-',
            r.plate ?? '-',
            (r.eventType ?? 'ON').toUpperCase(),
            Fmt.dateTimeWeb(r.deviceTime ?? r.startTime),
            r.latitude ?? '',
            r.longitude ?? '',
          ]);
        }
        break;

      default:
        if (rows.isNotEmpty) {
          final List<String> headers = rows.first.cells.keys.toList();
          tableData.add(headers);
          for (final ReportRow r in rows) {
            tableData.add(headers.map((String h) => r.cells[h] ?? '').toList());
          }
        }
        break;
    }

    return tableData;
  }

  static String _buildCsvString(List<List<dynamic>> tableData) {
    final StringBuffer sb = StringBuffer();
    for (final List<dynamic> row in tableData) {
      sb.writeln(row.map((dynamic e) {
        final String s = e.toString();
        if (s.contains(',') || s.contains('"') || s.contains('\n')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }).join(','));
    }
    return sb.toString();
  }

  static Future<void> exportCsv({
    required ReportType type,
    required List<ReportRow> rows,
  }) async {
    if (rows.isEmpty) return;

    final List<List<dynamic>> tableData = _buildRowsForType(type, rows);
    final String csv = _buildCsvString(tableData);
    final String fileName = '${type.name}_report_${DateTime.now().millisecondsSinceEpoch}.csv';

    await downloadFileUniversal(
      content: csv,
      fileName: fileName,
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static Future<void> exportExcel({
    required ReportType type,
    required List<ReportRow> rows,
  }) async {
    if (rows.isEmpty) return;

    final List<List<dynamic>> tableData = _buildRowsForType(type, rows);
    final String csv = _buildCsvString(tableData);
    final String fileName = '${type.name}_report_${DateTime.now().millisecondsSinceEpoch}.csv';

    await downloadFileUniversal(
      content: csv,
      fileName: fileName,
      mimeType: 'application/vnd.ms-excel;charset=utf-8',
    );
  }

  static Future<void> exportPdf({
    required ReportType type,
    required List<ReportRow> rows,
  }) async {
    if (rows.isEmpty) return;

    final List<List<dynamic>> tableData = _buildRowsForType(type, rows);
    if (tableData.isEmpty) return;

    final List<dynamic> headers = tableData.first;
    final List<List<dynamic>> dataRows = tableData.sublist(1);

    final StringBuffer html = StringBuffer();
    html.writeln('<!DOCTYPE html>');
    html.writeln('<html><head><meta charset="utf-8">');
    html.writeln('<title>\${type.label} - \${BrandConfig.appName} Report</title>');
    html.writeln('<style>');
    html.writeln('@media print { @page { size: landscape; margin: 12mm; } }');
    html.writeln('body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 24px; color: #0F172A; }');
    html.writeln('.header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #0F766E; padding-bottom: 12px; margin-bottom: 16px; }');
    html.writeln('.title { font-size: 20px; font-weight: 700; color: #1E293B; margin: 0; }');
    html.writeln('.meta { font-size: 12px; color: #64748B; margin-top: 4px; }');
    html.writeln('.badge { background: #CCFBF1; color: #0F766E; font-weight: 700; font-size: 11px; padding: 4px 8px; border-radius: 6px; }');
    html.writeln('table { width: 100%; border-collapse: collapse; font-size: 11px; margin-top: 12px; }');
    html.writeln('th { background: #F8FAFC; color: #475569; font-weight: 700; text-align: left; padding: 8px 10px; border-bottom: 2px solid #E2E8F0; white-space: nowrap; }');
    html.writeln('td { padding: 7px 10px; border-bottom: 1px solid #F1F5F9; color: #334155; }');
    html.writeln('tr:nth-child(even) td { background: #FAFAFA; }');
    html.writeln('.footer { margin-top: 24px; text-align: right; font-size: 10px; color: #94A3B8; }');
    html.writeln('</style>');
    html.writeln('</head><body>');
    html.writeln('<div class="header">');
    html.writeln('  <div>');
    html.writeln('    <h1 class="title">\${type.label}</h1>');
    html.writeln('    <div class="meta">Generated: \${DateTime.now().toLocal().toString().split(".")[0]} · Total Records: \${dataRows.length}</div>');
    html.writeln('  </div>');
    html.writeln('  <div class="badge">\${BrandConfig.appName} Fleet Management</div>');
    html.writeln('</div>');
    html.writeln('<table>');
    html.writeln('  <thead><tr>');
    for (final dynamic h in headers) {
      html.writeln('    <th>\$h</th>');
    }
    html.writeln('  </tr></thead>');
    html.writeln('  <tbody>');
    for (final List<dynamic> row in dataRows) {
      html.writeln('    <tr>');
      for (final dynamic cell in row) {
        html.writeln('      <td>\$cell</td>');
      }
      html.writeln('    </tr>');
    }
    html.writeln('  </tbody>');
    html.writeln('</table>');
    html.writeln('<div class="footer">Confidential · \${BrandConfig.appName} Fleet Operations · \${BrandConfig.legalEntityName}</div>');
    html.writeln('</body></html>');

    final String fileName = '${type.name}_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await openPrintablePdfUniversal(
      htmlContent: html.toString(),
      fileName: fileName,
    );
  }
}
