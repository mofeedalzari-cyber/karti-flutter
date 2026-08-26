// نفس تصميم src/routes/app.requests.tsx — تبويبات (قيد المراجعة/مقبولة/
// مرفوضة)، بطاقة لكل طلب فيها كل التفاصيل، أزرار اعتماد/رفض/تسجيل دفعة
// للمدير، تحديد جماعي وحذف.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';
import 'requests_providers.dart';

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final tab = ref.watch(requestsTabProvider);
    final isAdmin = profileAsync.value?.role == Role.admin;

    return DefaultTabController(
      length: 3,
      initialIndex: ['PENDING', 'APPROVED', 'REJECTED'].indexOf(tab),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('طلبات سحب الكروت',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(isAdmin ? 'طلبات المناديب بانتظار الموافقة' : 'طلباتك للكروت',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          const SizedBox(height: 8),
          TabBar(
            onTap: (i) => ref.read(requestsTabProvider.notifier).state = ['PENDING', 'APPROVED', 'REJECTED'][i],
            tabs: const [
              Tab(text: 'قيد المراجعة'),
              Tab(text: 'مقبولة'),
              Tab(text: 'مرفوضة'),
            ],
          ),
          Expanded(child: _RequestList(isAdmin: isAdmin)),
        ],
      ),
    );
  }
}

class _RequestList extends ConsumerStatefulWidget {
  final bool isAdmin;
  const _RequestList({required this.isAdmin});

  @override
  ConsumerState<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends ConsumerState<_RequestList> {
  final Set<String> _selected = {};

  Future<void> _approve(CardRequest r) async {
    try {
      final res = await approveCardRequest(r.id);
      if (!mounted) return;
      final msg = 'تم الاعتماد — ${res.approved} كرت${res.remaining > 0 ? ' (${res.remaining} غير متوفر)' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      ref.invalidate(cardRequestsProvider);
      // TODO(المرحلة 8): استدعاء notifyRequestDecision عبر Render/Edge Function
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showRejectDialog(CardRequest r) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طلب ${r.agentUsername} — ${r.packageName} (${r.quantity})', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'سبب الرفض (اختياري)'),
            ),
          ],
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
      await rejectCardRequest(r.id, reasonCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الرفض')));
      ref.invalidate(cardRequestsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showPayDialog(CardRequest r) async {
    final amountCtrl = TextEditingController(text: r.remaining.toStringAsFixed(0));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل دفعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المندوب: ${r.agentUsername}', style: const TextStyle(fontSize: 13)),
            Text('الطلب: ${r.packageName}', style: const TextStyle(fontSize: 13)),
            Text('المتبقي: ${fmtMoney(r.remaining)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = num.tryParse(amountCtrl.text) ?? 0;
    final result = await recordRequestPayment(r.id, amount);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) ref.invalidate(cardRequestsProvider);
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الطلبات'),
        content: Text('حذف ${_selected.length} طلب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deleteCardRequests(_selected.toList());
      setState(() => _selected.clear());
      ref.invalidate(cardRequestsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(cardRequestsProvider);

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
        return Column(
          children: [
            if (widget.isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: rows.isNotEmpty && rows.every((r) => _selected.contains(r.id)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.addAll(rows.map((r) => r.id));
                        } else {
                          _selected.clear();
                        }
                      }),
                    ),
                    const Text('تحديد الكل', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      TextButton.icon(
                        onPressed: _bulkDelete,
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: Text('حذف المحدد (${_selected.length})', style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: rows.length,
                itemBuilder: (context, i) => _RequestCard(
                  r: rows[i],
                  isAdmin: widget.isAdmin,
                  selected: _selected.contains(rows[i].id),
                  onToggleSelect: () => setState(() {
                    if (_selected.contains(rows[i].id)) {
                      _selected.remove(rows[i].id);
                    } else {
                      _selected.add(rows[i].id);
                    }
                  }),
                  onApprove: () => _approve(rows[i]),
                  onReject: () => _showRejectDialog(rows[i]),
                  onPay: () => _showPayDialog(rows[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  final CardRequest r;
  final bool isAdmin;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onPay;

  const _RequestCard({
    required this.r,
    required this.isAdmin,
    required this.selected,
    required this.onToggleSelect,
    required this.onApprove,
    required this.onReject,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final isCash = r.paymentMethod == 'CASH';
    final fullyPaid = r.status == 'APPROVED' && r.remaining == 0 && r.totalValue > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isAdmin) Checkbox(value: selected, onChanged: (_) => onToggleSelect()),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: 'المندوب: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        TextSpan(text: r.agentUsername, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ])),
                      if (r.networkName != null) Text('الشبكة: ${r.networkName}', style: const TextStyle(fontSize: 12)),
                      if (r.packageName != null) Text('الفئة: ${r.packageName}', style: const TextStyle(fontSize: 12)),
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: 'عدد الكروت: ', style: TextStyle(fontSize: 12)),
                        TextSpan(text: '${r.displayQuantity}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ])),
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: 'القيمة الإجمالية: ', style: TextStyle(fontSize: 12)),
                        TextSpan(text: fmtMoney(r.totalValue), style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                      ])),
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: 'المدفوع / المتبقي: ', style: TextStyle(fontSize: 12)),
                        TextSpan(text: fmtMoney(r.paidAmount), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.green)),
                        const TextSpan(text: ' / '),
                        TextSpan(text: fmtMoney(r.remaining), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.orange)),
                      ])),
                      if (r.notes != null && r.notes!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Text('📝 ${r.notes}', style: const TextStyle(fontSize: 11)),
                        ),
                      if (r.rejectReason != null && r.rejectReason!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text('سبب الرفض: ${r.rejectReason}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                        ),
                    ],
                  ),
                ),
                _StatusChip(status: r.status),
              ],
            ),
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: (isCash ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isCash ? Icons.payments_outlined : Icons.account_balance_wallet_outlined,
                        size: 14, color: isCash ? Colors.green : Colors.orange),
                    const SizedBox(width: 4),
                    Text(isCash ? 'نقد' : 'آجل', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (isAdmin && r.status == 'PENDING') ...[
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('اعتماد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('رفض', style: TextStyle(color: Colors.red)),
                  ),
                ],
                if (isAdmin && r.status == 'APPROVED' && r.remaining > 0)
                  FilledButton.icon(
                    onPressed: onPay,
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('تسجيل دفعة'),
                  ),
                if (fullyPaid)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text('مسدد بالكامل', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green)),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'PENDING' => ('قيد المراجعة', Colors.orange),
      'APPROVED' => ('مقبولة', Colors.green),
      'REJECTED' => ('مرفوضة', Colors.red),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
