// نفس منطق src/lib/auth-context.tsx (جلب profiles + user_roles) — يُستخدم
// من كل صفحات المرحلة 2 وما بعدها بدل تكرار نفس الاستعلام بكل صفحة.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import 'auth_controller.dart';

enum Role { admin, agent, superadmin, user }

Role? roleFromString(String? s) {
  switch (s) {
    case 'admin':
      return Role.admin;
    case 'agent':
      return Role.agent;
    case 'superadmin':
      return Role.superadmin;
    case 'user':
      return Role.user;
    default:
      return null;
  }
}

class Profile {
  final String id;
  final String username;
  final String? fullName;
  final String? phone;
  final bool isActive;
  final String? networkId;
  final Role? role;
  final bool isSuperadmin;

  /// صلاحيات المدير أو أعلى (سوبر أدمن يشمل كل صلاحيات المدير) — استخدمها
  /// دائماً لفحوصات الصلاحيات بدل مقارنة `role == Role.admin` وحدها، لأن
  /// دور السوبر أدمن مُخزَّن كقيمة مستقلة (`Role.superadmin`) وليس `Role.admin`.
  bool get isAdminOrAbove => role == Role.admin || isSuperadmin;

  Profile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.phone,
    required this.isActive,
    required this.networkId,
    required this.role,
    required this.isSuperadmin,
  });
}

/// يُعاد جلبه تلقائياً كل ما تغيّرت حالة تسجيل الدخول.
final profileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateChangesProvider);
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return null;

  final profileRow = await supabase
      .from('profiles')
      .select('id, username, full_name, phone, is_active, network_id')
      .eq('id', uid)
      .maybeSingle();
  if (profileRow == null) return null;

  final rolesRows = await supabase.from('user_roles').select('role').eq('user_id', uid);
  final roleNames = (rolesRows as List).map((r) => r['role'] as String).toSet();
  final isSuperadmin = roleNames.contains('superadmin');
  final primaryRole = isSuperadmin
      ? Role.superadmin
      : roleNames.contains('admin')
          ? Role.admin
          : roleNames.contains('agent')
              ? Role.agent
              : Role.user;

  return Profile(
    id: profileRow['id'] as String,
    username: profileRow['username'] as String,
    fullName: profileRow['full_name'] as String?,
    phone: profileRow['phone'] as String?,
    isActive: (profileRow['is_active'] as bool?) ?? true,
    networkId: profileRow['network_id'] as String?,
    role: primaryRole,
    isSuperadmin: isSuperadmin,
  );
});
