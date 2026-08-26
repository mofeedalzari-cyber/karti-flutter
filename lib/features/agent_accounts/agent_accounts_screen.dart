// نفس تصميم src/routes/app.agent-accounts.tsx — اختيار شبكة/مندوب، إحصائيات
// ملخصة، جدول مديونية/مدفوعات، جدول حسب الشبكة، جدول حسب الباقة، وتسوية
// المديونيات (reconcile_agent_debts).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../networks/networks_providers.dart';
import 'agent_accounts_providers.dart';

class AgentAccountsScreen extends ConsumerStatefulWidget {
  const AgentAccountsScreen({super.key});

  @override
  ConsumerState<AgentAccountsScreen> createState() => _AgentAccountsScreenState();
}

class _AgentAccountsScreenState extends ConsumerState<AgentAccountsScreen> {
  bool _reconciling = false;

  Future<void> _reconcile() async {
    setState(() => _reconciling = true);
    try {
      final networkId = ref.read(aaNetworkFilterProvider);
      final r = await reconcileAgentDebts(networkId);
      if (!mounted) return;
      if (r.created > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت تسوية ${r.created} سجل مديونية بقيمة ${fmtMoney(r.totalValue)}')));
        ref.invalidate(agentAccountDataProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد مديونيات تحتاج تسوية')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(networksProvider);
    final agentsAsync = ref.watch(aaAgentsListProvider);
    final networkFilter = ref.watch(aaNetworkFilterProvider);
    final agentId = ref.watch(aaAgentProvider);
    final dataAsync = ref.watch(agentAccountDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابات المناديب'),
        actions: [
          IconButton(
            tooltip: 'تسوية المديونيات',
            icon: _reconciling
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.balance_outlined),
            onPressed: _reconciling ? null : _reconcile,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('عرض تفصيلي لحساب كل مندوب حسب الشبكة والفئة', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: networksAsync.when(
                data: (networks) => DropdownButtonFormField<String>(
                  initialValue: networkFilter,
                  decoration: const InputDecoration(labelText: 'الشبكة', isDense: true),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('كل الشبكات')),
                    ...networks.map((n) => DropdownMenuItem(value: n.id, child: Text(n.name))),
                  ],
                  onChanged: (v) => ref.read(aaNetworkFilterProvider.notifier).state = v ?? 'all',
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر التحميل'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: agentsAsync.when(
                data: (agents) => DropdownButtonFormField<String>(
                  initialValue: agentId,
                  decoration: const InputDecoration(labelText: 'المندوب', isDense: true),
                  items: agents
                      .map((a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text((a['full_name'] as String?) ?? (a['username'] as String)),
                          ))
                      .toList(),
                  onChanged: (v) => ref.read(aaAgentProvider.notifier).state = v,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر التحميل'),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          if (agentId == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('اختر مندوباً لعرض حسابه')))
          else
            dataAsync.when(
              loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('تعذر التحميل: $e', style: const TextStyle(color: Colors.red)),
              data: (data) {
                if (data == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(data.agentLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.2,
                      children: [
                        _Stat(label: 'مسحوب حالياً', value: '${data.withdrawn}'),
                        _Stat(label: 'مباع', value: '${data.sold}'),
                        _Stat(label: 'قيمة المبيعات', value: fmtMoney(data.salesValue)),
                        _Stat(label: 'عدد الباقات', value: '${data.distinctPackages}'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('المديونية والمدفوعات', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _DataTable(
                      columns: const ['الشبكة', 'الإجمالي', 'المدفوع', 'المتبقي'],
                      rows: data.paidRows.isEmpty
                          ? []
                          : [
                              ...data.paidRows.map((r) => [r.label, fmtMoney(r.total), fmtMoney(r.paid), fmtMoney(r.remaining)]),
                              ['الإجمالي', fmtMoney(data.totalDebt), fmtMoney(data.totalPaid), fmtMoney(data.totalRemaining)],
                            ],
                      empty: 'لا توجد ديون مسجّلة',
                    ),
                    const SizedBox(height: 20),
                    Text('حسب الشبكة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _DataTable(
                      columns: const ['الشبكة', 'مسحوب', 'مباع', 'القيمة'],
                      rows: data.byNetwork.map((r) => [r.label, '${r.withdrawn}', '${r.sold}', fmtMoney(r.value)]).toList(),
                      empty: 'لا توجد بيانات',
                    ),
                    const SizedBox(height: 20),
                    Text('حسب الباقة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _DataTable(
                      columns: const ['الباقة', 'الشبكة', 'مسحوب', 'مباع', 'القيمة'],
                      rows: data.byPackage.map((r) => [r.label, r.sub ?? '—', '${r.withdrawn}', '${r.sold}', fmtMoney(r.value)]).toList(),
                      empty: 'لا توجد بيانات',
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), textDirection: TextDirection.ltr),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _DataTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;
  final String empty;
  const _DataTable({required this.columns, required this.rows, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
        child: Text(empty, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columns.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))).toList(),
        rows: rows
            .map((r) => DataRow(cells: r.map((v) => DataCell(Text(v, style: const TextStyle(fontSize: 12)))).toList()))
            .toList(),
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 40,
      ),
    );
  }
}
