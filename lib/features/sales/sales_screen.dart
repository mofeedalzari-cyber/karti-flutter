// نفس تصميم src/routes/app.sales.tsx (الأجزاء الجوهرية) — بحث، فلاتر
// (عميل/مندوب/باقة/تاريخ)، ملخص حسب الباقة، تعديل، حذف جماعي.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';
import 'sales_providers.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  String _search = '';
  String? _customerFilter;
  String? _agentFilter;
  String? _packageFilter;
  final Set<String> _selected = {};

  List<SaleRow> _applyFilters(List<SaleRow> sales) {
    final q = _search.trim().toLowerCase();
    return sales.where((r) {
      if (_customerFilter != null && r.customerId != _customerFilter) return false;
      if (_agentFilter != null && r.agentKey != _agentFilter) return false;
      if (_packageFilter != null && r.packageName != _packageFilter) return false;
      if (q.isEmpty) return true;
      return r.transactionNo.toLowerCase().contains(q) ||
          r.packageName.toLowerCase().contains(q) ||
          r.networkName.toLowerCase().contains(q) ||
          r.agentUsername.toLowerCase().contains(q) ||
          (r.buyerName ?? '').toLowerCase().contains(q) ||
          (r.customerName ?? '').toLowerCase().contains(q) ||
          (r.cardUsername ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openEdit(SaleRow s, bool isAdmin) async {
    final buyerCtrl = TextEditingController(text: s.buyerName ?? '');
    final priceCtrl = TextEditingController(text: s.price.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل العملية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: buyerCtrl, decoration: const InputDecoration(labelText: 'اسم المشتري')),
            if (isAdmin) ...[
              const SizedBox(height: 10),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (confirmed != true) return;
    num? price;
    if (isAdmin) {
      price = num.tryParse(priceCtrl.text);
      if (price == null || price < 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سعر غير صالح')));
        return;
      }
    }
    try {
      await updateSale(s.id, buyerName: buyerCtrl.text, price: price);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات')));
      ref.invalidate(salesListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    bool deleteCards = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('حذف ${_selected.length} عملية'),
          content: Row(children: [
            Checkbox(value: deleteCards, onChanged: (v) => setState(() => deleteCards = v ?? false)),
            const Expanded(child: Text('حذف الكروت المرتبطة أيضاً (إرجاعها كمتاحة أو حذفها)', style: TextStyle(fontSize: 12))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final r = await bulkDeleteSales(_selected.toList(), deleteCards: deleteCards);
    if (!mounted) return;
    if (r.ok > 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف ${r.ok} عملية')));
    if (r.fail > 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حذف ${r.fail}')));
    setState(() => _selected.clear());
    ref.invalidate(salesListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final salesAsync = ref.watch(salesListProvider);
    final isAdmin = profileAsync.value?.role == Role.admin;

    return Scaffold(
      appBar: AppBar(title: Text(isAdmin ? 'جميع المبيعات' : 'مبيعاتي')),
      body: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
        data: (allSales) {
          final filtered = _applyFilters(allSales);
          final packageOptions = allSales.map((s) => s.packageName).toSet().toList()..sort();
          final agentOptions = {for (final s in allSales) s.agentKey: s.agentUsername};
          final customerOptions = {
            for (final s in allSales)
              if (s.customerId != null) s.customerId!: s.customerName ?? ''
          };

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('عرض ${filtered.length} من ${allSales.length} عملية', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(labelText: 'بحث برقم العملية / الاسم / الكرت', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _packageFilter,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'الباقة', isDense: true),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('الكل')),
                            ...packageOptions.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) => setState(() => _packageFilter = v),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _agentFilter,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'المندوب', isDense: true),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('الكل')),
                              ...agentOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))),
                            ],
                            onChanged: (v) => setState(() => _agentFilter = v),
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              if (_selected.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  child: Row(children: [
                    Text('${_selected.length} محدد', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _bulkDelete,
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('حذف', style: TextStyle(color: Colors.red)),
                    ),
                  ]),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('لا توجد عمليات مطابقة'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final s = filtered[i];
                          final canModify = canModifySale(s, profileAsync.value);
                          final selected = _selected.contains(s.id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: canModify
                                  ? Checkbox(
                                      value: selected,
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          _selected.add(s.id);
                                        } else {
                                          _selected.remove(s.id);
                                        }
                                      }),
                                    )
                                  : null,
                              title: Text(s.customerName ?? s.buyerName ?? s.cardUsername ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              subtitle: Text('${s.packageName} · ${s.networkName} · #${s.transactionNo}', style: const TextStyle(fontSize: 11)),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtMoney(s.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  if (canModify)
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      onPressed: () => _openEdit(s, isAdmin),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
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
