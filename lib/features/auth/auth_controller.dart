// نفس منطق تسجيل الدخول الموجود بـ src/routes/auth.tsx بالضبط — بدون أي
// تغيير بالمنطق أو بالدوال البرمجية (RPC) المستخدمة على قاعدة البيانات:
//   1) login_guard_check  — حماية من محاولات الدخول المتكررة (Brute-force)
//   2) username_from_phone — تحويل رقم الجوال لاسم المستخدم
//   3) تسجيل الدخول عبر بريد اصطناعي: "<username>@wificards.local"
//   4) التحقق من الدور (agent/admin/superadmin) بجدول user_roles
//   5) login_guard_record — تسجيل نجاح/فشل المحاولة
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

enum AccountType { agent, network }

class AuthState {
  final bool busy;
  final String? error;
  const AuthState({this.busy = false, this.error});

  AuthState copyWith({bool? busy, String? error}) =>
      AuthState(busy: busy ?? this.busy, error: error);
}

/// يحوّل اسم المستخدم لبريد اصطناعي داخلي — مطابق تماماً لـ usernameToEmail()
/// بملف src/lib/auth-context.tsx بالنسخة الحالية.
String usernameToEmail(String u) {
  final cleaned = u.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');
  return '$cleaned@wificards.local';
}

String sanitizeDigits(String value, {int maxLength = 20}) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length > maxLength ? digits.substring(0, maxLength) : digits;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState());

  /// يرجع رسالة خطأ إن فشل تسجيل الدخول، أو null عند النجاح.
  Future<String?> login({
    required String phoneOrUsername,
    required String password,
    required AccountType accountType,
  }) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final identifier = phoneOrUsername.trim();
      if (identifier.isEmpty) return 'أدخل رقم الجوال';
      if (password.length < 6) return 'كلمة المرور قصيرة جداً';

      final digits = sanitizeDigits(identifier);

      // 1) حماية من محاولات الدخول المتكررة
      if (digits.isNotEmpty) {
        final lock = await supabase.rpc('login_guard_check', params: {'_phone': digits});
        final secs = (lock is num) ? lock.toInt() : 0;
        if (secs > 0) {
          final minutes = (secs / 60).ceil();
          return 'تم إيقاف المحاولات مؤقتاً بسبب محاولات دخول خاطئة. أعد المحاولة بعد $minutes دقيقة';
        }
      }

      Future<String> fail(String message) async {
        if (digits.isNotEmpty) {
          await supabase.rpc('login_guard_record', params: {'_phone': digits, '_ok': false});
        }
        return message;
      }

      // 2) تحويل رقم الجوال لاسم المستخدم
      String? loginName;
      if (digits.isNotEmpty) {
        final data = await supabase.rpc('username_from_phone', params: {'_phone': digits});
        loginName = (data is String && data.isNotEmpty) ? data : null;
      } else if (RegExp(r'^[a-zA-Z0-9._-]{3,30}$').hasMatch(identifier)) {
        loginName = identifier;
      }

      if (loginName == null) {
        return await fail('رقم الجوال أو كلمة المرور غير صحيحة');
      }

      // 3) تسجيل الدخول الفعلي عبر Supabase Auth
      final signIn = await supabase.auth.signInWithPassword(
        email: usernameToEmail(loginName),
        password: password,
      );
      if (signIn.user == null) {
        return await fail('رقم الجوال أو كلمة المرور غير صحيحة');
      }

      // 4) التحقق من نوع الحساب (مندوب / مدير شبكة)
      final roles = await supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', signIn.user!.id);
      final roleNames = (roles as List).map((r) => r['role'] as String).toSet();
      final hasSuperadmin = roleNames.contains('superadmin');
      final allowed = hasSuperadmin
          ? true
          : accountType == AccountType.agent
              ? roleNames.contains('agent')
              : roleNames.contains('admin');

      if (!allowed) {
        await supabase.auth.signOut();
        return accountType == AccountType.agent
            ? 'هذا الحساب ليس حساب مندوب توزيع، اختر «وكيل / مدير شبكة»'
            : 'هذا الحساب ليس حساب مدير شبكة، اختر «مندوب توزيع»';
      }

      if (digits.isNotEmpty) {
        await supabase.rpc('login_guard_record', params: {'_phone': digits, '_ok': true});
      }
      return null; // نجاح
    } catch (e) {
      return 'تعذر تسجيل الدخول، تحقق من الاتصال ثم أعد المحاولة';
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(),
);

/// يبث حالة تسجيل الدخول الحالية (مسجّل / غير مسجّل) لاستخدامها بالتوجيه.
final authStateChangesProvider = StreamProvider((ref) {
  return supabase.auth.onAuthStateChange;
});
