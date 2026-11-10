import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/alert.dart';
import '../config/brand_config.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  // Handled by system / app launch
}

/// Top-level background handler — required by FCM to be a static/top-level
/// function. Runs in a separate isolate with no access to app state, so it
/// only does work that is safe there.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[push] background message: ${message.messageId}');

  // If there's no notification payload, this is a data-only message.
  // We must render it manually so the user actually sees the alert.
  if (message.notification == null) {
    final Map<String, dynamic> data = message.data;
    final String type = (data['type'] ?? data['alertType'] ?? data['alert_type'] ?? data['event_type'] ?? '').toString().toLowerCase();

    // Background isolates don't share state with Riverpod, so we read SharedPreferences directly.
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    bool enabled = true;
    switch (type) {
      case 'sos':
      case 'panic':
      case 'crash':
      case 'accident':
      case 'tow':
      case 'power_cut':
        enabled = prefs.getBool('ft_notif_sos') ?? true;
        break;
      case 'theft':
      case 'theft_alarm':
      case 'safety_park':
      case 'tamper':
        enabled = prefs.getBool('ft_notif_theft') ?? true;
        break;
      case 'overspeed':
      case 'overspeeding':
        enabled = prefs.getBool('ft_notif_overspeed') ?? true;
        break;
      case 'geofence_enter':
      case 'geofenceenter':
      case 'geofence_exit':
      case 'geofenceexit':
        enabled = prefs.getBool('ft_notif_geofence') ?? true;
        break;
      case 'ignition_on':
      case 'ignition_off':
      case 'moving':
      case 'start_moving':
      case 'trip_started':
      case 'trip_start':
      case 'trip':
      case 'stopped':
      case 'idle':
      case 'stoppage':
        enabled = prefs.getBool('ft_notif_ignition') ?? true;
        break;
      case 'harsh_braking':
      case 'harsh_acceleration':
      case 'harsh_driving':
      case 'harsh':
        enabled = false;
        break;
    }

    final bool isTheft = data['isTheft'] == 'true' ||
        data['isTheft'] == true ||
        <String>['theft', 'theft_alarm', 'safety_park', 'tamper'].contains(type);
    if (!isTheft && !enabled) return;

    final _NotificationContent content = _buildNotificationContent(data, message.notification, type);

    final bool isCritical =
        <String>['sos', 'panic', 'power_cut', 'crash', 'tow'].contains(type);

    final String channelId = isTheft
        ? BrandConfig.theftChannelId
        : (isCritical ? BrandConfig.criticalChannelId : BrandConfig.alertsChannelId);
    final String channelName = isTheft
        ? BrandConfig.theftChannelName
        : (isCritical ? BrandConfig.criticalChannelName : BrandConfig.alertsChannelName);

    final FlutterLocalNotificationsPlugin local =
        FlutterLocalNotificationsPlugin();

    // Ensure the channel exists before showing, otherwise Android drops the notification
    // if it was never created or the app data was cleared.
    final AndroidNotificationChannel channel = isTheft
        ? const AndroidNotificationChannel(
            'theft_alarm_channel',
            'Theft Alarm (Safety Parking)',
            description: 'Emergency siren alerts when vehicle theft is detected.',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('police_siren'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: true,
          )
        : AndroidNotificationChannel(
            channelId,
            channelName,
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          );
    await local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Basic initialization required to show a notification from the background isolate
    await local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await local.show(
      message.hashCode,
      content.title,
      content.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: isTheft
              ? 'Emergency siren alerts when vehicle theft is detected.'
              : channel.description,
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true, // Forces popup / screen wakeup on lock screen
          sound: isTheft ? const RawResourceAndroidNotificationSound('police_siren') : null,
          audioAttributesUsage: isTheft ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
          category: isTheft ? AndroidNotificationCategory.alarm : (isCritical ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.status),
          playSound: true,
          enableVibration: true,
          color: isTheft ? const Color(0xFFDC2626) : const Color(0xFF4F6BFF),
          icon: '@drawable/ic_notification',
          styleInformation: BigTextStyleInformation(content.body),
        ),
        iOS: DarwinNotificationDetails(
          sound: isTheft ? 'police_siren.wav' : null,
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: (isTheft || isCritical)
              ? InterruptionLevel.critical
              : InterruptionLevel.active,
        ),
      ),
      payload: jsonEncode(data),
    );

    final String alertId = data['alertId']?.toString() ??
        data['id']?.toString() ??
        'push_${DateTime.now().millisecondsSinceEpoch}_${message.hashCode}';
    await PushService.saveLocalAlert(<String, dynamic>{
      'id': alertId,
      'type': type,
      'title': content.title,
      'message': content.body,
      'vehicleId': data['vehicleId'] ?? data['vehicle_id'],
      'vehicleName': data['vehicleName'] ?? data['vehicle_name'] ?? data['plate'],
      'createdAt': data['deviceTime'] ?? data['serverTime'] ?? DateTime.now().toIso8601String(),
      'latitude': double.tryParse(data['lat']?.toString() ?? ''),
      'longitude': double.tryParse(data['lng']?.toString() ?? ''),
      'address': data['address'] ?? data['location'] ?? data['place'],
      'isRead': false,
    });
  }
}

class _NotificationContent {
  _NotificationContent(this.title, this.body);
  final String title;
  final String body;
}

_NotificationContent _buildNotificationContent(Map<String, dynamic> data, RemoteNotification? n, String type) {
  final String rawTitle = n?.title ?? 
      (data['title'] as String?) ?? 
      (data['alert_title'] as String?) ?? 
      (data['alertTitle'] as String?) ?? 
      FleetAlert.titleFor(type);
      
  final String vehicleName = (data['vehicleName'] as String?) ?? 
      (data['vehicle_name'] as String?) ?? 
      (data['vehicleNumber'] as String?) ?? 
      '';

  // Format 1: Vehicle number, then alert type
  final String displayTitle = vehicleName.isNotEmpty ? '$vehicleName - $rawTitle' : rawTitle;

  String rawBody = n?.body ?? 
      (data['message'] as String?) ?? 
      (data['body'] as String?) ?? 
      (data['alert_message'] as String?) ?? 
      (data['alertMessage'] as String?) ??
      (data['alertText'] as String?) ??
      (data['alert_text'] as String?) ??
      '';
      
  if (rawBody.isEmpty && vehicleName.isEmpty) {
    rawBody = 'A new $rawTitle event has occurred.';
  }

  String finalBody = rawBody;

  // Format 2: Date & Time (or Duration)
  final String startTime = (data['startTime'] ?? data['start_time'] ?? '').toString();
  final String endTime = (data['endTime'] ?? data['end_time'] ?? '').toString();
  final String timeStr = (data['deviceTime'] ?? data['device_time'] ?? data['timestamp'] ?? data['time'] ?? '').toString();
  final String duration = (data['duration'] ?? data['durationMinutes'] ?? '').toString();

  if (startTime.isNotEmpty && endTime.isNotEmpty && startTime != endTime) {
    finalBody += '\n🕒 $startTime to $endTime';
    if (duration.isNotEmpty) finalBody += ' ($duration)';
  } else if (startTime.isNotEmpty && duration.isNotEmpty) {
    finalBody += '\n🕒 Started: $startTime ($duration)';
  } else if (startTime.isNotEmpty) {
    finalBody += '\n🕒 Started: $startTime (Ongoing)';
  } else if (timeStr.isNotEmpty) {
    finalBody += '\n🕒 $timeStr';
  }
  
  // Format 3: Location
  final String address = (data['address'] as String?) ??
      (data['location'] as String?) ??
      (data['place'] as String?) ??
      '';
  if (address.isNotEmpty) {
    finalBody += '\n📍 $address';
  }

  return _NotificationContent(displayTitle, finalBody.trim());
}

/// ─────────────────────────────────────────────────────────────────────
///  PUSH NOTIFICATIONS
/// ─────────────────────────────────────────────────────────────────────
///
/// Because the socket is deliberately dead in the background, FCM is the
/// *only* channel that can reach a user whose app is closed. This service:
///
///  * requests notification permission at a contextual moment (not at launch)
///  * registers/refreshes the device token with the backend
///  * renders foreground messages through flutter_local_notifications
///    (FCM does not display them itself while the app is visible)
///  * routes taps to the right screen via [onNotificationTap]
class PushService {
  PushService({
    required Future<void> Function(String token) onTokenRefresh,
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(Map<String, dynamic> data) onForegroundMessage,
    required bool Function(String type) isNotificationEnabled,
  })  : _onTokenRefresh = onTokenRefresh,
        _onNotificationTap = onNotificationTap,
        _onForegroundMessage = onForegroundMessage,
        _isNotificationEnabled = isNotificationEnabled;

  final Future<void> Function(String token) _onTokenRefresh;
  final void Function(Map<String, dynamic> data) _onNotificationTap;
  final void Function(Map<String, dynamic> data) _onForegroundMessage;
  final bool Function(String type) _isNotificationEnabled;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;

  bool _initialized = false;

  /// High-importance channel so critical alerts (SOS, power cut) can pop
  /// as heads-up notifications on Android 8+.
  static const AndroidNotificationChannel _criticalChannel =
      AndroidNotificationChannel(
    BrandConfig.criticalChannelId,
    BrandConfig.criticalChannelName,
    description: BrandConfig.criticalChannelDesc,
    importance: Importance.max,
    enableVibration: true,
    playSound: true,
  );

  static const AndroidNotificationChannel _theftChannel =
      AndroidNotificationChannel(
    BrandConfig.theftChannelId,
    BrandConfig.theftChannelName,
    description: BrandConfig.theftChannelDesc,
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('police_siren'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _generalChannel =
      AndroidNotificationChannel(
    BrandConfig.alertsChannelId,
    BrandConfig.alertsChannelName,
    description: BrandConfig.alertsChannelDesc,
    importance: Importance.defaultImportance,
    enableVibration: true,
    playSound: true,
  );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _setupLocalNotifications();

    // Show alerts on iOS while the app is foregrounded.
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _fgSub = FirebaseMessaging.onMessage.listen(_handleForeground);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage m) => _onNotificationTap(_dataOf(m)),
    );

    // Cold start from a notification tap.
    final RemoteMessage? initial = await _fcm.getInitialMessage();
    if (initial != null) {
      // Defer so the router is mounted before we navigate.
      Future<void>.delayed(
        const Duration(milliseconds: 900),
        () => _onNotificationTap(_dataOf(initial)),
      );
    }

    _tokenSub = _fcm.onTokenRefresh.listen(_onTokenRefresh);

    // Request battery optimization exemption on Android so Doze mode
    // does not throttle FCM delivery. Prompt once on first launch only to avoid
    // annoying OEM dialogs on every app startup.
    if (Platform.isAndroid) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final bool hasPrompted = prefs.getBool('has_prompted_battery_optimization') ?? false;
        if (!hasPrompted) {
          const MethodChannel batteryChannel =
              MethodChannel(BrandConfig.batteryChannel);
          final bool isIgnoring = await batteryChannel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
          await prefs.setBool('has_prompted_battery_optimization', true);
          if (!isIgnoring) {
            await batteryChannel.invokeMethod('requestIgnoreBatteryOptimizations');
          }
        }
      } catch (_) {
        // Non-fatal — FCM high-priority will still deliver most notifications
        // even without the exemption on newer Android versions.
      }
    }
  }

  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@drawable/ic_notification');

    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (NotificationResponse r) async {
        if (r.payload == null || r.payload!.isEmpty) return;
        try {
          final data = jsonDecode(r.payload!) as Map<String, dynamic>;
          _onNotificationTap(data);
        } catch (_) {/* malformed payload — ignore */}
      },
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImpl =
        _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImpl?.createNotificationChannel(_criticalChannel);
    await androidImpl?.createNotificationChannel(_theftChannel);
    await androidImpl?.createNotificationChannel(_generalChannel);
  }

  /// Contextual permission request. Call this after the user has seen the
  /// dashboard once — never on the very first frame.
  Future<bool> requestPermission() async {
    final NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final bool granted = settings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) await syncToken();
    return granted;
  }

  Future<bool> hasPermission() async {
    final NotificationSettings s = await _fcm.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Pushes the current device token to the backend so it can target alerts.
  Future<String?> syncToken() async {
    try {
      // APNs must be ready on iOS before an FCM token exists.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final String? apns = await _fcm.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      final String? token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await _onTokenRefresh(token);
      }
      return token;
    } catch (e) {
      debugPrint('[push] token sync failed: $e');
      return null;
    }
  }

  void _handleForeground(RemoteMessage message) {
    final Map<String, dynamic> data = _dataOf(message);
    final String type = (data['type'] ?? data['alertType'] ?? data['alert_type'] ?? data['event_type'] ?? '').toString().toLowerCase();

    final bool isTheft = data['isTheft'] == 'true' ||
        data['isTheft'] == true ||
        <String>['theft', 'theft_alarm', 'safety_park', 'tamper'].contains(type);

    if (!isTheft && !_isNotificationEnabled(type)) {
      debugPrint('[push] notification disabled for type $type, ignoring');
      return;
    }

    _onForegroundMessage(data);

    final RemoteNotification? n = message.notification;
    final _NotificationContent content = _buildNotificationContent(data, n, type);

    final bool isCritical = <String>['sos', 'panic', 'power_cut', 'crash', 'tow']
        .contains(type);

    final AndroidNotificationChannel channel = isTheft
        ? _theftChannel
        : (isCritical ? _criticalChannel : _generalChannel);

    final int notifId = data['alertId'] != null ? data['alertId'].hashCode : message.hashCode;
    _local.show(
      notifId,
      content.title,
      content.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.high,
          fullScreenIntent: true,
          sound: isTheft ? const RawResourceAndroidNotificationSound('police_siren') : null,
          audioAttributesUsage: isTheft ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
          category: isTheft ? AndroidNotificationCategory.alarm : (isCritical ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.status),
          playSound: true,
          enableVibration: true,
          color: isTheft ? const Color(0xFFDC2626) : const Color(0xFF4F6BFF),
          icon: '@drawable/ic_notification',
          styleInformation: BigTextStyleInformation(content.body),
        ),
        iOS: DarwinNotificationDetails(
          sound: isTheft ? 'police_siren.wav' : null,
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: (isTheft || isCritical)
              ? InterruptionLevel.critical
              : InterruptionLevel.active,
        ),
      ),
      payload: jsonEncode(data),
    );

    final String alertId = data['alertId']?.toString() ??
        data['id']?.toString() ??
        'push_${DateTime.now().millisecondsSinceEpoch}_${message.hashCode}';
    PushService.saveLocalAlert(<String, dynamic>{
      'id': alertId,
      'type': type,
      'title': content.title,
      'message': content.body,
      'vehicleId': data['vehicleId'] ?? data['vehicle_id'],
      'vehicleName': data['vehicleName'] ?? data['vehicle_name'] ?? data['plate'],
      'createdAt': data['deviceTime'] ?? data['serverTime'] ?? DateTime.now().toIso8601String(),
      'latitude': double.tryParse(data['lat']?.toString() ?? ''),
      'longitude': double.tryParse(data['lng']?.toString() ?? ''),
      'address': data['address'] ?? data['location'] ?? data['place'],
      'isRead': false,
    });
  }

  static const String _localAlertsKey = 'local_push_alerts_v1';

  static Future<void> saveLocalAlert(Map<String, dynamic> alertMap) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_localAlertsKey) ?? <String>[];
      final String? rawId = alertMap['id']?.toString() ?? alertMap['alertId']?.toString();
      final String vId = alertMap['vehicleId']?.toString() ?? alertMap['vehicle_id']?.toString() ?? '';
      final String type = (alertMap['type'] ?? alertMap['alertType'] ?? 'alert').toString().toLowerCase().trim();
      
      final String timeStr = (alertMap['createdAt'] ?? alertMap['deviceTime'] ?? alertMap['serverTime'] ?? '').toString();
      final DateTime time = DateTime.tryParse(timeStr) ?? DateTime.now();
      // 5-minute bucket for deduplicating burst alerts
      final int bucket5Min = time.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
      
      final String alertId = (rawId != null && rawId.isNotEmpty && !rawId.startsWith('alert_') && !rawId.startsWith('push_'))
          ? rawId
          : (vId.isNotEmpty ? '${type}_${vId}_$bucket5Min' : 'alert_${type}_$bucket5Min');

      final Map<String, dynamic> clean = <String, dynamic>{
        ...alertMap,
        'id': alertId,
      };
      final String encoded = jsonEncode(clean);
      list.removeWhere((String item) {
        try {
          final dynamic decoded = jsonDecode(item);
          return decoded is Map && decoded['id']?.toString() == alertId;
        } catch (_) {
          return false;
        }
      });
      list.insert(0, encoded);
      if (list.length > 200) {
        list.removeRange(200, list.length);
      }
      await prefs.setStringList(_localAlertsKey, list);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getLocalAlerts() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_localAlertsKey) ?? <String>[];
      final List<Map<String, dynamic>> res = <Map<String, dynamic>>[];
      for (final String s in list) {
        try {
          final dynamic decoded = jsonDecode(s);
          if (decoded is Map<String, dynamic>) {
            res.add(decoded);
          } else if (decoded is Map) {
            res.add(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      }
      return res;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> deleteLocalAlert(String alertId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_localAlertsKey) ?? <String>[];
      list.removeWhere((String item) {
        try {
          final dynamic decoded = jsonDecode(item);
          return decoded is Map && decoded['id']?.toString() == alertId;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_localAlertsKey, list);
    } catch (_) {}
  }

  static Future<void> clearLocalAlerts() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localAlertsKey);
    } catch (_) {}
  }

  Map<String, dynamic> _dataOf(RemoteMessage m) => <String, dynamic>{
        ...m.data,
        if (m.notification?.title != null) 'title': m.notification!.title,
        if (m.notification?.body != null) 'message': m.notification!.body,
      };

  Future<void> subscribeToOrg(String orgId) async {
    if (orgId.isEmpty) return;
    try {
      await _fcm.subscribeToTopic('org_$orgId');
    } catch (e) {
      debugPrint('[push] subscribe failed: $e');
    }
  }

  Future<void> unsubscribeFromOrg(String orgId) async {
    if (orgId.isEmpty) return;
    try {
      await _fcm.unsubscribeFromTopic('org_$orgId');
    } catch (_) {}
  }

  /// On logout we must delete the token, otherwise the next user on this
  /// device keeps receiving the previous customer's fleet alerts.
  Future<void> deleteToken() async {
    try {
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('[push] delete token failed: $e');
    }
  }

  void dispose() {
    _fgSub?.cancel();
    _openedSub?.cancel();
    _tokenSub?.cancel();
  }
}
