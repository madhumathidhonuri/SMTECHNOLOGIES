import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/vehicle.dart';
import '../config/brand_config.dart';
import 'geocoder.dart';

class ShareHelper {
  /// Shares vehicle live location details including resolved address, speed, status, and Google Maps URL.
  static Future<void> shareVehicleLocation(Vehicle vehicle) async {
    final double lat = vehicle.latitude ?? 0;
    final double lng = vehicle.longitude ?? 0;

    String address = vehicle.address ?? '';
    final bool isUnavailable = address.isEmpty ||
        address.toLowerCase().contains('location unavailable');

    if (isUnavailable && lat != 0 && lng != 0) {
      try {
        final String resolved = await Geocoder.getAddress(lat, lng);
        if (resolved != 'Location unavailable' && resolved.isNotEmpty) {
          address = resolved;
        } else {
          address = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
        }
      } catch (_) {
        address = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }
    }

    final String gmapsUrl = 'https://maps.google.com/?q=$lat,$lng';
    final String shareText = '''
*Live Location: ${vehicle.displayName}*
📍 Address: $address
🚀 Status: ${vehicle.status.label}
⚡ Speed: ${vehicle.speed.round()} km/h

MAPS:
$gmapsUrl
'''.trim();

    // 1. Copy formatted text to Clipboard
    await Clipboard.setData(ClipboardData(text: shareText));

    // 2. Attempt WhatsApp external app launch
    final Uri waSchemeUri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(shareText)}');
    final Uri waWebUri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(shareText)}');

    try {
      if (await canLaunchUrl(waSchemeUri)) {
        await launchUrl(waSchemeUri, mode: LaunchMode.externalApplication);
        return;
      } else if (await canLaunchUrl(waWebUri)) {
        await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // 3. Fallback to System Share dialog
    await Share.share(
      shareText,
      subject: 'Live Location: ${vehicle.displayName}',
    );
  }

  /// Shares official AIS-140 Fitment Certificate details and verification link.
  static Future<void> shareFitmentCertificate({
    required String vehiclePlate,
    required String certNumber,
    required String mfr,
    required String imei,
    required String serialNo,
    required String verifyUrl,
  }) async {
    final String shareText = '''
*${BrandConfig.appName} AIS-140 Fitment Certificate*
📄 Certificate No: $certNumber
🚛 Vehicle: $vehiclePlate
🏭 VLTD Manufacturer: $mfr
🔢 Device Serial No: $serialNo
📶 IMEI: $imei

✅ Verify & Download Certificate:
$verifyUrl
'''.trim();

    // 1. Copy formatted text to Clipboard
    await Clipboard.setData(ClipboardData(text: shareText));

    // 2. Attempt WhatsApp launch first
    final Uri waSchemeUri =
        Uri.parse('whatsapp://send?text=${Uri.encodeComponent(shareText)}');
    final Uri waWebUri =
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(shareText)}');

    try {
      if (await canLaunchUrl(waSchemeUri)) {
        await launchUrl(waSchemeUri, mode: LaunchMode.externalApplication);
        return;
      } else if (await canLaunchUrl(waWebUri)) {
        await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // 3. Fallback to system share sheet
    await Share.share(
      shareText,
      subject: 'Fitment Certificate - $vehiclePlate ($certNumber)',
    );
  }
}
