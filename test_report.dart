import 'lib/data/models/report_models.dart';

void main() {
  final raw = {
    'start_lat': 12.34,
    'start_lng': 56.78,
    'end_lat': 12.35,
    'end_lng': 56.79,
    'start_time': '2023-01-01T00:00:00Z',
    'end_time': '2023-01-01T01:00:00Z',
    'duration_seconds': 3600.0,
  };
  
  final row = ReportRow(cells: const {}, raw: raw);
  print('durationSecVal: ${row.durationSecVal}');
  print('duration_seconds from raw: ${row.raw['duration_seconds']}');
}
