import 'package:flutter/material.dart';
import '../../core/utils/geocoder.dart';
import '../../data/models/vehicle.dart';

/// Displays a fully-detailed, Google Geocoded address for a vehicle.
///
/// Previously, if the backend sent ANY address string (even a short one like
/// "Pottipadu, Telaprolu, AP 521109"), this widget used it as-is and NEVER
/// called the Google Geocoder. This meant the user never saw the full street-
/// level detail (shop name, galli, locality, district, state, country, pincode).
///
/// Now, the backend address is shown immediately as a quick placeholder, and
/// the Google Geocoder is ALWAYS called for the detailed result. Once Google's
/// full address arrives, it replaces the placeholder.
class LiveAddress extends StatefulWidget {
  const LiveAddress({
    required this.vehicle,
    this.max,
    this.style,
    this.textAlign,
    this.onAddressResolved,
    super.key,
  });

  final Vehicle vehicle;
  final int? max;
  final TextStyle? style;
  final TextAlign? textAlign;
  final ValueChanged<String>? onAddressResolved;

  @override
  State<LiveAddress> createState() => _LiveAddressState();
}

class _LiveAddressState extends State<LiveAddress> {
  String? _resolvedAddress;
  double? _lastResolvedLat;
  double? _lastResolvedLng;

  @override
  void initState() {
    super.initState();
    if (widget.vehicle.hasLocation) {
      final String? cached = Geocoder.getCachedAddress(
          widget.vehicle.latitude!, widget.vehicle.longitude!);
      if (cached != null && cached.isNotEmpty) {
        _resolvedAddress = cached;
      }
    }
    if (_resolvedAddress == null &&
        widget.vehicle.address != null &&
        widget.vehicle.address!.trim().isNotEmpty) {
      _resolvedAddress =
          Geocoder.formatToNearestAddress(widget.vehicle.address!);
    }
    _resolve();
  }

  @override
  void didUpdateWidget(covariant LiveAddress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.vehicle.hasLocation) {
      if (_resolvedAddress != null) {
        setState(() {
          _resolvedAddress = null;
          _lastResolvedLat = null;
          _lastResolvedLng = null;
        });
      }
      return;
    }

    // Skip re-querying if vehicle moved less than ~50 meters and address is already resolved
    final double lat = widget.vehicle.latitude!;
    final double lng = widget.vehicle.longitude!;
    if (_resolvedAddress != null &&
        _lastResolvedLat != null &&
        _lastResolvedLng != null) {
      final double dLat = (lat - _lastResolvedLat!).abs();
      final double dLng = (lng - _lastResolvedLng!).abs();
      // ~0.00045 degrees is approximately 50 meters
      if (dLat < 0.00045 && dLng < 0.00045) {
        return;
      }
    }

    if (oldWidget.vehicle.latitude != widget.vehicle.latitude ||
        oldWidget.vehicle.longitude != widget.vehicle.longitude ||
        oldWidget.vehicle.address != widget.vehicle.address) {
      _resolve();
    }
  }

  void _resolve() {
    if (!widget.vehicle.hasLocation) {
      if (mounted) {
        setState(() {
          _resolvedAddress = null;
          _lastResolvedLat = null;
          _lastResolvedLng = null;
        });
      }
      return;
    }

    _lastResolvedLat = widget.vehicle.latitude;
    _lastResolvedLng = widget.vehicle.longitude;

    // Show the backend address immediately as a temporary placeholder
    // so the user doesn't see a blank while Google geocoding runs.
    if (widget.vehicle.address != null &&
        widget.vehicle.address!.trim().isNotEmpty) {
      if (mounted) {
        setState(() {
          _resolvedAddress =
              Geocoder.formatToNearestAddress(widget.vehicle.address!);
        });
      }
    }

    // Call Geocoder for the detailed nearest address (~6 words)
    Geocoder.getAddress(widget.vehicle.latitude!, widget.vehicle.longitude!)
        .then((String addr) {
      if (mounted && addr != 'Location unavailable' && addr.isNotEmpty) {
        final bool isCoord =
            RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$').hasMatch(addr.trim());
        // Only overwrite existing address if new addr is a real address or we have nothing yet
        if (!isCoord ||
            _resolvedAddress == null ||
            _resolvedAddress == '...' ||
            RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$')
                .hasMatch(_resolvedAddress!.trim())) {
          setState(() {
            _resolvedAddress = addr;
          });
          widget.onAddressResolved?.call(addr);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _resolvedAddress != null
          ? _resolvedAddress!
          : (widget.vehicle.hasLocation ? '...' : 'Location unavailable'),
      maxLines: widget.max,
      overflow: widget.max != null ? TextOverflow.ellipsis : TextOverflow.visible,
      softWrap: true,
      textAlign: widget.textAlign,
      style: widget.style,
    );
  }
}
