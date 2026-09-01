# إعداد ميزة "النافذة العائمة" على Android (Phase 2)

هذه الخطوات مطلوبة **فقط** إذا أردت تفعيل ميزة الفقاعة العائمة فوق تطبيقات
OKX / TradingView. التطبيق الأساسي (الحاسبة + السجل المحلي) يعمل بدونها تماماً.

## 1) إضافة الصلاحية في AndroidManifest.xml

افتح `android/app/src/main/AndroidManifest.xml` وأضف داخل `<manifest>`:

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```

## 2) تعريف نقطة دخول منفصلة للنافذة العائمة

نوافذ Flutter العائمة تعمل كـ entry point مستقل عن `main()`. أضف في
`lib/main.dart` (أو ملف منفصل يتم استيراده):

```dart
@pragma("vm:entry-point")
void overlayMain() {
  runApp(const MiniRiskCalculatorBubble());
}
```

## 3) تشغيل وإيقاف الفقاعة من داخل التطبيق

استخدم `OverlayService.showBubble()` و `OverlayService.closeBubble()`
الموجودة في `lib/widgets/overlay_service.dart` - مثلاً من زر في الشاشة
الرئيسية.

## 4) قيود يجب معرفتها

- **Android فقط** - لا تعمل هذه الميزة على iOS إطلاقاً.
- المستخدم يجب أن يوافق يدوياً على إذن "Display over other apps" من
  إعدادات النظام في المرة الأولى (نظام Android يفرض ذلك لأسباب أمنية،
  ولا يمكن لأي تطبيق تجاوزه برمجياً).
- بعض الشركات المصنعة (Xiaomi, Huawei, Oppo) تخفي هذا الإذن في قوائم
  إعدادات إضافية خاصة بها ("Autostart", "Other permissions") - يفضل
  توجيه المستخدم بشاشة مساعدة عند أول تشغيل.

## 5) البناء والتشغيل

```bash
flutter pub get
flutter run
```

لبناء نسخة APK جاهزة للتوزيع:

```bash
flutter build apk --release
```
