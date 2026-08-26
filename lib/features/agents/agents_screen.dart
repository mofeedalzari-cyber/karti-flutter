// نفس تصميم src/routes/app.agents.tsx للجزء الأساسي — بحث، قائمة مناديب
// بإحصائية مبيعات مختصرة، تفعيل/تعطيل، تغيير الشبكة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../networks/networks_providers.dart';
import '../backup/backup_providers.dart';
import 'agents_providers.dart';

class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsAsync = ref.watch(agentsListProvider);
    final search = ref.watch(agentsSearchProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المناديب')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(agentsListProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'بحث بالاسم أو اسم المستخدم', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => ref.read(agentsSearchProvider.notifier).state = v,
            ),
            const SizedBox(height: 16),
            agentsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('تعذر التحميل: $e', style: const TextStyle(color: Colors.red)),
              data: (agents) {
                final filtered = search.isEmpty
                    ? agents
                    : agents.where((a) =>
                        a.username.toLowerCase().contains(search.toLowerCase()) ||
                        (a.fullName ?? '').toLowerCase().contains(search.toLowerCase())).toList();
                if (filtered.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('لا يوجد مناديب')));
                return Column(
                  children: filtered.map((a) => _AgentCard(agent: a)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends ConsumerWidget {
  final AgentModel agent;
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                    backgroundColor: primary,
                    child: Text(agent.displayName.isNotEmpty ? agent.displayName[0] : '?',
                        style: const TextStyle(color: Colors.white))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text('@${agent.username}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600), textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                Switch(
                  value: agent.isActive,
                  onChanged: (v) async {
                    try {
                      await setAgentActive(agent.id, v);
                      ref.invalidate(agentsListProvider);
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _openEditDialog(context, ref);
                    if (v == 'delete') _confirmDelete(context, ref);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'delete', child: Text('حذف نهائي', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _MiniStat(label: 'عدد المبيعات', value: '${agent.salesCount}')),
                Expanded(child: _MiniStat(label: 'إجمالي المبيعات', value: fmtMoney(agent.salesTotal))),
              ],
            ),
            const SizedBox(height: 10),
            Consumer(builder: (context, ref, _) {
              final networksAsync = ref.watch(networksProvider);
              return DropdownButtonFormField<String?>(
                initialValue: agent.networkId,
                decoration: const InputDecoration(labelText: 'الشبكة', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('بدون شبكة')),
                  ...(networksAsync.value ?? []).map((n) => DropdownMenuItem(value: n.id, child: Text(n.name))),
                ],
                onChanged: (v) async {
                  try {
                    await setAgentNetwork(agent.id, v);
                    ref.invalidate(agentsListProvider);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController(text: agent.fullName ?? '');
    final phoneCtrl = TextEditingController(text: agent.phone ?? '');
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل ${agent.displayName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
          const SizedBox(height: 10),
          TextField(controller: phoneCtrl, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم الجوال')),
          const SizedBox(height: 10),
          TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة مرور جديدة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await adminUpdateAgent(
        agentId: agent.id,
        fullName: nameCtrl.text,
        phone: phoneCtrl.text,
        password: passCtrl.text.isEmpty ? null : passCtrl.text,
      );
      ref.invalidate(agentsListProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المندوب نهائياً'),
        content: Text('حذف "${agent.displayName}"؟ سجل المبيعات والكروت السابقة يبقى محفوظاً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await adminDeleteAgent(agent.id);
      ref.invalidate(agentsListProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), textDirection: TextDirection.ltr),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}
