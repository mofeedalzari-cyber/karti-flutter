// إعدادات المشروع — انسخ نفس القيم الموجودة بملف .env بالنسخة الحالية (React):
// - supabaseUrl        ← VITE_SUPABASE_URL
// - supabaseAnonKey     ← VITE_SUPABASE_PUBLISHABLE_KEY
//
// هذا المفتاح "publishable/anon" مخصص للاستخدام بتطبيقات العميل أصلاً (نفس
// النسخة الويب تضمّنه بحزمة JS العلنية)، وكل الحماية الفعلية تصير عبر سياسات
// RLS بقاعدة البيانات — نفس القاعدة والسياسات الحالية بدون أي تعديل.
class AppConfig {
  static const supabaseUrl = "https://tbzuirbxsanojralqlvv.supabase.co";
  static const supabaseAnonKey = "ضع_قيمة_VITE_SUPABASE_PUBLISHABLE_KEY_هنا";

  // نفس رابط سيرفر Render الحالي — تُستخدم مؤقتاً لاستدعاء دوال الإشعارات
  // وربط الميكروتك (خطوة 2 من الخطة، راجع الرسالة المرفقة).
  static const apiBaseUrl = "https://arabic-layout-project-g2h5.onrender.com";
}
