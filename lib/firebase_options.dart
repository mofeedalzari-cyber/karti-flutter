// إعدادات Firebase — نفس مشروع kary-95ae6-a5e60 المستخدم بالنسخة الحالية
// (React/Capacitor) بالضبط، بنفس معرّف الحزمة com.mofeed.karti.
// القيم مأخوذة من google-services.json الذي أرسلته سابقاً.
//
// ⚠️ لو أضفت تطبيق Flutter منفصل بفايربيز لاحقاً (بدل إعادة استخدام تطبيق
// الأندرويد الحالي)، ستحتاج تشغّل `flutterfire configure` وتستبدل هذا الملف
// بالناتج — لكن بما إن معرّف الحزمة نفسه، الأصل نعيد استخدام نفس التطبيق.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBDHD_rXKgeFxKuB4QqHdlTQ-7j5PsacnE',
    appId: '1:1006630894710:android:46d12107245aedb6697357',
    messagingSenderId: '1006630894710',
    projectId: 'kary-95ae6-a5e60',
    storageBucket: 'kary-95ae6-a5e60.firebasestorage.app',
  );
}
