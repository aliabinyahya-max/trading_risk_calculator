import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'strategy_engine.dart';

/// خدمة التنبيهات المحلية - تعمل بدون أي سيرفر خارجي، تعرض إشعار نظام
/// عادي عند اكتشاف إشارة تداول.
///
/// ملاحظة مهمة: هذه إشعارات محلية (Local Notifications) وليست Push من
/// سيرفر، لذا فهي تعمل فقط طالما التطبيق مفتوحاً (في المقدمة أو الخلفية
/// القريبة). لتشغيلها حتى مع إغلاق التطبيق بالكامل على أندرويد، يلزم
/// لاحقاً إضافة Foreground Service أو WorkManager - وهذا مقيّد أصلاً
/// بإعدادات توفير البطارية لدى بعض الشركات المصنعة (راجع android_setup.md).
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<void> showSignalNotification(String symbol, TradingSignal signal) async {
    await init();
    final isBuy = signal.direction == SignalDirection.buy;
    const androidDetails = AndroidNotificationDetails(
      'trading_signals',
      'إشارات التداول',
      channelDescription: 'تنبيهات فرص الشراء والبيع المكتشفة تلقائياً',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '${isBuy ? "📈 فرصة شراء" : "📉 فرصة بيع"} - $symbol',
      signal.reason,
      details,
    );
  }
}
