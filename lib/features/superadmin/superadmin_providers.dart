// نفس منطق src/routes/app.superadmin.tsx (الأجزاء الجوهرية) — RPCs:
// superadmin_stats, superadmin_networks, superadmin_agents,
// superadmin_packages, superadmin_set_network_active, superadmin_delete_network.
//
// ⚠️ مؤجَّل بنفس المرحلة (تفصيل إضافي، ليس أساسياً): تفصيل NetworkDetail
// الغني (كروت شبكة معينة + رسوم بيانية)، NetworkBackupButton (سيرفر Render،
// نفس فئة المرحلة 8).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

final superadminStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final data = await supabase.rpc('superadmin_stats');
  return data as Map<String, dynamic>;
});

final superadminNetworksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase.rpc('superadmin_networks');
  return (data as List).cast<Map<String, dynamic>>();
});

final superadminAgentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase.rpc('superadmin_agents');
  return (data as List).cast<Map<String, dynamic>>();
});

final superadminPackagesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase.rpc('superadmin_packages');
  return (data as List).cast<Map<String, dynamic>>();
});

Future<void> superadminSetNetworkActive(String networkId, bool active) async {
  await supabase.rpc('superadmin_set_network_active', params: {'_network_id': networkId, '_active': active});
}

Future<void> superadminDeleteNetwork(String networkId) async {
  await supabase.rpc('superadmin_delete_network', params: {'_network_id': networkId});
}

Future<void> superadminSetAgentActive(String agentId, bool active) async {
  await supabase.rpc('set_agent_active', params: {'_agent_id': agentId, '_active': active});
}

/// نفس منطق MyNetworkPanel: إنشاء شبكة خاصة بالسوبر أدمن نفسه (لو ما عنده وحدة).
Future<void> createMyNetwork(String name) async {
  await supabase.rpc('create_my_network', params: {'_name': name.trim()});
}
