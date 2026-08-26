// نفس src/routes/app.index.tsx → AgentHome بالضبط — ترحيب شخصي + إحصائيات
// المندوب الخاصة (يعيد استخدام نفس منطق AgentStats/agent-accounts).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';
import '../agent_accounts/agent_accounts_providers.dart';

class AgentHomeScreen extends ConsumerWidget {
  const AgentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final statsAsync = ref.watch(myAgentStatsProvider);
    final name = profileAsync.value?.fullName ?? profileAsync.value?.phone ?? profileAsync.value?.username ?? '';

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myAgentStatsProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('أهلاً، $name', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('لوحة البيع', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          statsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('تعذر تحميل الإحصائيات: $e', style: const TextStyle(color: Colors.red)),
            data: (data) {
              if (data == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.6,
                    children: [
                      _StatCard(icon: Icons.inventory_2_outlined, label: 'الكروت المسحوبة', value: '${data.withdrawn}'),
                      _StatCard(icon: Icons.point_of_sale_outlined, label: 'الكروت المباعة', value: '${data.sold}'),
                      _StatCard(icon: Icons.attach_money, label: 'قيمة مبيعاتي', value: fmtMoney(data.salesValue)),
                      _StatCard(icon: Icons.account_balance_wallet_outlined, label: 'المتبقي عليّ', value: fmtMoney(data.totalRemaining)),
                    ],
                  ),
                  if (data.byNetwork.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('حسب الشبكة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ...data.byNetwork.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            title: Text(r.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            subtitle: Text('مسحوب: ${r.withdrawn} · مباع: ${r.sold}', style: const TextStyle(fontSize: 11)),
                            trailing: Text(fmtMoney(r.value), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        )),
                  ],
                ],
              );
            },
          ),
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
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: primary, size: 20),
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), textDirection: TextDirection.ltr),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
