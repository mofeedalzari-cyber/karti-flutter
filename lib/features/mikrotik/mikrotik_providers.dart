// إدارة أجهزة الميكروتك — جدول public.mikrotiks (نفس الجدول المستخدم
// بالنسخة الويب، بدون أي تعديل على قاعدة البيانات). الاتصال الفعلي يصير من
// الجوال مباشرة عبر RouterOSApi (بروتوكول API الثنائي، راجع routeros_api.dart)
// — لا يعتمد على أي سيرفر وسيط.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import '../../services/routeros_api.dart';

class MikrotikDevice {
  final String id;
  final String networkId;
  final String name;
  final String host;
  final String username;
  final int port;
  final bool useSsl; // يقابل عمود use_https بالجدول (نُعيد استخدامه لدلالة api-ssl)
  final String? notes;

  MikrotikDevice({
    required this.id,
    required this.networkId,
    required this.name,
    required this.host,
    required this.username,
    required this.port,
    required this.useSsl,
    this.notes,
  });

  factory MikrotikDevice.fromMap(Map<String, dynamic> m) => MikrotikDevice(
        id: m['id'] as String,
        networkId: m['network_id'] as String,
        name: m['name'] as String,
        host: m['host'] as String,
        username: m['username'] as String,
        port: (m['port'] ?? 8728) as int,
        useSsl: (m['use_https'] as bool?) ?? false,
        notes: m['notes'] as String?,
      );
}

final mikrotiksListProvider = FutureProvider<List<MikrotikDevice>>((ref) async {
  final rows = await supabase.from('mikrotiks').select('id, network_id, name, host, username, port, use_https, notes').order('created_at', ascending: false);
  return (rows as List).map((r) => MikrotikDevice.fromMap(r as Map<String, dynamic>)).toList();
});

/// كلمة المرور تُقرأ فقط عند الحاجة الفعلية للاتصال (لا تُخزَّن بحالة القائمة).
Future<String?> fetchMikrotikPassword(String id) async {
  final row = await supabase.from('mikrotiks').select('password').eq('id', id).maybeSingle();
  return row?['password'] as String?;
}

Future<void> saveMikrotik({
  required String networkId,
  required String name,
  required String host,
  required String username,
  String? password, // فارغة عند التعديل = إبقاء القديمة
  required int port,
  required bool useSsl,
  String? notes,
  String? editingId,
}) async {
  final payload = <String, dynamic>{
    'network_id': networkId,
    'name': name.trim(),
    'host': host.trim(),
    'username': username.trim(),
    'port': port,
    'use_https': useSsl,
    'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
  };
  if (password != null && password.isNotEmpty) payload['password'] = password;

  if (editingId != null) {
    await supabase.from('mikrotiks').update(payload).eq('id', editingId);
  } else {
    payload['password'] = password ?? '';
    await supabase.from('mikrotiks').insert(payload);
  }
}

Future<void> deleteMikrotik(String id) async {
  await supabase.from('mikrotiks').delete().eq('id', id);
}

/// يفتح اتصالاً، ينفّذ العملية، ثم يغلقه دائماً — نمط موحّد لكل عمليات
/// الميكروتك بهذا الملف.
Future<T> withMikrotik<T>(MikrotikDevice device, Future<T> Function(RouterOSApi api) fn) async {
  final password = await fetchMikrotikPassword(device.id);
  final api = RouterOSApi();
  try {
    await api.connect(
      host: device.host,
      port: device.port,
      username: device.username,
      password: password ?? '',
      useTls: device.useSsl,
    );
    return await fn(api);
  } finally {
    api.close();
  }
}

Future<Map<String, String>> testMikrotikConnection({
  required String host,
  required int port,
  required String username,
  required String password,
  required bool useSsl,
}) async {
  final api = RouterOSApi();
  try {
    await api.connect(host: host, port: port, username: username, password: password, useTls: useSsl);
    final identity = await api.talk('/system/identity/print');
    return {'identity': identity.isNotEmpty ? (identity.first['name'] ?? '') : ''};
  } finally {
    api.close();
  }
}
