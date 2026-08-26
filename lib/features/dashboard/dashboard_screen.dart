// نفس منطق src/routes/app.index.tsx (AdminDashboard) بالضبط — يستدعي نفس
// دالة قاعدة البيانات admin_stats() بدون أي تعديل عليها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import '../../services/report_export.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';

class AdminStats {
  final int totalCards;
  final int available;
  final int sold;
  final num soldValue;
  final num availableValue;
  final int networks;
  final int packages;
  final int agents;

  AdminStats({
    required this.totalCards,
    required this.available,
    required this.sold,
    required this.soldValue,
    required this.availableValue,
    required this.networks,
    required this.packages,
    required this.agents,
  });

  factory AdminStats.fromMap(Map<String, dynamic> m) => AdminStats(
        totalCards: (m['total_cards'] ?? 0) as int,
        available: (m['available'] ?? 0) as int,
        sold: (m['sold'] ?? 0) as int,
        soldValue: (m['sold_value'] ?? 0) as num,
        availableValue: (m['available_value'] ?? 0) as num,
        networks: (m['networks'] ?? 0) as int,
        packages: (m['packages'] ?? 0) as int,
        agents: (m['agents'] ?? 0) as int,
      );
}

final adminStatsProvider = FutureProvider<AdminStats>((ref) async {
  final data = await supabase.rpc('admin_stats');
  return AdminStats.fromMap(data as Map<String, dynamic>);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminStatsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('لوحة التحكم',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('نظرة شاملة على أداء المتجر',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 20),
          statsAsync.when(
            data: (stats) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: [
                _StatCard(icon: Icons.inventory_2_outlined, label: 'إجمالي الكروت', value: '${stats.totalCards}'),
                _StatCard(icon: Icons.shopping_cart_outlined, label: 'المتوفر', value: '${stats.available}'),
                _StatCard(icon: Icons.bolt_outlined, label: 'المباع', value: '${stats.sold}'),
                _StatCard(icon: Icons.attach_money, label: 'قيمة المبيعات', value: fmtMoney(stats.soldValue)),
                _StatCard(icon: Icons.wifi, label: 'الشبكات', value: '${stats.networks}'),
                _StatCard(icon: Icons.inventory_outlined, label: 'الباقات', value: '${stats.packages}'),
                _StatCard(icon: Icons.people_outline, label: 'المناديب', value: '${stats.agents}'),
                _StatCard(icon: Icons.trending_up, label: 'قيمة المتوفر', value: fmtMoney(stats.availableValue)),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('تعذر تحميل الإحصائيات: $e', style: const TextStyle(color: Colors.red)),
            ),
          ),
          const AdminBreakdownsSection(),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: primary, size: 20),
            ),
            const Spacer(),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                textDirection: TextDirection.ltr),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// تفصيل إضافي (AdminBreakdowns بالنسخة الأصلية) — dashboard_breakdown RPC:
// ملخص الديون/التحصيل، تفصيل حسب الباقة، أرصدة المناديب، تصفير الرصيد.
// ⚠️ تصدير Excel/PDF من هذا القسم مؤجَّل للمرحلة 7 (نفس حدود PDF المعروفة).
// ============================================================

class DashboardBreakdown {
  final String? currency;
  final String? networkName;
  final num total, sold, remaining, salesValue, debts, collected, settled;
  final int agentsCount;
  final List<Map<String, dynamic>> packages; // {pkg,total,sold,withdrawn,remaining,value}
  final List<Map<String, dynamic>> agentHoldings; // {agent_id,agent,phone,pkg,price,holding}
  final List<Map<String, dynamic>> agents; // {full_name,username,phone,is_active}

  DashboardBreakdown({
    this.currency,
    this.networkName,
    required this.total,
    required this.sold,
    required this.remaining,
    required this.salesValue,
    required this.debts,
    required this.collected,
    required this.settled,
    required this.agentsCount,
    required this.packages,
    required this.agentHoldings,
    required this.agents,
  });

  factory DashboardBreakdown.fromMap(Map<String, dynamic> m) {
    final s = (m['summary'] as Map<String, dynamic>?) ?? {};
    return DashboardBreakdown(
      currency: m['currency'] as String?,
      networkName: m['network_name'] as String?,
      total: (s['total'] ?? 0) as num,
      sold: (s['sold'] ?? 0) as num,
      remaining: (s['remaining'] ?? 0) as num,
      salesValue: (s['salesValue'] ?? 0) as num,
      debts: (s['debts'] ?? 0) as num,
      collected: (s['collected'] ?? 0) as num,
      settled: (s['settled'] ?? 0) as num,
      agentsCount: (s['agentsCount'] ?? 0) as int,
      packages: ((m['packages'] as List?) ?? []).cast<Map<String, dynamic>>(),
      agentHoldings: ((m['agent_holdings'] as List?) ?? []).cast<Map<String, dynamic>>(),
      agents: ((m['agents'] as List?) ?? []).cast<Map<String, dynamic>>(),
    );
  }
}

final dashboardBreakdownProvider = FutureProvider<DashboardBreakdown>((ref) async {
  final data = await supabase.rpc('dashboard_breakdown');
  return DashboardBreakdown.fromMap(data as Map<String, dynamic>);
});

Future<num> resetBalance() async {
  final data = await supabase.rpc('admin_reset_balance');
  final row = (data is List) ? data.first as Map<String, dynamic>? : data as Map<String, dynamic>?;
  return (row?['cleared'] ?? 0) as num;
}

class AdminBreakdownsSection extends ConsumerWidget {
  const AdminBreakdownsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownAsync = ref.watch(dashboardBreakdownProvider);
    return breakdownAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('تعذر تحميل التفصيل: $e', style: const TextStyle(color: Colors.red)),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ملخص الشبكة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'تصدير PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                  onPressed: () => _exportPdf(context, ref, d),
                ),
                IconButton(
                  tooltip: 'تصدير Excel',
                  icon: const Icon(Icons.grid_on_outlined, size: 20),
                  onPressed: () => _exportExcel(context, d),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 10),
          _SummaryGrid(d: d, ref: ref),
          if (d.packages.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('حسب الباقة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _SimpleTable(
              columns: const ['الفئة', 'إجمالي', 'مباع', 'متبقٍ', 'القيمة'],
              rows: d.packages
                  .map((p) => [
                        '${p['pkg'] ?? '—'}',
                        '${p['total'] ?? 0}',
                        '${p['sold'] ?? 0}',
                        '${p['remaining'] ?? 0}',
                        fmtMoney((p['value'] ?? 0) as num),
                      ])
                  .toList(),
            ),
          ],
          if (d.agentHoldings.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('أرصدة المناديب (كروت لديهم)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _SimpleTable(
              columns: const ['المندوب', 'الفئة', 'لديه', 'السعر'],
              rows: d.agentHoldings
                  .map((h) => ['${h['agent'] ?? '—'}', '${h['pkg'] ?? '—'}', '${h['holding'] ?? 0}', fmtMoney((h['price'] ?? 0) as num)])
                  .toList(),
            ),
          ],
          if (d.agents.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('المناديب المرتبطين بالشبكة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...d.agents.map((a) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    title: Text((a['full_name'] as String?) ?? (a['username'] as String? ?? '—'), style: const TextStyle(fontSize: 13)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (a['is_active'] == true ? Colors.green : Colors.red).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(a['is_active'] == true ? 'نشط' : 'موقوف',
                          style: TextStyle(fontSize: 10, color: a['is_active'] == true ? Colors.green : Colors.red)),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  List<ReportTableSection> _buildSections(DashboardBreakdown d) => [
        if (d.packages.isNotEmpty)
          ReportTableSection(
            title: 'حسب الباقة',
            cols: const ['الفئة', 'إجمالي', 'مباع', 'متبقٍ', 'القيمة'],
            rows: d.packages
                .map((p) => ['${p['pkg'] ?? '—'}', '${p['total'] ?? 0}', '${p['sold'] ?? 0}', '${p['remaining'] ?? 0}', fmtMoney((p['value'] ?? 0) as num)])
                .toList(),
          ),
        if (d.agentHoldings.isNotEmpty)
          ReportTableSection(
            title: 'أرصدة المناديب',
            cols: const ['المندوب', 'الفئة', 'لديه', 'السعر'],
            rows: d.agentHoldings.map((h) => ['${h['agent'] ?? '—'}', '${h['pkg'] ?? '—'}', '${h['holding'] ?? 0}', fmtMoney((h['price'] ?? 0) as num)]).toList(),
          ),
        if (d.agents.isNotEmpty)
          ReportTableSection(
            title: 'المناديب',
            cols: const ['الاسم', 'الحالة'],
            rows: d.agents.map((a) => ['${a['full_name'] ?? a['username'] ?? '—'}', a['is_active'] == true ? 'نشط' : 'موقوف']).toList(),
          ),
      ];

  List<ReportSummaryRow> _buildSummary(DashboardBreakdown d) => [
        ReportSummaryRow('إجمالي الكروت', '${d.total}'),
        ReportSummaryRow('المباعة', '${d.sold}'),
        ReportSummaryRow('قيمة المبيعات', fmtMoney(d.salesValue)),
        ReportSummaryRow('ديون المناديب', fmtMoney(d.debts)),
        ReportSummaryRow('المسدد', fmtMoney(d.settled)),
        ReportSummaryRow('الرصيد', fmtMoney(d.collected)),
      ];

  Future<void> _exportPdf(BuildContext context, WidgetRef ref, DashboardBreakdown d) async {
    try {
      final profile = ref.read(profileProvider).value;
      await exportReportToPdf(
        title: d.networkName ?? 'تقرير الشبكة',
        summary: _buildSummary(d),
        sections: _buildSections(d),
        userName: profile?.fullName ?? profile?.username,
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير PDF: $e')));
    }
  }

  Future<void> _exportExcel(BuildContext context, DashboardBreakdown d) async {
    try {
      await exportReportToExcel(fileName: d.networkName ?? 'تقرير', summary: _buildSummary(d), sections: _buildSections(d));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير Excel: $e')));
    }
  }
}

class _SummaryGrid extends StatelessWidget {
  final DashboardBreakdown d;
  final WidgetRef ref;
  const _SummaryGrid({required this.d, required this.ref});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: [
        _MiniStat('إجمالي الكروت', '${d.total}'),
        _MiniStat('المباعة', '${d.sold}'),
        _MiniStat('قيمة المبيعات', fmtMoney(d.salesValue)),
        _MiniStat('ديون المناديب', fmtMoney(d.debts)),
        _MiniStat('المسدد', fmtMoney(d.settled)),
        _ResetBalanceStat(amount: d.collected),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), textDirection: TextDirection.ltr),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _ResetBalanceStat extends ConsumerWidget {
  final num amount;
  const _ResetBalanceStat({required this.amount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(fmtMoney(amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), textDirection: TextDirection.ltr),
            if (amount > 0)
              InkWell(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('تصفير الرصيد'),
                      content: Text(
                          'سيتم تصفير الرصيد الحالي (${fmtMoney(amount)}) وخصم المبلغ المدفوع من إجمالي الدين لكل طلب. لن يتأثر الدين المتبقي على المناديب. لا يمكن التراجع.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('تأكيد التصفير'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    final cleared = await resetBalance();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تصفير الرصيد — ${fmtMoney(cleared)}')));
                    ref.invalidate(dashboardBreakdownProvider);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                child: const Icon(Icons.restart_alt, size: 16, color: Colors.red),
              ),
          ]),
          Text('الرصيد', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _SimpleTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;
  const _SimpleTable({required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: columns.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))).toList(),
        rows: rows.map((r) => DataRow(cells: r.map((v) => DataCell(Text(v, style: const TextStyle(fontSize: 11)))).toList())).toList(),
      ),
    );
  }
}
