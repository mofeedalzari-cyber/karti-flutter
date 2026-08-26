// نفس منطق src/lib/push-notifications.ts بالضبط — نفس دالة RPC
// register_device_token، نفس معرّف القناة karti_requests وخصائصها.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../firebase_options.dart';
import 'supabase_service.dart';

bool _started = false;
final _localNotifications = FlutterLocalNotificationsPlugin();

const _channel = AndroidNotificationChannel(
  'karti_requests',
  'طلبات وإشعارات كرتي',
  description: 'إشعارات طلبات سحب الكروت والموافقات',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// يُستدعى من خلفية التطبيق (background) عند وصول إشعار — يجب أن تكون دالة
/// من المستوى الأعلى (top-level) حسب متطلبات Firebase.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _saveToken(String token) async {
  try {
    await supabase.rpc('register_device_token', params: {'_token': token, '_platform': 'android'});
  } catch (_) {
    /* تجاهل */
  }
}

Future<void> initPushNotifications(GoRouter router) async {
  if (_started) return;
  _started = true;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    var settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      settings = await messaging.requestPermission();
    }
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    // قناة إشعارات عالية الأهمية (نفس karti_requests بالضبط)
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (response) {
        final path = response.payload;
        if (path != null && path.isNotEmpty) router.push(path);
      },
    );

    // عرض إشعار محلي عندما يوصل إشعار والتطبيق مفتوح بالمقدمة (foreground)
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      final path = message.data['path'] as String?;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(_channel.id, _channel.name, channelDescription: _channel.description, importance: Importance.max, priority: Priority.high),
        ),
        payload: path,
      );
    });

    // فتح المسار المناسب عند الضغط على الإشعار (والتطبيق بالخلفية)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final path = message.data['path'] as String?;
      if (path != null && path.isNotEmpty) router.push(path);
    });

    final token = await messaging.getToken();
    if (token != null) await _saveToken(token);

    messaging.onTokenRefresh.listen(_saveToken);

    // إعادة تسجيل الرمز عند تسجيل الدخول بحساب آخر
    supabase.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn) {
        final t = await messaging.getToken();
        if (t != null) await _saveToken(t);
      }
    });
  } catch (_) {
    /* Firebase غير متاح (مثلاً أثناء التطوير بدون إعداد كامل) — تجاهل */
  }
}
