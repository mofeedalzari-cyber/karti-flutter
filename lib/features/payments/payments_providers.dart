// نفس منطق src/routes/app.payments.tsx بالكامل — RPCs: settle_agent_debt,
// admin_update_request_payment, admin_delete_request_payment.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

final paymentsAgentProvider = StateProvider<String?>((ref) => null);

/// شبكة المدير الحالي (نفس pay-network بالنسخة الأصلية)
final myOwnedNetworkProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return null;
  return supabase.from('networks').select('id, name, currency').eq('owner_id', uid).maybeSingle();
});

final paymentsAgentsListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final network = await ref.watch(myOwnedNetworkProvider.future);
  if (network == null) return [];
  final rows = await supabase.from('profiles').select('id, username, full_name, phone').eq('network_id', network['id'] as String).order('full_name');
  return (rows as List).cast<Map<String, dynamic>>();
});

class AgentDebt {
  final num total;
  final num paid;
  num get remaining => (total - paid).clamp(0, double.infinity);
  const AgentDebt({required this.total, required this.paid});
}

final agentDebtProvider = FutureProvider<AgentDebt?>((ref) async {
  final agentId = ref.watch(paymentsAgentProvider);
  final network = await ref.watch(myOwnedNetworkProvider.future);
  if (agentId == null || network == null) return null;
  final rows = await supabase
      .from('card_requests')
      .select('total_value, paid_amount')
      .eq('agent_id', agentId)
      .eq('network_id', network['id'] as String)
      .eq('status', 'APPROVED');
  num total = 0, paid = 0;
  for (final r in (rows as List)) {
    total += (r['total_value'] ?? 0) as num;
    paid += (r['paid_amount'] ?? 0) as num;
  }
  return AgentDebt(total: total, paid: paid);
});

class PaymentHistoryRow {
  final String id;
  final String requestId;
  final num amount;
  final String? note;
  final String createdAt;
  final String? recordedByUsername;
  final String packageName;

  PaymentHistoryRow({
    required this.id,
    required this.requestId,
    required this.amount,
    this.note,
    required this.createdAt,
    this.recordedByUsername,
    required this.packageName,
  });
}

final paymentHistoryProvider = FutureProvider<List<PaymentHistoryRow>>((ref) async {
  final agentId = ref.watch(paymentsAgentProvider);
  final network = await ref.watch(myOwnedNetworkProvider.future);
  if (agentId == null || network == null) return [];

  final reqs = await supabase.from('card_requests').select('id, package_name').eq('agent_id', agentId).eq('network_id', network['id'] as String);
  final ids = (reqs as List).map((r) => r['id'] as String).toList();
  if (ids.isEmpty) return [];
  final nameMap = {for (final r in reqs) r['id'] as String: r['package_name'] as String? ?? ''};

  final rows = await supabase
      .from('request_payments')
      .select('id, request_id, amount, note, created_at, recorded_by_username')
      .inFilter('request_id', ids)
      .order('created_at', ascending: false);

  return (rows as List)
      .map((p) => PaymentHistoryRow(
            id: p['id'] as String,
            requestId: p['request_id'] as String,
            amount: (p['amount'] ?? 0) as num,
            note: p['note'] as String?,
            createdAt: p['created_at'] as String? ?? '',
            recordedByUsername: p['recorded_by_username'] as String?,
            packageName: nameMap[p['request_id']] ?? '',
          ))
      .toList();
});

class SettleResult {
  final num applied;
  final num remainingDebt;
  final int paymentsCount;
  const SettleResult({required this.applied, required this.remainingDebt, required this.paymentsCount});
}

const _settleErrorMessages = {
  'INVALID_AMOUNT': 'أدخل مبلغاً صحيحاً',
  'AGENT_NOT_IN_NETWORK': 'المندوب ليس ضمن شبكتك',
  'FORBIDDEN': 'غير مسموح',
};

Future<SettleResult> settleAgentDebt({required String agentId, required num amount, String? note}) async {
  try {
    final data = await supabase.rpc('settle_agent_debt', params: {'_agent_id': agentId, '_amount': amount, '_note': note});
    final row = (data is List) ? data.first as Map<String, dynamic> : data as Map<String, dynamic>;
    return SettleResult(
      applied: (row['applied'] ?? 0) as num,
      remainingDebt: (row['remaining_debt'] ?? 0) as num,
      paymentsCount: (row['payments_count'] ?? 0) as int,
    );
  } on PostgrestException catch (e) {
    final key = _settleErrorMessages.keys.firstWhere((k) => e.message.contains(k), orElse: () => '');
    throw Exception(_settleErrorMessages[key] ?? e.message);
  }
}

const _editErrorMessages = {
  'INVALID_AMOUNT': 'أدخل مبلغاً صحيحاً',
  'EXCEEDS_TOTAL': 'المبلغ يتجاوز إجمالي المستحق',
  'FORBIDDEN': 'غير مسموح',
  'NOT_FOUND': 'العملية غير موجودة',
};

Future<void> editPayment({required String paymentId, required num amount, String? note}) async {
  try {
    await supabase.rpc('admin_update_request_payment', params: {'_payment_id': paymentId, '_amount': amount, '_note': note});
  } on PostgrestException catch (e) {
    final key = _editErrorMessages.keys.firstWhere((k) => e.message.contains(k), orElse: () => '');
    throw Exception(_editErrorMessages[key] ?? e.message);
  }
}

Future<void> deletePayment(String paymentId) async {
  await supabase.rpc('admin_delete_request_payment', params: {'_payment_id': paymentId});
}
