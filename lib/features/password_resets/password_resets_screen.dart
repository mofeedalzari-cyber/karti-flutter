// نفس منطق src/components/reset-requests-panel.tsx بالكامل — RPCs:
// superadmin_reset_requests, superadmin_resolve_reset_request,
// superadmin_delete_reset_requests, superadmin_reset_password.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/supabase_service.dart';

class ResetRequest {
  final String id;
  final String phone;
  final String? matchedUsername;
  final String? matchedFullName;
  final String? matchedNetworkName;
  final String? matchedUserId;
  final String? note;
  final String status;
  final String createdAt;

  ResetRequest({
    required this.id,
    required this.phone,
    this.matchedUsername,
    this.matchedFullName,
    this.matchedNetworkName,
    this.matchedUserId,
    this.note,
    required this.status,
    required this.createdAt,
  });

  factory ResetRequest.fromMap(Map<String, dynamic> m) => ResetRequest(
        id: m['id'] as String,
        phone: m['phone'] as String? ?? '',
        matchedUsername: m['matched_username'] as String?,
        matchedFullName: m['matched_full_name'] as String?,
        matchedNetworkName: m['matched_network_name'] as String?,
        matchedUserId: m['matched_user_id'] as String?,
        note: m['note'] as String?,
        status: m['status'] as String? ?? 'PENDING',
        createdAt: m['created_at'] as String? ?? '',
      );
}

final resetRequestsProvider = FutureProvider<List<ResetRequest>>((ref) async {
  final data = await supabase.rpc('superadmin_reset_requests');
  return (data as List).map((r) => ResetRequest.fromMap(r as Map<String, dynamic>)).toList();
});

Future<void> resolveResetRequest(String id) async {
  await supabase.rpc('superadmin_resolve_reset_request', params: {'_id': id, '_status': 'RESOLVED'});
}

Future<void> deleteResetRequests(List<String> ids) async {
  await supabase.rpc('superadmin_delete_reset_requests', params: {'_ids': ids});
}

Future<void> superadminResetPassword({required String userId, required String newPassword}) async {
  await supabase.rpc('superadmin_reset_password', params: {'_target_user_id': userId, '_new_password': newPassword});
}

class PasswordResetsScreen extends ConsumerStatefulWidget {
  const PasswordResetsScreen({super.key});

  @override
  ConsumerState<PasswordResetsScreen> createState() => _PasswordResetsScreenState();
}

class _PasswordResetsScreenState extends ConsumerState<PasswordResetsScreen> {
  final Set<String> _selected = {};

  Future<void> _resetPasswordDialog(ResetRequest r) async {
    final pwdCtrl = TextEditingController();
    final pwd2Ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل كلمة المرور — ${r.matchedFullName ?? r.phone}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
          const SizedBox(height: 10),
          TextField(controller: pwd2Ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (pwdCtrl.text.length < 6) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور 6 أحرف على الأقل')));
      return;
    }
    if (pwdCtrl.text != pwd2Ctrl.text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور غير متطابقة')));
      return;
    }
    try {
      await superadminResetPassword(userId: r.matchedUserId!, newPassword: pwdCtrl.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل كلمة المرور')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الطلبات'),
        content: Text('حذف ${_selected.length} طلب استعادة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteResetRequests(_selected.toList());
    setState(() => _selected.clear());
    ref.invalidate(resetRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(resetRequestsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('استعادة كلمة المرور'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(resetRequestsProvider))],
      ),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
        data: (rows) {
          if (rows.isEmpty) return const Center(child: Text('لا توجد طلبات'));
          return Column(
            children: [
              if (_selected.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  child: Row(children: [
                    Text('${_selected.length} محدد', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton.icon(onPressed: _bulkDelete, icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), label: const Text('حذف', style: TextStyle(color: Colors.red))),
                  ]),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final selected = _selected.contains(r.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(r.id);
                                  } else {
                                    _selected.remove(r.id);
                                  }
                                }),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.matchedFullName ?? r.phone, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text(r.phone, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                                    if (r.matchedNetworkName != null) Text('الشبكة: ${r.matchedNetworkName}', style: const TextStyle(fontSize: 11)),
                                    if (r.note != null) Text('ملاحظة: ${r.note}', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (r.status == 'PENDING' ? Colors.orange : Colors.green).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(r.status == 'PENDING' ? 'قيد الانتظار' : 'تم', style: TextStyle(fontSize: 10, color: r.status == 'PENDING' ? Colors.orange : Colors.green)),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, children: [
                              if (r.matchedUserId != null)
                                OutlinedButton(onPressed: () => _resetPasswordDialog(r), child: const Text('تعديل كلمة المرور', style: TextStyle(fontSize: 11))),
                              if (r.status == 'PENDING')
                                TextButton(
                                  onPressed: () async {
                                    await resolveResetRequest(r.id);
                                    ref.invalidate(resetRequestsProvider);
                                  },
                                  child: const Text('إغلاق', style: TextStyle(fontSize: 11)),
                                ),
                              if (r.phone.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => launchUrl(Uri.parse('https://wa.me/${r.phone.replaceAll(RegExp(r'\D'), '')}')),
                                  icon: const Icon(Icons.chat_outlined, size: 14),
                                  label: const Text('واتساب', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF25D366)),
                                ),
                            ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
