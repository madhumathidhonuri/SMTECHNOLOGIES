import 'package:latlong2/latlong.dart';

import '../../data/models/trip.dart';

/// Utility class for cleaning GPS trajectories and eliminating stationary drift / jitter.
class GpsFilter {
  /// Filters out stationary GPS drift / jitter (spiderwebbing) when a vehicle is stopped or parked.
  ///
  /// When a vehicle is stationary (speed <= [stationarySpeedThresholdKph] or ignition is off),
  /// GPS fixes naturally fluctuate within a 5-25m radius due to satellite geometry,
  /// atmospheric delay, and multipath interference. Connecting these fixes chronologically
  /// creates a chaotic "spiderweb" or scribble on the map over time.
  ///
  /// This filter locks to a stationary "anchor" point when motion stops, ignoring
  /// jitter fixes within [driftRadiusMeters] until the vehicle actually resumes moving.
  static List<TrackPoint> filterStationaryDrift(
    List<TrackPoint> points, {
    double stationarySpeedThresholdKph = 2.5,
    double driftRadiusMeters = 25.0,
  }) {
    if (points.length <= 1) return points;

    const Distance distCalc = Distance();
    final List<TrackPoint> clean = <TrackPoint>[];

    TrackPoint? anchor;
    bool isStationary = false;

    for (final TrackPoint pt in points) {
      if (!pt.isValid) continue;

      if (clean.isEmpty) {
        clean.add(pt);
        anchor = pt;
        isStationary = pt.speed <= stationarySpeedThresholdKph;
        continue;
      }

      final double distFromAnchor = distCalc(anchor!.latLng, pt.latLng);
      final bool isLowSpeed = pt.speed <= stationarySpeedThresholdKph;

      if (isLowSpeed) {
        if (!isStationary) {
          // Transition from moving to stationary
          isStationary = true;
          anchor = pt;
          // Ensure the polyline reaches this stop location
          if (distCalc(clean.last.latLng, pt.latLng) >= 3.0) {
            clean.add(pt);
          }
        } else {
          // Vehicle is stationary. Suppress drift within [driftRadiusMeters].
          if (distFromAnchor < driftRadiusMeters) {
            continue;
          }

          // If ignition is off, even larger multipath fluctuations should be suppressed
          if (!pt.ignition && distFromAnchor < (driftRadiusMeters * 2.0)) {
            continue;
          }

          // If outside drift radius while stationary, update anchor to the new resting spot
          anchor = pt;
        }
      } else {
        // Vehicle is moving (speed > stationarySpeedThresholdKph)
        if (isStationary) {
          // Only break out of stationary state if movement is real (away from anchor or fast)
          if (distFromAnchor >= 15.0 || pt.speed > 5.0) {
            isStationary = false;
            anchor = pt;
            clean.add(pt);
          }
        } else {
          // Normal moving path: skip negligible sub-meter micro-noise
          if (distCalc(clean.last.latLng, pt.latLng) >= 2.0) {
            clean.add(pt);
            anchor = pt;
          }
        }
      }
    }

    return clean;
  }
}

