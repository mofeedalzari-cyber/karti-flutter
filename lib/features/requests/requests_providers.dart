// نفس منطق src/routes/app.requests.tsx بالضبط — جدول card_requests، وRPCs:
// approve_card_request, reject_card_request, record_request_payment.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class CardRequest {
  final String id;
  final String status; // PENDING / APPROVED / REJECTED
  final String agentId;
  final String agentUsername;
  final String? networkName;
  final String? packageName;
  final int quantity;
  final int? approvedQuantity;
  final num totalValue;
  final num paidAmount;
  final String paymentMethod; // CASH / CREDIT
  final String? notes;
  final String? rejectReason;
  final String createdAt;

  CardRequest({
    required this.id,
    required this.status,
    required this.agentId,
    required this.agentUsername,
    this.networkName,
    this.packageName,
    required this.quantity,
    this.approvedQuantity,
    required this.totalValue,
    required this.paidAmount,
    required this.paymentMethod,
    this.notes,
    this.rejectReason,
    required this.createdAt,
  });

  num get remaining => (totalValue - paidAmount).clamp(0, double.infinity);
  int get displayQuantity => approvedQuantity ?? quantity;

  factory CardRequest.fromMap(Map<String, dynamic> m) => CardRequest(
        id: m['id'] as String,
        status: m['status'] as String,
        agentId: m['agent_id'] as String,
        agentUsername: m['agent_username'] as String? ?? '',
        networkName: m['network_name'] as String?,
        packageName: m['package_name'] as String?,
        quantity: (m['quantity'] ?? 0) as int,
        approvedQuantity: m['approved_quantity'] as int?,
        totalValue: (m['total_value'] ?? 0) as num,
        paidAmount: (m['paid_amount'] ?? 0) as num,
        paymentMethod: m['payment_method'] as String? ?? 'CREDIT',
        notes: m['notes'] as String?,
        rejectReason: m['reject_reason'] as String?,
        createdAt: m['created_at'] as String? ?? '',
      );
}

final requestsTabProvider = StateProvider<String>((ref) => 'PENDING');

final cardRequestsProvider = FutureProvider<List<CardRequest>>((ref) async {
  final status = ref.watch(requestsTabProvider);
  final rows = await supabase.from('card_requests').select('*').eq('status', status).order('created_at', ascending: false);
  return (rows as List).map((r) => CardRequest.fromMap(r as Map<String, dynamic>)).toList();
});

class ApproveResult {
  final int approved;
  final int remaining;
  const ApproveResult({required this.approved, required this.remaining});
}

Future<ApproveResult> approveCardRequest(String id) async {
  final data = await supabase.rpc('approve_card_request', params: {'_request_id': id});
  final row = (data is List) ? data.first as Map<String, dynamic> : data as Map<String, dynamic>;
  return ApproveResult(
    approved: (row['approved'] ?? 0) as int,
    remaining: (row['remaining'] ?? 0) as int,
  );
}

Future<void> rejectCardRequest(String id, String reason) async {
  await supabase.rpc('reject_card_request', params: {'_request_id': id, '_reason': reason});
}

class PaymentResult {
  final bool success;
  final String message;
  const PaymentResult({required this.success, required this.message});
}

Future<PaymentResult> recordRequestPayment(String id, num amount) async {
  try {
    final data = await supabase.rpc('record_request_payment', params: {'_request_id': id, '_amount': amount});
    final row = (data is List) ? data.first as Map<String, dynamic> : data as Map<String, dynamic>;
    final remaining = (row['remaining'] ?? 0) as num;
    return PaymentResult(success: true, message: 'تم تسجيل الدفعة — المتبقي ${remaining.toStringAsFixed(0)}');
  } on PostgrestException catch (e) {
    final msg = e.message.contains('EXCEEDS_TOTAL')
        ? 'المبلغ يتجاوز المتبقي'
        : e.message.contains('INVALID_AMOUNT')
            ? 'أدخل مبلغاً صحيحاً'
            : e.message.contains('NOT_APPROVED')
                ? 'الطلب غير معتمد'
                : e.message;
    return PaymentResult(success: false, message: msg);
  }
}

Future<void> deleteCardRequests(List<String> ids) async {
  await supabase.from('card_requests').delete().inFilter('id', ids);
}
