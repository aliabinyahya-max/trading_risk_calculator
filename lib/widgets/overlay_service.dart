import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// خدمة النافذة العائمة (Floating Bubble) - المرحلة الثانية من المشروع.
///
/// ملاحظة مهمة: هذه الميزة تعمل على Android فقط، وتحتاج:
/// 1. إذن "Display over other apps" (SYSTEM_ALERT_WINDOW) يوافق عليه
///    المستخدم يدوياً من إعدادات النظام (لا يمكن منحه برمجياً بالكامل).
/// 2. اختباراً على جهاز حقيقي أو محاكي Android - لا تعمل هذه الميزة
///    على iOS إطلاقاً بسبب قيود Apple على النوافذ العائمة.
/// 3. تعديل AndroidManifest.xml لإضافة الصلاحية (راجع ملف android_setup.md).
class OverlayService {
  static Future<bool> requestPermission() async {
    final status = await FlutterOverlayWindow.isPermissionGranted();
    if (status) return true;
    return await FlutterOverlayWindow.requestPermission() ?? false;
  }

  static Future<void> showBubble() async {
    final granted = await requestPermission();
    if (!granted) return;

    await FlutterOverlayWindow.showOverlay(
      height: 400,
      width: 300,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.auto,
    );
  }

  static Future<void> closeBubble() async {
    await FlutterOverlayWindow.closeOverlay();
  }
}

/// هذا هو الودجت الذي يُعرض داخل النافذة العائمة نفسها (منفصل عن التطبيق
/// الرئيسي - Flutter overlay windows تعمل كـ isolate/entry point مستقل).
/// يجب استدعاؤه من `overlayMain()` كما هو موضح في android_setup.md
class MiniRiskCalculatorBubble extends StatelessWidget {
  const MiniRiskCalculatorBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.indigo.shade900,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: Text(
              'حاسبة سريعة\n(نسخة مصغرة)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
