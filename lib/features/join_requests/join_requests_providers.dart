// نفس منطق src/routes/app.join-requests.tsx — جدول join_requests، وRPCs:
// approve_join_request, reject_join_request.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class JoinRequest {
  final String id;
  final String status;
  final String? agentId;
  final String? agentFullName;
  final String? agentUsername;
  final String? agentPhone;
  final String? rejectReason;
  final String requestedAt;

  JoinRequest({
    required this.id,
    required this.status,
    this.agentId,
    this.agentFullName,
    this.agentUsername,
    this.agentPhone,
    this.rejectReason,
    required this.requestedAt,
  });

  factory JoinRequest.fromMap(Map<String, dynamic> m) => JoinRequest(
        id: m['id'] as String,
        status: m['status'] as String,
        agentId: m['agent_id'] as String?,
        agentFullName: m['agent_full_name'] as String?,
        agentUsername: m['agent_username'] as String?,
        agentPhone: m['agent_phone'] as String?,
        rejectReason: m['reject_reason'] as String?,
        requestedAt: m['requested_at'] as String? ?? '',
      );
}

final joinRequestsTabProvider = StateProvider<String>((ref) => 'PENDING');

final joinRequestsProvider = FutureProvider<List<JoinRequest>>((ref) async {
  final status = ref.watch(joinRequestsTabProvider);
  final rows = await supabase.from('join_requests').select('*').eq('status', status).order('requested_at', ascending: false);
  return (rows as List).map((r) => JoinRequest.fromMap(r as Map<String, dynamic>)).toList();
});

Future<void> approveJoinRequest(String id) async {
  await supabase.rpc('approve_join_request', params: {'_request_id': id});
}

Future<void> rejectJoinRequest(String id, String reason) async {
  await supabase.rpc('reject_join_request', params: {'_request_id': id, '_reason': reason});
}
