// نفس تصميم src/routes/app.cabin.tsx — بطاقات باقات ملوّنة (كروت المندوب
// المسحوبة)، اختيار/بحث/إنشاء زبون، بيع إلزامي بربط الزبون، مشاركة الفاتورة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/format.dart';
import '../../services/pick_contact.dart';
import 'cabin_providers.dart';

class CabinScreen extends ConsumerWidget {
  const CabinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(cabinRowsProvider);
    final customersAsync = ref.watch(myCustomersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('كبينة البيع'),
        actions: [
          TextButton.icon(
            onPressed: () => _openCustomersSheet(context, ref),
            icon: const Icon(Icons.people_outline, size: 18),
            label: Text('الزبائن (${customersAsync.value?.length ?? 0})'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(cabinRowsProvider),
        child: rowsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
          data: (allRows) {
            final rows = allRows.where((r) => r.available > 0).toList();
            final totalAvail = allRows.fold<int>(0, (s, r) => s + r.available);
            final totalSold = allRows.fold<int>(0, (s, r) => s + r.soldCount);
            final totalValue = allRows.fold<num>(0, (s, r) => s + r.available * r.price);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Expanded(child: _StatMini(label: 'متوفر', value: '$totalAvail', color: Colors.green)),
                  const SizedBox(width: 8),
                  Expanded(child: _StatMini(label: 'مباع', value: '$totalSold', color: Colors.orange)),
                  const SizedBox(width: 8),
                  Expanded(child: _StatMini(label: 'قيمة المتاح', value: fmtMoney(totalValue), color: Theme.of(context).colorScheme.primary)),
                ]),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(children: [
                      Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('لا توجد كروت متاحة في كبينتك.'),
                      const SizedBox(height: 4),
                      Text('اذهب إلى الشبكات واطلب كروت من المدير.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ]),
                  )
                else
                  ...rows.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CabinPackageCard(row: r, onSell: () => _startSellFlow(context, ref, r)),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openCustomersSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _CustomersManageSheet(),
    );
  }

  Future<void> _startSellFlow(BuildContext context, WidgetRef ref, CabinRow row) async {
    final customer = await showModalBottomSheet<CabinCustomer>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _CustomerPickerSheet(),
    );
    if (customer == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد البيع'),
        content: Text('بيع كرت من "${row.packageName}" بسعر ${fmtMoney(row.price)} للزبون "${customer.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await sellFromCabin(packageId: row.packageId, customer: customer);
      ref.invalidate(cabinRowsProvider);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: const [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('تمت عملية البيع')]),
          content: SelectableText(result.shareText(row.networkName)),
          actions: [
            TextButton.icon(
              onPressed: () => Share.share(result.shareText(row.networkName), subject: 'تفاصيل البيع'),
              icon: const Icon(Icons.share_outlined, size: 16),
              label: const Text('مشاركة'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatMini({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color), textDirection: TextDirection.ltr),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }
}

class _CabinPackageCard extends StatelessWidget {
  final CabinRow row;
  final VoidCallback onSell;
  const _CabinPackageCard({required this.row, required this.onSell});

  Color? get _bgColor {
    if (row.color == null) return null;
    try {
      return Color(int.parse(row.color!.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bgColor;
    final isColored = bg != null;
    final fg = isColored ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final sub = isColored ? Colors.white70 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isColored ? LinearGradient(colors: [bg, bg.withValues(alpha: 0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: isColored ? null : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: isColored ? null : Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.packageName, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
                  Text(row.networkName, style: TextStyle(fontSize: 11, color: sub)),
                ],
              ),
            ),
            Text(fmtMoney(row.price), style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.inventory_2_outlined, size: 14, color: fg),
            const SizedBox(width: 4),
            Text('متوفر: ${row.available}', style: TextStyle(fontSize: 12, color: fg)),
            const SizedBox(width: 12),
            Icon(Icons.check_circle_outline, size: 14, color: fg),
            const SizedBox(width: 4),
            Text('مباع: ${row.soldCount}', style: TextStyle(fontSize: 12, color: fg)),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onSell,
            icon: const Icon(Icons.point_of_sale_outlined, size: 16),
            label: const Text('بيع'),
            style: FilledButton.styleFrom(backgroundColor: isColored ? Colors.white : null, foregroundColor: isColored ? bg : null),
          ),
        ],
      ),
    );
  }
}

/// ورقة اختيار زبون قبل البيع — بحث + إنشاء زبون جديد سريع.
class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  String _search = '';
  bool _adding = false;
  final _nameCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final c = await createCustomer(name: _nameCtrl.text, whatsapp: _waCtrl.text);
      ref.invalidate(myCustomersProvider);
      if (!mounted) return;
      if (c != null) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(myCustomersProvider);
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('اختر الزبون', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            if (!_adding) ...[
              TextField(
                decoration: const InputDecoration(labelText: 'بحث بالاسم أو واتساب', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() => _adding = true),
                icon: const Icon(Icons.person_add_outlined, size: 16),
                label: const Text('زبون جديد'),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: customersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('$e'),
                  data: (customers) {
                    final q = _search.trim().toLowerCase();
                    final filtered = q.isEmpty ? customers : customers.where((c) => c.name.toLowerCase().contains(q) || c.whatsapp.contains(q)).toList();
                    if (filtered.isEmpty) return const Center(child: Text('لا يوجد زبائن مطابقين'));
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        return ListTile(
                          title: Text(c.name),
                          subtitle: Text(c.whatsapp, textDirection: TextDirection.ltr),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    );
                  },
                ),
              ),
            ] else ...[
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await pickContact();
                      if (result.ok && result.contact != null) {
                        setState(() {
                          _nameCtrl.text = result.contact!.name;
                          _waCtrl.text = result.contact!.phone;
                        });
                      } else if (result.message != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message!)));
                      }
                    },
                    icon: const Icon(Icons.contacts_outlined, size: 16),
                    label: const Text('اختيار من جهات الاتصال'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'اسم الزبون')),
              const SizedBox(height: 10),
              TextField(controller: _waCtrl, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم واتساب')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => setState(() => _adding = false), child: const Text('رجوع'))),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _create,
                    child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('إضافة واختيار'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// ورقة إدارة الزبائن (عرض/حذف) — من زر "الزبائن" بالأعلى.
class _CustomersManageSheet extends ConsumerWidget {
  const _CustomersManageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(myCustomersProvider);
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('زبائني', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
                data: (customers) {
                  if (customers.isEmpty) return const Center(child: Text('لا يوجد زبائن بعد'));
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, i) {
                      final c = customers[i];
                      return ListTile(
                        title: Text(c.name),
                        subtitle: Text(c.whatsapp, textDirection: TextDirection.ltr),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('حذف الزبون'),
                                content: Text('حذف حساب "${c.name}"؟ المبيعات السابقة تبقى كما هي.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await deleteCustomer(c.id);
                              ref.invalidate(myCustomersProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف حساب الزبون مع بقاء المبيعات كما هي')));
                              }
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الزبون: $e')));
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
