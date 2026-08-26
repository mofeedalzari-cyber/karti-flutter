// نفس منطق src/routes/app.agents.tsx (القائمة الأساسية) — بدون أي تغيير على
// RPC: set_agent_active, set_agent_network.
//
// ⚠️ مؤجَّل بنفس المرحلة: التفاصيل الإحصائية الغنية لكل مندوب (تفصيل شهري،
// توزيع حسب الباقة...) بالنسخة الأصلية — هذي النسخة تعرض ملخصاً أساسياً بس.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class AgentModel {
  final String id;
  final String username;
  final String? fullName;
  final String? phone;
  final bool isActive;
  final String? networkId;
  final String createdAt;
  final int salesCount;
  final num salesTotal;

  AgentModel({
    required this.id,
    required this.username,
    this.fullName,
    this.phone,
    required this.isActive,
    this.networkId,
    required this.createdAt,
    this.salesCount = 0,
    this.salesTotal = 0,
  });

  String get displayName => fullName ?? phone ?? username;
}

final agentsSearchProvider = StateProvider<String>((ref) => '');

final agentsListProvider = FutureProvider<List<AgentModel>>((ref) async {
  final roles = await supabase.from('user_roles').select('user_id').eq('role', 'agent');
  final ids = (roles as List).map((r) => r['user_id'] as String).toList();
  if (ids.isEmpty) return [];

  final profs = await supabase
      .from('profiles')
      .select('id, username, full_name, phone, is_active, created_at, network_id')
      .inFilter('id', ids)
      .order('created_at', ascending: false);

  final salesData = await supabase.from('sales').select('agent_id, price');
  final Map<String, Map<String, num>> salesMap = {};
  for (final s in (salesData as List)) {
    final agentId = s['agent_id'] as String?;
    if (agentId == null) continue;
    final cur = salesMap.putIfAbsent(agentId, () => {'count': 0, 'total': 0});
    cur['count'] = cur['count']! + 1;
    cur['total'] = cur['total']! + ((s['price'] ?? 0) as num);
  }

  return (profs as List).map((p) {
    final id = p['id'] as String;
    final sales = salesMap[id];
    return AgentModel(
      id: id,
      username: p['username'] as String,
      fullName: p['full_name'] as String?,
      phone: p['phone'] as String?,
      isActive: (p['is_active'] as bool?) ?? true,
      networkId: p['network_id'] as String?,
      createdAt: p['created_at'] as String? ?? '',
      salesCount: (sales?['count'] ?? 0).toInt(),
      salesTotal: sales?['total'] ?? 0,
    );
  }).toList();
});

Future<void> setAgentActive(String id, bool active) async {
  await supabase.rpc('set_agent_active', params: {'_agent_id': id, '_active': active});
}

Future<void> setAgentNetwork(String id, String? networkId) async {
  await supabase.rpc('set_agent_network', params: {'_agent_id': id, '_network_id': networkId});
}
