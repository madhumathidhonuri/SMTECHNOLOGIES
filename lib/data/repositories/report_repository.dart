import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/trip_provider.dart';
import '../models/json_utils.dart';
import '../models/report_models.dart';
import '../models/user_trip.dart';
import '../models/vehicle.dart';

class ReportRepository {
  ReportRepository(this._api, this._ref);

  final ApiClient _api;
  final Ref _ref;

  /// Runs any `/api/reports/*` endpoint with a normalised query shape.
  Future<ReportResult> run({
    required ReportType type,
    required DateTime start,
    required DateTime end,
    String? vehicleId,
    List<String>? vehicleIds,
    String? mode,
    String? fromGeofenceId,
    String? toGeofenceId,
    String? geofenceId,
    CancelToken? cancelToken,
  }) async {
    // For consolidated and geofence endpoints: backend handles fleet-wide in one query.
    // Per-vehicle parallel calls would only return 1 row each, causing missing vehicles.
    final bool isFleetWideParallel = vehicleId == null &&
        type != ReportType.consolidated &&
        type != ReportType.fuelConsolidated &&
        type != ReportType.individual &&
        type != ReportType.routeHistory &&
        type != ReportType.geofenceTransit &&
        type != ReportType.geofenceSinglePlace &&
        type != ReportType.dailyTrip &&
        type != ReportType.ignition;

    final List<Vehicle> vehicles = _ref.read(fleetProvider).vehicles;

    if (isFleetWideParallel) {
      final List<String> allIds = vehicles.map((v) => v.id).toList();
      if (allIds.isNotEmpty) {
        // Fetch each vehicle — ignore individual failures so one bad vehicle
        // doesn't wipe the whole result set.
        final List<ReportResult> results = (await Future.wait(
          allIds.map((String id) async {
            final Vehicle? vehicle = vehicles.where((v) => v.id == id).firstOrNull;
            try {
              final ReportResult res = await _fetch(
                type: type,
                start: start,
                end: end,
                vehicleId: id,
                vehicle: vehicle,
                cancelToken: cancelToken,
              );

              // Filter row matching this vehicle (only for Consolidated & Fuel Consolidated)
              ReportResult filteredRes = res;
              if (type == ReportType.consolidated || type == ReportType.fuelConsolidated) {
                final List<ReportRow> matchingRows = res.rows.where((ReportRow row) =>
                  row.vehicleId == id ||
                  row.vehicleName == vehicle?.displayName ||
                  row.raw['vehicle_id'] == id
                ).toList();
                filteredRes = ReportResult(
                  rows: matchingRows,
                  summary: ReportSummary.fromRows(matchingRows),
                  columns: res.columns,
                );
              }

              return await _enrichResult(
                res: filteredRes,
                type: type,
                vehicle: vehicle,
                id: id,
                start: start,
                end: end,
                cancelToken: cancelToken,
              );
            } catch (err) {
              debugPrint('FETCH FAILED FOR VEHICLE $id ($type): $err');
              return const ReportResult(rows: <ReportRow>[], summary: ReportSummary());
            }
          }),
        ));
        final List<ReportRow> merged =
            results.expand((ReportResult r) => r.rows).toList();

        // De-duplicate rows by vehicle identification and date to handle bulk endpoints gracefully
        final Map<String, ReportRow> uniqueMap = <String, ReportRow>{};
        for (final ReportRow r in merged) {
          final String key = '${r.vehicleName ?? r.vehicleId ?? ""}_${r.plate ?? ""}_${r.date ?? ""}';
          uniqueMap[key] = r;
        }
        final List<ReportRow> deduplicated = uniqueMap.values.toList();

        return ReportResult(rows: deduplicated, summary: ReportSummary.fromRows(deduplicated));
      }
    }

    final Vehicle? vehicle = vehicleId != null
        ? vehicles.where((v) => v.id == vehicleId).firstOrNull
        : null;

    final ReportResult singleRes = await _fetch(
      type: type,
      start: start,
      end: end,
      vehicleId: vehicleId,
      vehicle: vehicle,
      vehicleIds: vehicleIds,
      mode: mode,
      fromGeofenceId: fromGeofenceId,
      toGeofenceId: toGeofenceId,
      geofenceId: geofenceId,
      cancelToken: cancelToken,
    );

    // Fallback: only for non-consolidated report types
    if (type != ReportType.consolidated &&
        type != ReportType.fuelConsolidated &&
        type != ReportType.individual &&
        type != ReportType.geofenceTransit &&
        type != ReportType.geofenceSinglePlace &&
        type != ReportType.dailyTrip &&
        type != ReportType.ignition &&
        vehicleId == null && singleRes.rows.isEmpty && vehicles.isNotEmpty) {
      final List<ReportResult> results = (await Future.wait(
        vehicles.map((Vehicle v) async {
          try {
            final ReportResult res = await _fetch(
              type: type,
              start: start,
              end: end,
              vehicleId: v.id,
              vehicle: v,
              cancelToken: cancelToken,
            );
            return await _enrichResult(
              res: res,
              type: type,
              vehicle: v,
              id: v.id,
              start: start,
              end: end,
              cancelToken: cancelToken,
            );
          } catch (err) {
            debugPrint('FETCH FAILED FOR VEHICLE ${v.id} (consolidated fallback): $err');
            return const ReportResult(rows: <ReportRow>[], summary: ReportSummary());
          }
        }),
      ));
      final List<ReportRow> merged =
          results.expand((ReportResult r) => r.rows).toList();
      
      final Map<String, ReportRow> uniqueMap = <String, ReportRow>{};
      for (final ReportRow r in merged) {
        final String key = '${r.vehicleName ?? r.vehicleId ?? ""}_${r.plate ?? ""}_${r.date ?? ""}';
        uniqueMap[key] = r;
      }
      final List<ReportRow> deduplicated = uniqueMap.values.toList();
      return ReportResult(rows: deduplicated, summary: ReportSummary.fromRows(deduplicated));
    }

    return await _enrichResult(
      res: singleRes,
      type: type,
      vehicle: vehicle,
      id: vehicleId,
      start: start,
      end: end,
      cancelToken: cancelToken,
    );
  }

  /// Helper to enrich and synthesize report results client-side (locations & odometer).
  Future<ReportResult> _enrichResult({
    required ReportResult res,
    required ReportType type,
    required Vehicle? vehicle,
    required String? id,
    required DateTime start,
    required DateTime end,
    required CancelToken? cancelToken,
  }) async {
    ReportResult processedRes = res;

    // 1. CONSOLIDATED & FUEL CONSOLIDATED — enrich rows with trips, stoppages, and overspeeds
    if ((type == ReportType.consolidated || type == ReportType.fuelConsolidated) &&
        processedRes.rows.isNotEmpty) {
      try {
        final List<ReportRow> updatedRows = await Future.wait(
          processedRes.rows.map((ReportRow row) async {
            // If the row already has valid activity & event counts, keep it
            if (row.tripCount > 0 || row.stoppageCount > 0 || row.overspeedingCount > 0) {
              return row;
            }

            final String? targetId = row.vehicleId ??
                id ??
                row.raw['vehicle_id']?.toString() ??
                row.raw['vehicleId']?.toString() ??
                vehicle?.id;

            if (targetId == null || targetId.isEmpty) {
              return row;
            }

            int trips = 0;
            int stops = 0;
            int overspeeds = 0;

            // Step 1: Probe /reports/individual which packages activity & event summaries together
            try {
              final dynamic indRes = await _api.get<dynamic>(
                '/reports/individual',
                query: <String, dynamic>{
                  'vehicleId': targetId,
                  'startDate': start.toUtc().toIso8601String(),
                  'endDate': end.toUtc().toIso8601String(),
                  'from': start.toUtc().toIso8601String(),
                  'to': end.toUtc().toIso8601String(),
                },
                cancelToken: cancelToken,
              );

              if (indRes is Map) {
                final dynamic s = indRes['summary'] ?? indRes['data']?['summary'];
                if (s is Map) {
                  final Map<String, dynamic> sMap = Map<String, dynamic>.from(s);
                  trips = asInt(sMap, <String>['trip_count', 'trips', 'totalTrips', 'total_trips']);
                  stops = asInt(sMap, <String>['stoppage_count', 'stoppages', 'totalStops', 'total_stops']);
                  overspeeds = asInt(sMap, <String>['overspeeding_count', 'overspeeding', 'violations', 'overspeed_count']);
                }
                if (trips == 0) {
                  final dynamic tList = indRes['trips'] ?? indRes['data']?['trips'];
                  if (tList is List) trips = tList.length;
                }
                if (stops == 0) {
                  final dynamic sList = indRes['stoppages'] ?? indRes['data']?['stoppages'];
                  if (sList is List) stops = sList.length;
                }
                if (overspeeds == 0) {
                  final dynamic oList = indRes['overspeeding'] ?? indRes['data']?['overspeeding'];
                  if (oList is List) overspeeds = oList.length;
                }
              }
            } catch (_) {}

            // Step 2: If any counts are still 0, query the specific report endpoints in parallel
            if (trips == 0 || stops == 0 || overspeeds == 0) {
              final List<int> dedicatedResults = await Future.wait<int>(<Future<int>>[
                if (trips == 0)
                  _api.get<dynamic>(
                    '/reports/trip',
                    query: <String, dynamic>{
                      'vehicleId': targetId,
                      'startDate': start.toUtc().toIso8601String(),
                      'endDate': end.toUtc().toIso8601String(),
                      'from': start.toUtc().toIso8601String(),
                      'to': end.toUtc().toIso8601String(),
                    },
                    cancelToken: cancelToken,
                  ).then((dynamic r) {
                    if (r is List) return r.length;
                    if (r is Map) {
                      final dynamic d = r['data'] ?? r['trips'] ?? r['records'] ?? r['rows'];
                      if (d is List) return d.length;
                      if (d is Map && d['total'] is num) return (d['total'] as num).toInt();
                    }
                    return 0;
                  }).catchError((_) => 0)
                else
                  Future<int>.value(trips),

                if (stops == 0)
                  _api.get<dynamic>(
                    '/reports/stoppages',
                    query: <String, dynamic>{
                      'vehicleId': targetId,
                      'startDate': start.toUtc().toIso8601String(),
                      'endDate': end.toUtc().toIso8601String(),
                      'from': start.toUtc().toIso8601String(),
                      'to': end.toUtc().toIso8601String(),
                    },
                    cancelToken: cancelToken,
                  ).then((dynamic r) {
                    if (r is List) return r.length;
                    if (r is Map) {
                      final dynamic d = r['data'] ?? r['stoppages'] ?? r['records'] ?? r['rows'];
                      if (d is List) return d.length;
                      if (d is Map && d['total'] is num) return (d['total'] as num).toInt();
                    }
                    return 0;
                  }).catchError((_) => 0)
                else
                  Future<int>.value(stops),

                if (overspeeds == 0)
                  _api.get<dynamic>(
                    '/reports/overspeeding',
                    query: <String, dynamic>{
                      'vehicleId': targetId,
                      'startDate': start.toUtc().toIso8601String(),
                      'endDate': end.toUtc().toIso8601String(),
                      'from': start.toUtc().toIso8601String(),
                      'to': end.toUtc().toIso8601String(),
                    },
                    cancelToken: cancelToken,
                  ).then((dynamic r) {
                    if (r is List) return r.length;
                    if (r is Map) {
                      final dynamic d = r['data'] ?? r['overspeeding'] ?? r['records'] ?? r['rows'];
                      if (d is List) return d.length;
                      if (d is Map && d['total'] is num) return (d['total'] as num).toInt();
                    }
                    return 0;
                  }).catchError((_) => 0)
                else
                  Future<int>.value(overspeeds),
              ]);

              trips = dedicatedResults[0];
              stops = dedicatedResults[1];
              overspeeds = dedicatedResults[2];
            }

            final Map<String, dynamic> mutableRaw = Map<String, dynamic>.of(row.raw);
            mutableRaw['trip_count'] = trips;
            mutableRaw['stoppage_count'] = stops;
            mutableRaw['overspeeding_count'] = overspeeds;

            return ReportRow.fromJson(mutableRaw);
          }),
        );

        processedRes = ReportResult(
          rows: updatedRows,
          summary: ReportSummary.fromRows(updatedRows),
          columns: updatedRows.isEmpty ? <String>[] : updatedRows.first.cells.keys.toList(),
        );
      } catch (e) {
        debugPrint('Failed to enrich consolidated activity & event counts: $e');
      }
    }

    // 2. DAILY DISTANCE ODOMETER BACK-CALCULATION
    if (type == ReportType.distance && processedRes.rows.isNotEmpty) {
      try {
        final List<ReportRow> sortedRows = List<ReportRow>.from(processedRes.rows)
          ..sort((ReportRow a, ReportRow b) {
            final DateTime da = a.date ?? DateTime(2000);
            final DateTime db = b.date ?? DateTime(2000);
            return db.compareTo(da); // Descending (newest first)
          });

        double runningOdo = vehicle?.odometer ?? 0.0;
        final List<ReportRow> updatedRows = <ReportRow>[];

        for (final ReportRow row in sortedRows) {
          final double dist = row.distanceTravelled ?? 0.0;
          final Map<String, dynamic> mutableRaw = Map<String, dynamic>.of(row.raw);

          if (vehicle != null && vehicle.odometer != null && vehicle.odometer! > 0) {
            mutableRaw['end_odometer'] = runningOdo;
            mutableRaw['start_odometer'] = runningOdo - dist;
            runningOdo = runningOdo - dist;
          }

          updatedRows.add(ReportRow.fromJson(mutableRaw));
        }

        // Keep them sorted descending (newest first)
        processedRes = ReportResult(
          rows: updatedRows,
          summary: ReportSummary.fromRows(updatedRows),
          columns: updatedRows.isEmpty ? <String>[] : updatedRows.first.cells.keys.toList(),
        );
      } catch (e) {
        debugPrint('Failed to back-calculate odometer for vehicle $id: $e');
      }
    }

    return processedRes;
  }

  Future<ReportResult> _fetch({
    required ReportType type,
    required DateTime start,
    required DateTime end,
    String? vehicleId,
    Vehicle? vehicle,
    List<String>? vehicleIds,
    String? mode,
    String? fromGeofenceId,
    String? toGeofenceId,
    String? geofenceId,
    CancelToken? cancelToken,
  }) async {
    // Special handling for manual trips: merge remote + local stored trips
    if (type == ReportType.manualTrip) {
      dynamic apiRes;
      try {
        apiRes = await _api.get<dynamic>(
          type.path,
          query: <String, dynamic>{
            if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
          },
          cancelToken: cancelToken,
        );
      } catch (e) {
        debugPrint('Manual trips remote fetch error (falling back to local): $e');
        apiRes = <Map<String, dynamic>>[];
      }

      final List<UserTrip> providerTrips = _ref.read(tripProvider).trips;
      final List<Map<String, dynamic>> localRaw =
          _ref.read(secureStoreProvider).getLocalTrips();
      final List<UserTrip> localTrips =
          localRaw.map(UserTrip.fromJson).toList();

      final Map<String, UserTrip> tripMap = <String, UserTrip>{};
      for (final UserTrip t in localTrips) {
        if (t.id.isNotEmpty) tripMap[t.id] = t;
      }
      for (final UserTrip t in providerTrips) {
        if (t.id.isNotEmpty) tripMap[t.id] = t;
      }

      if (apiRes is List) {
        for (final dynamic item in apiRes) {
          if (item is Map<String, dynamic>) {
            final UserTrip parsed = UserTrip.fromJson(item);
            if (parsed.id.isNotEmpty) tripMap[parsed.id] = parsed;
          }
        }
      }

      Iterable<UserTrip> matched = tripMap.values;
      if (vehicleId != null && vehicleId.isNotEmpty) {
        matched = matched.where((UserTrip t) => t.vehicleId == vehicleId);
      }

      // Filter by date range (start to end)
      matched = matched.where((UserTrip t) {
        final DateTime? tDate = t.startTime ?? t.createdAt;
        if (tDate == null) return true;
        return tDate.isAfter(start.subtract(const Duration(hours: 1))) &&
            tDate.isBefore(end.add(const Duration(hours: 1)));
      });

      final List<ReportRow> tripRows = matched.map((UserTrip t) {
        final Map<String, dynamic> rowMap = <String, dynamic>{
          'id': t.id,
          'vehicle_id': t.vehicleId,
          'vehicle_name': t.vehicleName ?? vehicle?.displayName ?? t.plate,
          'plate': t.plate ?? vehicle?.registrationNumber ?? t.vehicleName,
          'name': t.name,
          'trip_name': t.name,
          'status': t.status,
          'route_id': t.routeId,
          'route_name': t.routeName,
          'origin': t.origin ?? (t.routeName != null && t.routeName!.contains(' - ') ? t.routeName!.split(' - ').first.trim() : null),
          'destination': t.destination ?? (t.routeName != null && t.routeName!.contains(' - ') ? t.routeName!.split(' - ').last.trim() : null),
          'start_time': t.startTime?.toIso8601String(),
          'end_time': t.endTime?.toIso8601String(),
          'created_at': t.createdAt?.toIso8601String(),
          'distance': t.distanceKm,
          'distance_travelled': t.distanceKm,
          'distanceKm': t.distanceKm,
          'duration_seconds': t.durationSecs,
          'stoppage_count': t.stoppageCount,
        };
        return ReportRow.fromJson(rowMap);
      }).toList();

      return ReportResult(
        rows: tripRows,
        summary: ReportSummary.fromRows(tripRows),
        columns: tripRows.isEmpty ? <String>[] : tripRows.first.cells.keys.toList(),
      );
    }

    // Dedicated Ignition Report endpoint matches webapp (/api/vehicles/:id/ignition-report)
    if (type == ReportType.ignition) {
      final List<Vehicle> fleetVehicles = _ref.read(fleetProvider).vehicles;
      final String? targetId = vehicleId ??
          vehicle?.id ??
          (fleetVehicles.isNotEmpty ? fleetVehicles.first.id : null);

      if (targetId != null && targetId.isNotEmpty) {
        final String sDate =
            '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}T${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:${start.second.toString().padLeft(2, '0')}';
        final String eDate =
            '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}T${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}:${end.second.toString().padLeft(2, '0')}';

        try {
          final dynamic apiRes = await _api.get<dynamic>(
            '/vehicles/$targetId/ignition-report',
            query: <String, dynamic>{
              'startDate': sDate,
              'endDate': eDate,
            },
            cancelToken: cancelToken,
          );

          if (apiRes != null) {
            final ReportResult parsed = ReportResult.parse(apiRes);
            if (parsed.rows.isNotEmpty || !parsed.summary.isEmpty) {
              return parsed;
            }
          }
        } catch (e) {
          debugPrint('Vehicles ignition-report failed, falling back to /reports/ignition: $e');
        }
      }
    }

    final dynamic res = await _api.get<dynamic>(
      type.path,
      query: <String, dynamic>{
        'startDate': start.toUtc().toIso8601String(),
        'endDate': end.toUtc().toIso8601String(),
        'from': start.toUtc().toIso8601String(),
        'to': end.toUtc().toIso8601String(),
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
        if (vehicleIds != null && vehicleIds.isNotEmpty)
          'vehicleIds': vehicleIds.join(','),
        if (type == ReportType.idle) 'onlyIdle': true,
        if (mode != null && mode.isNotEmpty && mode != 'all') 'mode': mode,
        if (fromGeofenceId != null && fromGeofenceId.isNotEmpty)
          'fromGeofenceId': fromGeofenceId,
        if (toGeofenceId != null && toGeofenceId.isNotEmpty)
          'toGeofenceId': toGeofenceId,
        if (geofenceId != null && geofenceId.isNotEmpty)
          'geofenceId': geofenceId,
      },
      cancelToken: cancelToken,
    );

    dynamic filteredRes = res;
    if (vehicleId != null && vehicleId.isNotEmpty) {
      filteredRes = _filterPayloadByVehicle(res, vehicleId, vehicle);
    }

    if (vehicle != null && type != ReportType.consolidated && type != ReportType.fuelConsolidated) {
      _injectVehicleDetails(filteredRes, vehicle);
    }

    debugPrint('API RESPONSE FOR ${type.name}: $filteredRes');

    final ReportResult parsed = ReportResult.parse(filteredRes);
    if (type == ReportType.trip) {
      final List<ReportRow> filteredRows = parsed.rows
          .where((ReportRow row) => (row.distanceTravelled ?? 0.0) > 0.0)
          .toList();
      return ReportResult(
        rows: filteredRows,
        summary: ReportSummary.fromRows(filteredRows),
        columns: parsed.columns,
      );
    }
    return parsed;
  }

  dynamic _filterPayloadByVehicle(dynamic payload, String vehicleId, [Vehicle? vehicle]) {
    if (payload is List) {
      return payload.where((item) {
        if (item is Map) {
          final String? rowVehicleId = item['vehicle_id']?.toString() ??
              item['vehicleId']?.toString() ??
              item['id']?.toString() ??
              item['deviceId']?.toString() ??
              item['device_id']?.toString();
          if (rowVehicleId != null && rowVehicleId.isNotEmpty) {
            if (rowVehicleId == vehicleId) return true;
          }
          if (vehicle != null) {
            final String? itemPlate = item['plate']?.toString() ?? item['registrationNumber']?.toString();
            if (itemPlate != null && itemPlate.isNotEmpty) {
              if (itemPlate.toLowerCase() == vehicle.registrationNumber.toLowerCase() ||
                  itemPlate.toLowerCase() == vehicle.plate.toLowerCase()) {
                return true;
              }
            }
            final String? itemName = item['vehicle_name']?.toString() ?? item['name']?.toString();
            if (itemName != null && itemName.isNotEmpty) {
              if (itemName.toLowerCase() == vehicle.name.toLowerCase() ||
                  itemName.toLowerCase() == vehicle.displayName.toLowerCase()) {
                return true;
              }
            }
          }
          if (rowVehicleId != null && rowVehicleId.isNotEmpty) {
            return false;
          }
        }
        return true;
      }).toList();
    } else if (payload is Map<String, dynamic>) {
      final Map<String, dynamic> copy = Map<String, dynamic>.of(payload);
      copy.forEach((key, val) {
        if (val is List || val is Map) {
          copy[key] = _filterPayloadByVehicle(val, vehicleId);
        }
      });
      return copy;
    } else if (payload is Map) {
      try {
        final Map copy = Map.of(payload);
        copy.forEach((key, val) {
          if (val is List || val is Map) {
            copy[key] = _filterPayloadByVehicle(val, vehicleId);
          }
        });
        return copy;
      } catch (_) {}
    }
    return payload;
  }

  void _injectVehicleDetails(dynamic payload, Vehicle vehicle) {
    final String vehicleName = vehicle.displayName;
    final String registrationNumber = vehicle.registrationNumber;

    if (payload is List) {
      for (final dynamic item in payload) {
        if (item is Map<String, dynamic>) {
          item['vehicle_name'] = vehicleName;
          item['registrationNumber'] = registrationNumber;
          item['plate'] = registrationNumber;
        } else if (item is Map) {
          try {
            item['vehicle_name'] = vehicleName;
            item['registrationNumber'] = registrationNumber;
            item['plate'] = registrationNumber;
          } catch (_) {}
        }
      }
    } else if (payload is Map<String, dynamic>) {
      payload['vehicle_name'] = vehicleName;
      payload['registrationNumber'] = registrationNumber;
      payload['plate'] = registrationNumber;
      payload.forEach((String key, dynamic val) {
        if (val is List || val is Map) {
          _injectVehicleDetails(val, vehicle);
        }
      });
    } else if (payload is Map) {
      try {
        payload['vehicle_name'] = vehicleName;
        payload['registrationNumber'] = registrationNumber;
        payload['plate'] = registrationNumber;
      } catch (_) {}
      payload.forEach((dynamic key, dynamic val) {
        if (val is List || val is Map) {
          _injectVehicleDetails(val, vehicle);
        }
      });
    }
  }
}
