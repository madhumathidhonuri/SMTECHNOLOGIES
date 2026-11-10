import 'package:intl/intl.dart';

/// All user-visible value formatting lives here so units, precision and
/// locale behaviour stay identical across every screen.
class Fmt {
  const Fmt._();

  static final DateFormat _time = DateFormat('HH:mm:ss');
  static final DateFormat _timeSec = DateFormat('HH:mm:ss');
  static final DateFormat _time12Sec = DateFormat('hh:mm:ss a');
  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateShort = DateFormat('dd MMM');
  static final DateFormat _dateTime = DateFormat('dd MMM, HH:mm:ss');
  static final DateFormat _full = DateFormat('EEE, dd MMM yyyy • HH:mm:ss');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');
  static final DateFormat _webDate = DateFormat('dd-MM-yyyy');
  static final DateFormat _webDateTime = DateFormat('dd-MM-yyyy HH:mm:ss');
  static final DateFormat _webDateTimeFilter = DateFormat('dd-MM-yyyy hh:mm a');

  static String time(DateTime? d) => d == null ? '—' : _time.format(d);
  static String timeSec(DateTime? d) => d == null ? '—' : _timeSec.format(d);
  static String time12Sec(DateTime? d) => d == null ? '—' : _time12Sec.format(d);
  static String date(DateTime? d) => d == null ? '—' : _date.format(d);
  static String dateShort(DateTime? d) => d == null ? '—' : _dateShort.format(d);
  static String dateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);
  static String full(DateTime? d) => d == null ? '—' : _full.format(d);
  static String iso(DateTime d) => _iso.format(d);
  static String dateWeb(DateTime? d) => d == null ? '—' : _webDate.format(d);
  static String dateTimeWeb(DateTime? d) => d == null ? '—' : _webDateTime.format(d);
  static String dateTimeFilter(DateTime? d) => d == null ? '—' : _webDateTimeFilter.format(d);

  /// Clock duration format "HH:mm:ss" matching web app (e.g. 00:07:38).
  static String durationWeb(int? seconds) => secsToHms(seconds);

  /// Format duration for vehicle status since metrics.
  /// When >= 1 day: displays days-wise (e.g. "1d 2h 19m" or "3d").
  /// When < 1 day: displays "hh:mm:ss" (e.g. "00:06:04").
  static String statusDuration(DateTime? d) {
    if (d == null) return '-';
    final Duration diff = DateTime.now().difference(d);
    if (diff.isNegative) return '00:00:00';

    final int days = diff.inDays;
    final int hours = diff.inHours % 24;
    final int minutes = diff.inMinutes % 60;
    final int seconds = diff.inSeconds % 60;

    if (days > 0) {
      if (hours > 0 && minutes > 0) {
        return '${days}d ${hours}h ${minutes}m';
      } else if (hours > 0) {
        return '${days}d ${hours}h';
      } else if (minutes > 0) {
        return '${days}d ${minutes}m';
      }
      return '${days}d';
    }

    final String hStr = hours.toString().padLeft(2, '0');
    final String mStr = minutes.toString().padLeft(2, '0');
    final String sStr = seconds.toString().padLeft(2, '0');
    return '$hStr:$mStr:$sStr';
  }

  /// "just now", "4m ago", "2h ago", "3d ago" — the primary freshness signal
  /// on every vehicle card.
  static String relative(DateTime? d) {
    if (d == null) return 'Waiting for data';
    final Duration diff = DateTime.now().difference(d);

    if (diff.isNegative) return 'just now';
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  /// "hh:mm:ss" format for all durations.
  static String duration(Duration d) => durationHms(d);

  /// Converts raw seconds → "hh:mm:ss" (e.g. 3661 → "01:01:01").
  /// Returns "00:00:00" for null/negative input.
  static String secsToHms(int? seconds) {
    if (seconds == null || seconds < 0) return '00:00:00';
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Duration from a [Duration] object in "hh:mm:ss" format.
  static String durationHms(Duration d) {
    final int totalSeconds = d.inSeconds.abs();
    return secsToHms(totalSeconds);
  }

  static String durationFromSeconds(int? seconds) =>
      secsToHms(seconds);


  /// Distance with adaptive precision: metres under 1 km.
  static String distance(double? km, {bool imperial = false}) {
    if (km == null) return '—';
    if (imperial) {
      final double miles = km * 0.621371;
      return '${miles.toStringAsFixed(miles < 10 ? 2 : 1)} mi';
    }
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 100) return '${km.toStringAsFixed(1)} km';
    return '${km.toStringAsFixed(0)} km';
  }

  static String speed(double? kph, {bool imperial = false}) {
    if (kph == null) return '—';
    if (imperial) return '${(kph * 0.621371).round()} mph';
    return '${kph.round()} km/h';
  }

  static String percent(double? v, {int decimals = 0}) =>
      v == null ? '—' : '${v.toStringAsFixed(decimals)}%';

  static String currency(double amount, {String code = 'INR'}) {
    final NumberFormat f = NumberFormat.currency(
      symbol: switch (code.toUpperCase()) {
        'INR' => '₹',
        'USD' => '\$',
        'EUR' => '€',
        'GBP' => '£',
        'AED' => 'AED ',
        _ => '$code ',
      },
      decimalDigits: amount == amount.roundToDouble() ? 0 : 2,
    );
    return f.format(amount);
  }

  /// 1 234 → "1.2k" for stat tiles.
  static String compactNumber(num v) =>
      NumberFormat.compact().format(v);

  /// Truncates long reverse-geocoded addresses without cutting mid-word.
  static String address(String? a, {int max = 64}) {
    if (a == null || a.trim().isEmpty) return 'Location unavailable';
    final String s = a.trim();
    if (s.length <= max) return s;
    final int cut = s.lastIndexOf(' ', max);
    return '${s.substring(0, cut > 20 ? cut : max)}…';
  }

  static String coordinates(double? lat, double? lng) {
    if (lat == null || lng == null) return '—';
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  /// Compass label from a bearing.
  static String heading(double degrees) {
    const List<String> dirs = <String>[
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW',
    ];
    final int i = (((degrees % 360) + 22.5) ~/ 45) % 8;
    return dirs[i];
  }

  static String expiry(int? days) {
    if (days == null) return 'No expiry set';
    if (days < 0) return 'Expired ${-days}d ago';
    if (days == 0) return 'Expires today';
    if (days == 1) return 'Expires tomorrow';
    if (days < 30) return 'Expires in $days days';
    final int months = (days / 30).floor();
    return 'Expires in $months month${months > 1 ? 's' : ''}';
  }
}
