// نفس منطق src/routes/app.customers.tsx (الجزء الإداري) — network_customers
// RPC، فلترة حسب المندوب، تسوية دين زبون عبر مندوبه (admin_settle_customer_via_agent).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import 'customers_providers.dart';

class AdminCustomersScreen extends ConsumerStatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  ConsumerState<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends ConsumerState<AdminCustomersScreen> {
  String _search = '';

  Future<void> _openSettle(NetCustomer c) async {
    final amountCtrl = TextEditingController(text: c.balance.toStringAsFixed(0));
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تسوية دين ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('عبر المندوب: ${c.agentUsername ?? '—'}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسوية')),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = num.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً')));
      return;
    }
    try {
      final remaining = await settleCustomerViaAgent(customerId: c.id, amount: amount, note: noteCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت التسوية — المتبقي ${fmtMoney(remaining)}')));
      ref.invalidate(networkCustomersProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(networkCustomersProvider);
    final agentFilter = ref.watch(netAgentFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('زبائن الشبكة')),
      body: customersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
        data: (all) {
          final agents = {for (final c in all) if (c.agentId != null) c.agentId!: c.agentUsername ?? ''};
          final q = _search.trim().toLowerCase();
          var filtered = all.where((c) {
            if (agentFilter != null && c.agentId != agentFilter) return false;
            if (q.isEmpty) return true;
            return c.name.toLowerCase().contains(q) || c.whatsapp.contains(q) || (c.agentUsername ?? '').toLowerCase().contains(q);
          }).toList()
            ..sort((a, b) => b.balance.compareTo(a.balance));

          final totalBalance = filtered.fold<num>(0, (s, c) => s + c.balance);
          final totalSales = filtered.fold<num>(0, (s, c) => s + c.salesTotal + c.charges);
          final totalPaid = filtered.fold<num>(0, (s, c) => s + c.paid);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: 'بحث بالاسم أو واتساب أو المندوب', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: agentFilter,
                      decoration: const InputDecoration(labelText: 'المندوب', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل المناديب')),
                        ...agents.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                      ],
                      onChanged: (v) => ref.read(netAgentFilterProvider.notifier).state = v,
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _MiniStat(label: 'عدد الزبائن', value: '${filtered.length}')),
                      Expanded(child: _MiniStat(label: 'إجمالي المبيعات', value: fmtMoney(totalSales))),
                      Expanded(child: _MiniStat(label: 'الديون', value: fmtMoney(totalBalance))),
                      Expanded(child: _MiniStat(label: 'المسدد', value: fmtMoney(totalPaid))),
                    ]),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('لا يوجد زبائن مطابقين'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final c = filtered[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${c.agentUsername ?? 'بدون مندوب'} · ${c.whatsapp}', style: const TextStyle(fontSize: 11)),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtMoney(c.balance), style: TextStyle(fontWeight: FontWeight.w800, color: c.balance > 0 ? Colors.orange : Colors.green)),
                                  if (c.balance > 0)
                                    TextButton(
                                      onPressed: () => _openSettle(c),
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24)),
                                      child: const Text('تسوية', style: TextStyle(fontSize: 11)),
                                    ),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis),
      Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
    ]);
  }
}
