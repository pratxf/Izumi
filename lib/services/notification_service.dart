import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Stream controllers for UI layer to consume
  final _foregroundMessageController =
      StreamController<RemoteMessage>.broadcast();
  final _messageOpenedController = StreamController<RemoteMessage>.broadcast();

  /// Stream emitted when a local notification (foreground) is tapped.
  /// Payload is the JSON-encoded FCM data map.
  final _localNotificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of messages received while the app is in the foreground.
  Stream<RemoteMessage> get onForegroundMessage =>
      _foregroundMessageController.stream;

  /// Stream of notification taps that opened the app from background.
  Stream<RemoteMessage> get onMessageOpened =>
      _messageOpenedController.stream;

  /// Stream of taps on foreground local notifications.
  Stream<Map<String, dynamic>> get onLocalNotificationTap =>
      _localNotificationTapController.stream;

  bool _initialized = false;

  /// Phase 1: Lightweight APNs registration for iOS phone auth.
  /// Call this early in the constructor so Firebase Phone Auth can use
  /// silent push instead of reCAPTCHA. Does NOT request user permission.
  Future<void> registerForAPNs() async {
    try {
      await _messaging.getAPNSToken();
    } catch (_) {
      // Only relevant on iOS — safe to ignore on Android
    }
  }

  // Phase 2: Full FCM + local notifications initialization.
  // Call after auth resolves so the permission dialog doesn't block startup.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request permission (required for iOS, Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // ── Initialize flutter_local_notifications ─────────────────────────
    const androidSettings = AndroidInitializationSettings('ic_stat_izumi');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      'general',
      'General Notifications',
      description: 'Default notification channel for Izumi',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const tasksChannel = AndroidNotificationChannel(
      'tasks',
      'Task Notifications',
      description: 'Notifications for task assignments and updates',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(tasksChannel);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background message tap (app was in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  // Get FCM token
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  // Listen for token refresh
  void onTokenRefresh(void Function(String token) callback) {
    _messaging.onTokenRefresh.listen(callback);
  }

  // Store FCM token in user's Firestore document
  Future<void> saveTokenToFirestore(String userId) async {
    final token = await getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'fcmToken': token,
      });
    }
  }

  // Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  // Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }

  // Check if app was opened from a notification
  Future<RemoteMessage?> getInitialMessage() async {
    return await _messaging.getInitialMessage();
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _foregroundMessageController.add(message);
    _showLocalNotification(message);
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    _messageOpenedController.add(message);
  }

  /// Display a local notification when an FCM message arrives in the foreground.
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] as String? ?? 'general';
    final channelId = type == 'task' ? 'tasks' : 'general';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'tasks' ? 'Task Notifications' : 'General Notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_izumi',
    );
    final iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  /// Called when user taps a local notification.
  void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _localNotificationTapController.add(data);
    } catch (_) {
      // Ignore malformed payloads
    }
  }

  /// Show a local notification with custom title and body.
  Future<void> showLocal({
    required String title,
    required String body,
    String channelId = 'general',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'tasks' ? 'Task Notifications' : 'General Notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_izumi',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  /// Reset state so [initialize] will re-run on next login with a fresh token.
  void resetForLogout() {
    _initialized = false;
  }

  void dispose() {
    _foregroundMessageController.close();
    _messageOpenedController.close();
    _localNotificationTapController.close();
  }
}
