// نفس تصميم src/routes/app.payments.tsx — اختيار مندوب، عرض المديونية،
// تسديد دفعة (settle_agent_debt)، سجل الدفعات مع تعديل/حذف.
// ⚠️ طباعة إيصال PDF (printReceiptPDF) مؤجَّلة للمرحلة 7 — التسديد نفسه يعمل
// ويُحدَّث بقاعدة البيانات بشكل كامل، فقط الإيصال المطبوع مؤجَّل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../pdf/receipt_pdf.dart';
import '../auth/profile_provider.dart';
import 'payments_providers.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _settle() async {
    final agentId = ref.read(paymentsAgentProvider);
    if (agentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر المندوب')));
      return;
    }
    final amount = num.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً')));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await settleAgentDebt(agentId: agentId, amount: amount, note: _noteCtrl.text.isEmpty ? null : _noteCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم السداد — طُبِّق ${fmtMoney(r.applied)} • المتبقي ${fmtMoney(r.remainingDebt)}')));
      final network = ref.read(myOwnedNetworkProvider).value;
      final agentName = ref.read(paymentsAgentsListProvider).value?.firstWhere((a) => a['id'] == agentId, orElse: () => {})['full_name'] as String? ?? '';
      final adminName = ref.read(profileProvider).value?.fullName ?? ref.read(profileProvider).value?.username ?? 'المدير';
      try {
        await printReceiptPdf(CreditReceiptInput(
          networkName: network?['name'] as String? ?? '—',
          networkPhone: '',
          agentName: agentName,
          amount: r.applied,
          statement: _noteCtrl.text.isEmpty ? 'سداد دين' : _noteCtrl.text,
          dateStr: DateTime.now().toString().split('.').first,
          adminName: adminName,
        ));
      } catch (_) {
        /* تجاهل فشل الطباعة — التسديد نفسه نجح فعلاً بقاعدة البيانات */
      }
      _amountCtrl.clear();
      _noteCtrl.clear();
      ref.invalidate(agentDebtProvider);
      ref.invalidate(paymentHistoryProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPaymentDialog(PaymentHistoryRow p) async {
    final amountCtrl = TextEditingController(text: p.amount.toString());
    final noteCtrl = TextEditingController(text: p.note ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل عملية التسديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await editPayment(paymentId: p.id, amount: num.tryParse(amountCtrl.text) ?? 0, note: noteCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل عملية التسديد')));
      ref.invalidate(paymentHistoryProvider);
      ref.invalidate(agentDebtProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deletePaymentConfirm(PaymentHistoryRow p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف عملية التسديد'),
        content: Text('حذف دفعة بقيمة ${fmtMoney(p.amount)}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deletePayment(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف عملية التسديد')));
      ref.invalidate(paymentHistoryProvider);
      ref.invalidate(agentDebtProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(paymentsAgentsListProvider);
    final agentId = ref.watch(paymentsAgentProvider);
    final debtAsync = ref.watch(agentDebtProvider);
    final historyAsync = ref.watch(paymentHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          agentsAsync.when(
            data: (agents) => DropdownButtonFormField<String>(
              initialValue: agentId,
              decoration: const InputDecoration(labelText: 'المندوب'),
              items: agents.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text((a['full_name'] as String?) ?? (a['username'] as String)))).toList(),
              onChanged: (v) => ref.read(paymentsAgentProvider.notifier).state = v,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('تعذر التحميل'),
          ),
          const SizedBox(height: 16),
          if (agentId != null) ...[
            debtAsync.when(
              data: (debt) {
                if (debt == null) return const SizedBox.shrink();
                return Card(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('الإجمالي', style: TextStyle(fontSize: 12)),
                        Text(fmtMoney(debt.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('المدفوع', style: TextStyle(fontSize: 12)),
                        Text(fmtMoney(debt.paid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
                      ]),
                      const Divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('المتبقي', style: TextStyle(fontWeight: FontWeight.w800)),
                        Text(fmtMoney(debt.remaining), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.orange)),
                      ]),
                    ]),
                  ),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ التسديد')),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _settle,
              icon: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payments_outlined),
              label: const Text('تسجيل التسديد'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
            const SizedBox(height: 20),
            Text('سجل الدفعات', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            historyAsync.when(
              data: (history) {
                if (history.isEmpty) return const Text('لا توجد دفعات سابقة');
                return Column(
                  children: history
                      .map((p) => Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              title: Text(fmtMoney(p.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text('${p.packageName}${p.note != null ? ' · ${p.note}' : ''}', style: const TextStyle(fontSize: 11)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _editPaymentDialog(p)),
                                IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _deletePaymentConfirm(p)),
                              ]),
                            ),
                          ))
                      .toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('تعذر التحميل: $e'),
            ),
          ],
        ],
      ),
    );
  }
}
