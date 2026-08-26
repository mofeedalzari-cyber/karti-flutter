// نفس تصميم src/routes/app.superadmin.tsx (اللوحة الرئيسية) — إحصائيات
// عامة، وتبويبات (الشبكات/المناديب/الباقات) بإجراءات تفعيل/تعطيل/حذف.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import 'superadmin_providers.dart';

class SuperadminScreen extends ConsumerWidget {
  const SuperadminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(superadminStatsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة السوبر أدمن'),
          bottom: const TabBar(tabs: [Tab(text: 'الشبكات'), Tab(text: 'المناديب'), Tab(text: 'الباقات')]),
        ),
        body: Column(
          children: [
            statsAsync.when(
              data: (stats) => Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1.3,
                  children: [
                    _MiniStat(label: 'الشبكات', value: '${stats['networks'] ?? 0}'),
                    _MiniStat(label: 'المناديب', value: '${stats['agents'] ?? 0}'),
                    _MiniStat(label: 'الباقات', value: '${stats['packages'] ?? 0}'),
                    _MiniStat(label: 'الكروت', value: '${stats['cards'] ?? 0}'),
                  ],
                ),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const Expanded(
              child: TabBarView(children: [_NetworksTab(), _AgentsTab(), _PackagesTab()]),
            ),
          ],
        ),
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
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ]),
    );
  }
}

class _NetworksTab extends ConsumerWidget {
  const _NetworksTab();

  Future<void> _toggle(BuildContext context, WidgetRef ref, Map<String, dynamic> n) async {
    final active = n['is_active'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? 'إيقاف الشبكة' : 'تفعيل الشبكة'),
        content: Text(active ? 'إيقاف شبكة "${n['name']}"؟ لن يتمكن مستخدموها من الدخول.' : 'إعادة تفعيل شبكة "${n['name']}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await superadminSetNetworkActive(n['id'] as String, !active);
      ref.invalidate(superadminNetworksProvider);
      ref.invalidate(superadminStatsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Map<String, dynamic> n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف نهائي لشبكة "${n['name']}"؟'),
        content: const Text('سيتم حذف جميع المناديب والباقات والكروت والطلبات والمبيعات المرتبطة بها. لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، حذف نهائي')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await superadminDeleteNetwork(n['id'] as String);
      ref.invalidate(superadminNetworksProvider);
      ref.invalidate(superadminStatsProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الشبكة بالكامل')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(superadminNetworksProvider);
    return networksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
      data: (networks) {
        if (networks.isEmpty) return const Center(child: Text('لا توجد شبكات'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: networks.length,
          itemBuilder: (context, i) {
            final n = networks[i];
            final active = n['is_active'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(child: Text(n['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w800))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: (active ? Colors.green : Colors.red).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                        child: Text(active ? 'نشطة' : 'موقوفة', style: TextStyle(fontSize: 10, color: active ? Colors.green : Colors.red)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('كروت: ${n['cards_count'] ?? 0} · مناديب: ${n['agents_count'] ?? 0}', style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: () => _toggle(context, ref, n),
                        icon: Icon(active ? Icons.power_settings_new : Icons.power, size: 16),
                        label: Text(active ? 'إيقاف' : 'تفعيل'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _delete(context, ref, n),
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: const Text('حذف', style: TextStyle(color: Colors.red)),
                      ),
                    ]),
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

class _AgentsTab extends ConsumerWidget {
  const _AgentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsAsync = ref.watch(superadminAgentsProvider);
    return agentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
      data: (agents) {
        if (agents.isEmpty) return const Center(child: Text('لا يوجد مناديب'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: agents.length,
          itemBuilder: (context, i) {
            final a = agents[i];
            final active = a['is_active'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text((a['full_name'] as String?) ?? (a['username'] as String? ?? '—'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${a['network_name'] ?? '—'}', style: const TextStyle(fontSize: 11)),
                trailing: Switch(
                  value: active,
                  onChanged: (v) async {
                    try {
                      await superadminSetAgentActive(a['id'] as String, v);
                      ref.invalidate(superadminAgentsProvider);
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PackagesTab extends ConsumerWidget {
  const _PackagesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(superadminPackagesProvider);
    return packagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
      data: (packages) {
        if (packages.isEmpty) return const Center(child: Text('لا توجد باقات'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: packages.length,
          itemBuilder: (context, i) {
            final p = packages[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(p['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${p['network_name'] ?? '—'}', style: const TextStyle(fontSize: 11)),
                trailing: Text(fmtMoney((p['price'] ?? 0) as num), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            );
          },
        );
      },
    );
  }
}
