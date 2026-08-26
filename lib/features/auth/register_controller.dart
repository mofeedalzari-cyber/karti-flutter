// نفس منطق src/routes/register-agent.tsx و register-network.tsx بالضبط —
// نفس آلية supabase.auth.signUp() بالبيانات الوصفية (metadata) اللي تُشغّل
// trigger بقاعدة البيانات لإنشاء الملف الشخصي وطلب الانضمام تلقائياً.
import '../../services/supabase_service.dart';
import '../auth/auth_controller.dart'; // sanitizeDigits, usernameToEmail

final passwordMinLength = 6;

/// null = نجاح، غير ذلك = رسالة الخطأ
Future<String?> registerAccount({
  required String fullName,
  required String phone,
  required String networkName,
  required String password,
  required String password2,
  required String accountType, // "agent" أو "network"
}) async {
  if (fullName.trim().isEmpty) return 'أدخل الاسم الرباعي';
  final digits = sanitizeDigits(phone);
  if (digits.length < 9) return 'رقم جوال غير صحيح';
  if (networkName.trim().isEmpty) {
    return accountType == 'agent' ? 'اختر الشبكة التي تتبع لها' : 'أدخل اسم الشبكة';
  }
  if (password.length < passwordMinLength) return 'كلمة مرور قصيرة جداً';
  if (password != password2) return 'كلمة المرور غير متطابقة';

  final username = ('u$digits').substring(0, ('u$digits').length > 30 ? 30 : ('u$digits').length);

  try {
    await supabase.auth.signUp(
      email: usernameToEmail(username),
      password: password,
      data: {
        'username': username,
        'full_name': fullName.trim(),
        'phone': digits,
        'account_type': accountType,
        'network_name': networkName.trim(),
      },
    );
  } on AuthException catch (e) {
    if (e.message.toLowerCase().contains('registered')) return 'رقم الجوال مستخدم من قبل';
    return e.message;
  }

  // TODO(المرحلة 8): استدعاء notifyNewJoinRequest عبر Render/Edge Function
  return null;
}

Future<List<Map<String, dynamic>>> listActiveNetworks() async {
  final data = await supabase.rpc('list_active_networks');
  return (data as List).cast<Map<String, dynamic>>();
}
