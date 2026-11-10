import 'dart:math';

/// Compresses a polyline using the Douglas-Peucker algorithm.
class PolylineSimplifier {
  /// Simplifies a list of GPS coordinates [lat, lng] using the Douglas-Peucker algorithm.
  /// The [epsilonMeters] is the maximum perpendicular deviation allowed in meters.
  static List<List<double>> simplify(List<List<double>> points, double epsilonMeters) {
    if (points.length <= 2) return points;

    // 1 degree latitude ~ 111,139 meters
    final double midLatRad = points[points.length ~/ 2][0] * pi / 180.0;
    final double cosLat = cos(midLatRad);
    final double tolDegSq = (epsilonMeters / 111139.0) * (epsilonMeters / 111139.0);

    final List<bool> keep = List<bool>.filled(points.length, true);

    void dp(int start, int end) {
      if (end <= start + 1) return;

      double maxDistSq = 0;
      int maxIdx = start;

      final double x1 = points[start][1] * cosLat;
      final double y1 = points[start][0];
      final double x2 = points[end][1] * cosLat;
      final double y2 = points[end][0];
      final double dx = x2 - x1;
      final double dy = y2 - y1;
      final double lineLenSq = dx * dx + dy * dy;

      for (int i = start + 1; i < end; i++) {
        final double x = points[i][1] * cosLat;
        final double y = points[i][0];
        double dSq;
        if (lineLenSq == 0) {
          final double ex = x - x1;
          final double ey = y - y1;
          dSq = ex * ex + ey * ey;
        } else {
          // Perpendicular distance squared from point (x, y) to line segment
          final double cross = (dy * x - dx * y + x2 * y1 - y2 * x1).abs();
          dSq = (cross * cross) / lineLenSq;
        }

        if (dSq > maxDistSq) {
          maxDistSq = dSq;
          maxIdx = i;
        }
      }

      if (maxDistSq > tolDegSq) {
        dp(start, maxIdx);
        dp(maxIdx, end);
      } else {
        for (int i = start + 1; i < end; i++) {
          keep[i] = false;
        }
      }
    }

    dp(0, points.length - 1);

    final List<List<double>> result = <List<double>>[];
    for (int i = 0; i < points.length; i++) {
      if (keep[i]) result.add(points[i]);
    }
    return result;
  }
}

