// نفس منطق src/routes/app.agent-accounts.tsx بالكامل — جداول cards/sales/
// card_requests، وRPC: reconcile_agent_debts. بدون أي تغيير على قاعدة
// البيانات.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

final aaNetworkFilterProvider = StateProvider<String>((ref) => 'all'); // "all" أو معرّف شبكة
final aaAgentProvider = StateProvider<String?>((ref) => null);

final aaAgentsListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final roles = await supabase.from('user_roles').select('user_id').eq('role', 'agent');
  final ids = (roles as List).map((r) => r['user_id'] as String).toList();
  if (ids.isEmpty) return [];
  final rows = await supabase.from('profiles').select('id, username, full_name, phone').inFilter('id', ids).order('full_name');
  return (rows as List).cast<Map<String, dynamic>>();
});

class RowAgg {
  final String key;
  final String label;
  final String? sub;
  final String? currency;
  final num? price;
  int withdrawn;
  int sold;
  num value;
  RowAgg({
    required this.key,
    required this.label,
    this.sub,
    this.currency,
    this.price,
    this.withdrawn = 0,
    this.sold = 0,
    this.value = 0,
  });
}

class PaidRow {
  final String key;
  final String label;
  final num total;
  final num paid;
  num get remaining => (total - paid).clamp(0, double.infinity);
  PaidRow({required this.key, required this.label, required this.total, required this.paid});
}

class AgentAccountData {
  final String agentLabel;
  final int withdrawn;
  final int sold;
  final num salesValue;
  final int distinctPackages;
  final int networksCount;
  final List<PaidRow> paidRows;
  final num totalPaid;
  final num totalDebt;
  final num totalRemaining;
  final List<RowAgg> byNetwork;
  final List<RowAgg> byPackage;

  AgentAccountData({
    required this.agentLabel,
    required this.withdrawn,
    required this.sold,
    required this.salesValue,
    required this.distinctPackages,
    required this.networksCount,
    required this.paidRows,
    required this.totalPaid,
    required this.totalDebt,
    required this.totalRemaining,
    required this.byNetwork,
    required this.byPackage,
  });
}

/// يجلب كل بيانات مندوب واحد ويحسب كل الجداول — مطابق تماماً لمنطق
/// AgentAccountsPageInner بالنسخة الأصلية.
final agentAccountDataProvider = FutureProvider<AgentAccountData?>((ref) async {
  final agentId = ref.watch(aaAgentProvider);
  final networkFilter = ref.watch(aaNetworkFilterProvider);
  if (agentId == null) return null;
  return fetchAgentAccountData(agentId, networkFilter);
});

/// نفس منطق agentAccountDataProvider تماماً، مستخرج كدالة مستقلة قابلة
/// لإعادة الاستخدام (تُستدعى أيضاً من myAgentStatsProvider أسفل الملف).
Future<AgentAccountData?> fetchAgentAccountData(String agentId, String networkFilter) async {
  final results = await Future.wait([
    supabase.from('networks').select('id, name, currency'),
    supabase.from('packages').select('id, name, price, network_id'),
    supabase.from('cards').select('id, status, package_id, network_id, assigned_to').eq('assigned_to', agentId),
    supabase.from('sales').select('id, package_id, package_name, network_id, network_name, price').eq('agent_id', agentId).order('sold_at', ascending: false),
    supabase.from('card_requests').select('network_id, total_value, paid_amount, status').eq('agent_id', agentId).eq('status', 'APPROVED'),
    supabase.from('profiles').select('id, username, full_name, phone').eq('id', agentId).maybeSingle(),
  ]);

  final networks = (results[0] as List).cast<Map<String, dynamic>>();
  final packages = (results[1] as List).cast<Map<String, dynamic>>();
  var cards = (results[2] as List).cast<Map<String, dynamic>>();
  var sales = (results[3] as List).cast<Map<String, dynamic>>();
  final paidRequests = (results[4] as List).cast<Map<String, dynamic>>();
  final agentProfile = results[5] as Map<String, dynamic>?;

  final netMap = {for (final n in networks) n['id'] as String: n};
  final pkgMap = {for (final p in packages) p['id'] as String: p};

  if (networkFilter != 'all') {
    cards = cards.where((c) => c['network_id'] == networkFilter).toList();
    sales = sales.where((s) => s['network_id'] == networkFilter).toList();
  }

  // تسوية المديونيات حسب الشبكة
  final Map<String, Map<String, num>> paidByNetwork = {};
  for (final r in paidRequests) {
    final nid = r['network_id'] as String;
    final cur = paidByNetwork.putIfAbsent(nid, () => {'total': 0, 'paid': 0});
    cur['total'] = cur['total']! + ((r['total_value'] ?? 0) as num);
    cur['paid'] = cur['paid']! + ((r['paid_amount'] ?? 0) as num);
  }
  final paidRows = paidByNetwork.entries
      .where((e) => networkFilter == 'all' || e.key == networkFilter)
      .map((e) => PaidRow(key: e.key, label: netMap[e.key]?['name'] as String? ?? '—', total: e.value['total']!, paid: e.value['paid']!))
      .toList();
  final totalPaid = paidRows.fold<num>(0, (s, r) => s + r.paid);
  final totalDebt = paidRows.fold<num>(0, (s, r) => s + r.total);
  final totalRemaining = (totalDebt - totalPaid).clamp(0, double.infinity);

  final withdrawn = cards.where((c) => c['status'] == 'ASSIGNED').length;
  final sold = sales.length;
  final salesValue = sales.fold<num>(0, (s, x) => s + ((x['price'] ?? 0) as num));
  final distinctPackages = {
    ...cards.map((c) => c['package_id'] as String),
    ...sales.map((s) => s['package_id'] as String),
  }.length;
  final networksCount = {
    ...cards.map((c) => c['network_id'] as String),
    ...sales.map((s) => s['network_id'] as String),
  }.length;

  // تجميع حسب الشبكة
  final Map<String, RowAgg> byNetworkMap = {};
  for (final c in cards) {
    final nid = c['network_id'] as String;
    final net = netMap[nid];
    final row = byNetworkMap.putIfAbsent(nid, () => RowAgg(key: nid, label: net?['name'] as String? ?? '—', currency: net?['currency'] as String?));
    if (c['status'] == 'ASSIGNED') row.withdrawn++;
  }
  for (final s in sales) {
    final nid = s['network_id'] as String;
    final row = byNetworkMap.putIfAbsent(nid, () => RowAgg(key: nid, label: s['network_name'] as String? ?? '—', currency: netMap[nid]?['currency'] as String?));
    row.sold++;
    row.value += (s['price'] ?? 0) as num;
  }
  final byNetwork = byNetworkMap.values.toList()..sort((a, b) => b.value.compareTo(a.value));

  // تجميع حسب الباقة
  final Map<String, RowAgg> byPackageMap = {};
  for (final c in cards) {
    final pid = c['package_id'] as String;
    final pkg = pkgMap[pid];
    final net = netMap[c['network_id'] as String];
    final row = byPackageMap.putIfAbsent(
        pid,
        () => RowAgg(
              key: pid,
              label: pkg?['name'] as String? ?? '—',
              sub: net?['name'] as String?,
              currency: net?['currency'] as String?,
              price: pkg != null ? (pkg['price'] as num) : null,
            ));
    if (c['status'] == 'ASSIGNED') row.withdrawn++;
  }
  for (final s in sales) {
    final pid = s['package_id'] as String;
    final pkg = pkgMap[pid];
    final nid = s['network_id'] as String;
    final row = byPackageMap.putIfAbsent(
        pid,
        () => RowAgg(
              key: pid,
              label: s['package_name'] as String? ?? '—',
              sub: s['network_name'] as String?,
              currency: netMap[nid]?['currency'] as String?,
              price: pkg != null ? (pkg['price'] as num) : (s['price'] as num?),
            ));
    row.sold++;
    row.value += (s['price'] ?? 0) as num;
  }
  final byPackage = byPackageMap.values.toList()..sort((a, b) => b.value.compareTo(a.value));

  final displayPhone = agentProfile?['phone'] as String? ?? agentProfile?['username'] as String? ?? '';
  final agentLabel = agentProfile != null ? '${agentProfile['full_name'] ?? displayPhone} — $displayPhone' : '';

  return AgentAccountData(
    agentLabel: agentLabel,
    withdrawn: withdrawn,
    sold: sold,
    salesValue: salesValue,
    distinctPackages: distinctPackages,
    networksCount: networksCount,
    paidRows: paidRows,
    totalPaid: totalPaid,
    totalDebt: totalDebt,
    totalRemaining: totalRemaining,
    byNetwork: byNetwork,
    byPackage: byPackage,
  );
}

class ReconcileResult {
  final int created;
  final num totalValue;
  const ReconcileResult({required this.created, required this.totalValue});
}

Future<ReconcileResult> reconcileAgentDebts(String? networkId) async {
  final data = await supabase.rpc('reconcile_agent_debts', params: {
    if (networkId != null && networkId != 'all') '_network_id': networkId,
  });
  final row = (data is List) ? data.first as Map<String, dynamic>? : data as Map<String, dynamic>?;
  return ReconcileResult(
    created: (row?['created'] as num?)?.toInt() ?? 0,
    totalValue: (row?['total_value'] ?? 0) as num,
  );
}

/// إحصائيات المندوب لنفسه (لوحته الخاصة "أهلاً..." — AgentHome بالنسخة
/// الأصلية) — يعيد استخدام fetchAgentAccountData() لكن دائماً على المستخدم
/// الحالي، بدون أي اعتماد على فلاتر لوحة الأدمن (aaAgentProvider/aaNetworkFilterProvider).
final myAgentStatsProvider = FutureProvider<AgentAccountData?>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return null;
  return fetchAgentAccountData(uid, 'all');
});
