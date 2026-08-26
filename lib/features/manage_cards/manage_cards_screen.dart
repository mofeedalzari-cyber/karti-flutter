// نفس تصميم src/routes/app.manage-cards.tsx للجزء الأساسي: فلاتر (شبكة/باقة/
// مندوب/بحث)، قائمة الكروت بحالاتها الملوّنة، تحديد جماعي، حذف/إرجاع ذكي.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../networks/networks_providers.dart';
import '../pdf/card_print_pdf.dart';
import 'manage_cards_providers.dart';

class ManageCardsScreen extends ConsumerStatefulWidget {
  const ManageCardsScreen({super.key});

  @override
  ConsumerState<ManageCardsScreen> createState() => _ManageCardsScreenState();
}

class _ManageCardsScreenState extends ConsumerState<ManageCardsScreen> {
  final Set<String> _selected = {};
  bool _extendedDelete = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bulkDelete(List<CardRow> allCards) async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف/إرجاع الكروت المحددة'),
        content: Text('سيتم التعامل مع ${_selected.length} كرت (إرجاع المسحوب منها للمتاح، وحذف الباقي).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final r = await bulkDeleteOrUnassign(
        allCards: allCards,
        selectedIds: _selected,
        extendedDelete: _extendedDelete,
      );
      final parts = <String>[];
      if (r.deleted > 0) parts.add('تم حذف ${r.deleted} كرت');
      if (r.unassigned > 0) parts.add('تم إرجاع ${r.unassigned} كرت مسحوب إلى المتاح');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.isNotEmpty ? parts.join(' — ') : 'لا يوجد تغييرات')));
      setState(() => _selected.clear());
      ref.invalidate(manageCardsListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _transferSold(List<CardRow> allCards) async {
    final soldSelected = _selected
        .where((id) => allCards.any((c) => c.id == id && c.status == 'SOLD'))
        .toList();
    if (soldSelected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدّد كروتاً مباعة أولاً')));
      return;
    }
    final networkId = ref.read(manageCardsFiltersProvider).networkId;
    if (networkId == null) return;
    final agents = await ref.read(manageCardsAgentsProvider(networkId).future);
    if (!mounted) return;
    final toAgent = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('نقل الكروت المباعة إلى مندوب آخر'),
        children: agents
            .map((a) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, a['id'] as String),
                  child: Text(a['name'] as String),
                ))
            .toList(),
      ),
    );
    if (toAgent == null) return;
    try {
      final r = await transferSoldCards(cardIds: soldSelected, toAgentId: toAgent);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.moved > 0
              ? 'تم نقل ${r.moved} كرت مباع وتحويل ${r.amount} إلى المندوب الجديد'
              : 'لا يوجد كروت قابلة للنقل')));
      setState(() => _selected.clear());
      ref.invalidate(manageCardsListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteOldSold(List<CardRow> allCards) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الكروت القديمة'),
        content: const Text('سيتم حذف كل الكروت المباعة/المسحوبة الأقدم من 30 يوم نهائياً. متأكد؟'),
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
      final deleted = await deleteOldSoldCards(allCards);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(deleted > 0 ? 'تم حذف $deleted كرت قديم' : 'لا يوجد كروت قديمة للحذف')));
      ref.invalidate(manageCardsListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _printSelected(List<CardRow> allCards) async {
    final selectedCards = allCards.where((c) => _selected.contains(c.id)).toList();
    if (selectedCards.isEmpty) return;
    try {
      await printCardsPdf(
        cards: selectedCards.map((c) => PrintableCard(username: c.username, password: c.password)).toList(),
        title: 'كشف كروت (${selectedCards.length})',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(manageCardsFiltersProvider);
    final networksAsync = ref.watch(networksListProvider);
    final cardsAsync = ref.watch(manageCardsListProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إدارة الكروت', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              networksAsync.when(
                data: (networks) => DropdownButtonFormField<String>(
                  initialValue: filters.networkId,
                  decoration: const InputDecoration(labelText: 'الشبكة (مطلوبة)'),
                  items: networks.map((n) => DropdownMenuItem(value: n.id, child: Text(n.name))).toList(),
                  onChanged: (v) => ref.read(manageCardsFiltersProvider.notifier).state =
                      ManageCardsFilters(networkId: v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر التحميل'),
              ),
              if (filters.networkId != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Consumer(builder: (context, ref, _) {
                      final pkgsAsync = ref.watch(manageCardsPackagesProvider(filters.networkId!));
                      return DropdownButtonFormField<String?>(
                        initialValue: filters.packageId,
                        decoration: const InputDecoration(labelText: 'الباقة'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('الكل')),
                          ...(pkgsAsync.value ?? []).map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] as String))),
                        ],
                        onChanged: (v) => ref.read(manageCardsFiltersProvider.notifier).state =
                            filters.copyWith(packageId: v, clearPackage: v == null),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Consumer(builder: (context, ref, _) {
                      final agentsAsync = ref.watch(manageCardsAgentsProvider(filters.networkId!));
                      return DropdownButtonFormField<String?>(
                        initialValue: filters.agentId,
                        decoration: const InputDecoration(labelText: 'المندوب'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('الكل')),
                          ...(agentsAsync.value ?? []).map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String))),
                        ],
                        onChanged: (v) => ref.read(manageCardsFiltersProvider.notifier).state =
                            filters.copyWith(agentId: v, clearAgent: v == null),
                      );
                    }),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(labelText: 'بحث (اسم مستخدم الكرت)', prefixIcon: Icon(Icons.search)),
                  onSubmitted: (v) => ref.read(manageCardsFiltersProvider.notifier).state = filters.copyWith(search: v),
                ),
              ],
            ],
          ),
        ),
        if (_selected.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('${_selected.length} محدد', style: const TextStyle(fontWeight: FontWeight.w700)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    value: _extendedDelete,
                    onChanged: (v) => setState(() => _extendedDelete = v ?? false),
                  ),
                  const Text('حذف موسّع', style: TextStyle(fontSize: 12)),
                ]),
                TextButton.icon(
                  onPressed: () => _printSelected(cardsAsync.value ?? []),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('طباعة'),
                ),
                TextButton.icon(
                  onPressed: () => _transferSold(cardsAsync.value ?? []),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('نقل المباع'),
                ),
                TextButton.icon(
                  onPressed: () => _bulkDelete(cardsAsync.value ?? []),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('حذف/إرجاع', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        if (filters.networkId != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _deleteOldSold(cardsAsync.value ?? []),
                icon: const Icon(Icons.auto_delete_outlined, size: 16, color: Colors.orange),
                label: const Text('حذف الكروت القديمة (+30 يوم)', style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            ),
          ),
        Expanded(
          child: filters.networkId == null
              ? const Center(child: Text('اختر شبكة لعرض الكروت'))
              : cardsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
                  data: (cards) {
                    if (cards.isEmpty) return const Center(child: Text('لا توجد كروت مطابقة'));
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: cards.length,
                      itemBuilder: (context, i) {
                        final c = cards[i];
                        final isSelected = _selected.contains(c.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Checkbox(
                              value: isSelected,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selected.add(c.id);
                                } else {
                                  _selected.remove(c.id);
                                }
                              }),
                            ),
                            title: Text(c.username, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              [
                                c.packageName,
                                if (c.status == 'ASSIGNED' && c.assignedFullName != null) 'مسحوب: ${c.assignedFullName}',
                                if (c.status == 'SOLD' && (c.customerName ?? c.soldFullName) != null)
                                  'مباع لـ: ${c.customerName ?? c.soldFullName}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: _StatusBadge(status: c.status),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'AVAILABLE' => ('متاح', Colors.green),
      'ASSIGNED' => ('مسحوب', Colors.orange),
      'SOLD' => ('مباع', Colors.blue),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
