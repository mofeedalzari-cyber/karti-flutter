// نفس تصميم src/routes/app.join-requests.tsx — تبويبات، بطاقة لكل طلب مندوب
// جديد مع اعتماد/رفض.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'join_requests_providers.dart';

class JoinRequestsScreen extends ConsumerWidget {
  const JoinRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(joinRequestsTabProvider);
    return DefaultTabController(
      length: 3,
      initialIndex: ['PENDING', 'APPROVED', 'REJECTED'].indexOf(tab),
      child: Scaffold(
        appBar: AppBar(title: const Text('طلبات انضمام المناديب')),
        body: Column(
          children: [
            TabBar(
              onTap: (i) => ref.read(joinRequestsTabProvider.notifier).state = ['PENDING', 'APPROVED', 'REJECTED'][i],
              tabs: const [Tab(text: 'قيد المراجعة'), Tab(text: 'مقبولة'), Tab(text: 'مرفوضة')],
            ),
            const Expanded(child: _JoinList()),
          ],
        ),
      ),
    );
  }
}

class _JoinList extends ConsumerWidget {
  const _JoinList();

  Future<void> _approve(BuildContext context, WidgetRef ref, JoinRequest r) async {
    try {
      await approveJoinRequest(r.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قبول المندوب وتفعيل حسابه')));
      ref.invalidate(joinRequestsProvider);
      // TODO(المرحلة 8): notifyJoinDecision عبر Render/Edge Function
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, JoinRequest r) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'سبب الرفض (اختياري)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await rejectJoinRequest(r.id, reasonCtrl.text);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض الطلب')));
      ref.invalidate(joinRequestsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(joinRequestsProvider);
    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text('لا توجد طلبات.'),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            final displayName = r.agentFullName ?? r.agentPhone ?? r.agentUsername ?? '—';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: const Icon(Icons.person_add_outlined, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            if (r.agentPhone != null)
                              Text(r.agentPhone!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), textDirection: TextDirection.ltr),
                          ],
                        ),
                      ),
                    ]),
                    if (r.rejectReason != null && r.rejectReason!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Text('سبب الرفض: ${r.rejectReason}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                      ),
                    if (r.status == 'PENDING') ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _approve(context, ref, r),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('قبول'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _reject(context, ref, r),
                            icon: const Icon(Icons.close, size: 16, color: Colors.red),
                            label: const Text('رفض', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
