// نفس تصميم ومنطق src/routes/app.packages.tsx — بطاقات ملوّنة حسب لون
// الباقة، عدّاد "المتاح الآن"، ثلاث خانات (الصلاحية/الساعات/الحجم)، وأزرار
// تختلف حسب الدور (تعديل/حذف للمدير، طلب سحب/كبينة البيع للمندوب).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';
import 'package_model.dart';
import 'packages_providers.dart';

class PackagesScreen extends ConsumerWidget {
  const PackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (profile) {
        final canManage = profile?.isAdminOrAbove ?? false;
        return _PackagesBody(canManage: canManage, profile: profile);
      },
    );
  }
}

class _PackagesBody extends ConsumerWidget {
  final bool canManage;
  final Profile? profile;
  const _PackagesBody({required this.canManage, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(networksProvider);
    final packagesAsync = ref.watch(packagesProvider);
    final countsAsync = ref.watch(packageCountsProvider);
    final filterNet = ref.watch(packageNetworkFilterProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(packagesProvider);
        ref.invalidate(packageCountsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('الباقات',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => _openPackageForm(context, ref, editing: null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة باقة'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('إدارة كل الباقات عبر الشبكات',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 16),

          // تصفية حسب الشبكة
          networksAsync.when(
            data: (networks) => SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: filterNet,
                decoration: const InputDecoration(labelText: 'تصفية حسب الشبكة'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('كل الشبكات')),
                  ...networks.map((n) => DropdownMenuItem(value: n.id, child: Text(n.name))),
                ],
                onChanged: (v) => ref.read(packageNetworkFilterProvider.notifier).state = v,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          packagesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('تعذر تحميل الباقات: $e', style: const TextStyle(color: Colors.red)),
            ),
            data: (packages) {
              if (packages.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('لا توجد باقات بعد.'),
                      if (canManage) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _openPackageForm(context, ref, editing: null),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('إضافة أول باقة'),
                        ),
                      ],
                    ],
                  ),
                );
              }
              final networksMap = {
                for (final n in networksAsync.value ?? <NetworkLite>[]) n.id: n
              };
              final counts = countsAsync.value ?? {};
              return Column(
                children: packages
                    .map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PackageCard(
                            pkg: p,
                            networkName: networksMap[p.networkId]?.name ?? '—',
                            counts: counts[p.id] ?? const PackageCounts(),
                            canManage: canManage,
                            onEdit: () => _openPackageForm(context, ref, editing: p),
                            onDelete: () => _confirmDelete(context, ref, p),
                            onRequest: () => _openRequestSheet(context, ref, p, counts[p.id]),
                            onSell: () => _confirmSell(context, ref, p),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, PackageModel p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الباقة'),
        content: Text('حذف "${p.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await deletePackage(p.id);
              if (!context.mounted) return;
              if (result.outcome == DeleteOutcome.success) {
                ref.invalidate(packagesProvider);
                ref.invalidate(packageCountsProvider);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف')));
              } else if (result.outcome == DeleteOutcome.blockedByForeignKey) {
                _confirmDisableInstead(context, ref, p);
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(result.errorMessage ?? 'حدث خطأ')));
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _confirmDisableInstead(BuildContext context, WidgetRef ref, PackageModel p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لا يمكن الحذف'),
        content: Text(
            'لا يمكن حذف الباقة "${p.name}" لأنها مرتبطة بمبيعات سابقة.\n\nهل تريد تعطيلها بدلاً من الحذف؟ (ستختفي من قوائم البيع مع الحفاظ على سجل المبيعات)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await disablePackage(p.id);
              ref.invalidate(packagesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعطيل الباقة')));
              }
            },
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
  }

  void _openPackageForm(BuildContext context, WidgetRef ref, {required PackageModel? editing}) {
    showDialog(
      context: context,
      builder: (ctx) => _PackageFormDialog(editing: editing, isSuperadmin: profile?.isSuperadmin ?? false),
    ).then((_) {
      ref.invalidate(packagesProvider);
      ref.invalidate(packageCountsProvider);
    });
  }

  void _openRequestSheet(BuildContext context, WidgetRef ref, PackageModel p, PackageCounts? counts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RequestCardsSheet(pkg: p, available: counts?.available ?? 0),
    );
  }

  Future<void> _confirmSell(BuildContext context, WidgetRef ref, PackageModel p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بيع مباشر'),
        content: Text('سيتم سحب كرت متاح من باقة "${p.name}" وبيعه فوراً بسعر ${fmtMoney(p.price)}. متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد البيع')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await sellCard(p.id);
      ref.invalidate(packagesProvider);
      ref.invalidate(packageCountsProvider);
      if (!context.mounted) return;
      final networksMap = {for (final n in ref.read(networksProvider).value ?? <NetworkLite>[]) n.id: n};
      final networkName = networksMap[p.networkId]?.name ?? '';
      _showSaleResultDialog(context, result, networkName);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _showSaleResultDialog(BuildContext context, SaleResult result, String networkName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: const [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('تمت عملية البيع')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(result.shareText(networkName)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Share.share(result.shareText(networkName), subject: 'تفاصيل البيع'),
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('مشاركة'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final PackageModel pkg;
  final String networkName;
  final PackageCounts counts;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRequest;
  final VoidCallback onSell;

  const _PackageCard({
    required this.pkg,
    required this.networkName,
    required this.counts,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onRequest,
    required this.onSell,
  });

  Color? get _bgColor {
    if (pkg.color == null) return null;
    try {
      return Color(int.parse(pkg.color!.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bgColor;
    final isColored = bg != null;
    final fg = isColored ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final subFg = isColored ? Colors.white70 : Colors.grey.shade600;
    final primary = Theme.of(context).colorScheme.primary;
    final shortId = pkg.id.replaceAll('-', '').substring(0, 8).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isColored
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg, bg.withValues(alpha: 0.75)],
              )
            : null,
        color: isColored ? null : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: isColored ? null : Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isColored ? Colors.white.withValues(alpha: 0.2) : primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.layers_outlined, color: isColored ? Colors.white : primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('باقة ${pkg.name}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: fg),
                        overflow: TextOverflow.ellipsis),
                    Text(networkName, style: TextStyle(fontSize: 11, color: subFg)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isColored ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(fmtMoney(pkg.price),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: fg)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isColored ? Colors.white.withValues(alpha: 0.15) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المتاح الآن', style: TextStyle(fontSize: 13, color: subFg)),
                Text('${counts.available}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _FeatureTile(icon: Icons.event_available, value: pkg.validity ?? '—', label: 'الصلاحية', colored: isColored)),
              const SizedBox(width: 8),
              Expanded(child: _FeatureTile(icon: Icons.access_time, value: pkg.allowedTime ?? '—', label: 'الساعات', colored: isColored)),
              const SizedBox(width: 8),
              Expanded(child: _FeatureTile(icon: Icons.sd_storage_outlined, value: pkg.dataSize ?? '—', label: 'الحجم', colored: isColored)),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isColored ? Colors.white.withValues(alpha: 0.15) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('ID: $shortId',
                  style: TextStyle(fontSize: 10, color: subFg), textDirection: TextDirection.ltr),
            ),
          ),
          const SizedBox(height: 12),
          if (canManage)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('تعديل'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: isColored ? Colors.white54 : Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fg,
                    side: BorderSide(color: isColored ? Colors.white54 : Colors.grey.shade300),
                  ),
                  child: const Icon(Icons.delete_outline, size: 16),
                ),
              ],
            )
          else
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSell,
                  icon: const Icon(Icons.point_of_sale_outlined, size: 16),
                  label: const Text('بيع مباشر'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRequest,
                  icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                  label: const Text('طلب سحب'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fg,
                    side: BorderSide(color: isColored ? Colors.white54 : Colors.grey.shade300),
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool colored;
  const _FeatureTile({required this.icon, required this.value, required this.label, required this.colored});

  @override
  Widget build(BuildContext context) {
    final fg = colored ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final sub = colored ? Colors.white70 : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colored ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
          Text(label, style: TextStyle(fontSize: 9, color: sub)),
        ],
      ),
    );
  }
}

/// نافذة إضافة/تعديل باقة
class _PackageFormDialog extends ConsumerStatefulWidget {
  final PackageModel? editing;
  final bool isSuperadmin;
  const _PackageFormDialog({required this.editing, required this.isSuperadmin});

  @override
  ConsumerState<_PackageFormDialog> createState() => _PackageFormDialogState();
}

class _PackageFormDialogState extends ConsumerState<_PackageFormDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _dataSize = TextEditingController();
  final _speed = TextEditingController();
  final _validity = TextEditingController();
  final _allowedTime = TextEditingController();
  final _description = TextEditingController();
  String? _networkId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _price.text = e.price.toString();
      _dataSize.text = e.dataSize ?? '';
      _speed.text = e.speed ?? '';
      _validity.text = e.validity ?? '';
      _allowedTime.text = e.allowedTime ?? '';
      _description.text = e.description ?? '';
      _networkId = e.networkId;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _dataSize, _speed, _validity, _allowedTime, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم الباقة')));
      return;
    }
    if (_networkId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر الشبكة')));
      return;
    }
    setState(() => _busy = true);
    try {
      final form = PackageModel(
        id: widget.editing?.id ?? '',
        networkId: _networkId!,
        name: _name.text.trim(),
        price: num.tryParse(_price.text) ?? 0,
        dataSize: _dataSize.text.trim().isEmpty ? null : _dataSize.text.trim(),
        speed: _speed.text.trim().isEmpty ? null : _speed.text.trim(),
        validity: _validity.text.trim().isEmpty ? null : _validity.text.trim(),
        allowedTime: _allowedTime.text.trim().isEmpty ? null : _allowedTime.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      await savePackage(form: form, editingId: widget.editing?.id, isSuperadmin: widget.isSuperadmin);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(networksProvider);
    return AlertDialog(
      title: Text(widget.editing != null ? 'تعديل باقة' : 'إضافة باقة جديدة'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              networksAsync.when(
                data: (networks) => DropdownButtonFormField<String>(
                  initialValue: _networkId,
                  decoration: const InputDecoration(labelText: 'الشبكة'),
                  items: networks.map((n) => DropdownMenuItem(value: n.id, child: Text(n.name))).toList(),
                  onChanged: (v) => setState(() => _networkId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل الشبكات'),
              ),
              const SizedBox(height: 10),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الباقة')),
              const SizedBox(height: 10),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'السعر'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _dataSize, decoration: const InputDecoration(labelText: 'الحجم'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _speed, decoration: const InputDecoration(labelText: 'السرعة'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _validity, decoration: const InputDecoration(labelText: 'الصلاحية'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _allowedTime, decoration: const InputDecoration(labelText: 'الساعات المسموحة'))),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

/// ورقة طلب سحب الكروت (للمندوب)
class _RequestCardsSheet extends StatefulWidget {
  final PackageModel pkg;
  final int available;
  const _RequestCardsSheet({required this.pkg, required this.available});

  @override
  State<_RequestCardsSheet> createState() => _RequestCardsSheetState();
}

class _RequestCardsSheetState extends State<_RequestCardsSheet> {
  final _qtyCtrl = TextEditingController(text: '10');
  final _notesCtrl = TextEditingController();
  String _payment = 'CREDIT';
  bool _busy = false;

  Future<void> _submit() async {
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كمية غير صحيحة')));
      return;
    }
    if (qty > widget.available) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('لا يمكن الطلب أكثر من المتاح (${widget.available})، وأنت طلبت $qty')));
      return;
    }
    setState(() => _busy = true);
    final error = await requestCards(
      packageId: widget.pkg.id,
      quantity: qty,
      notes: _notesCtrl.text,
      paymentMethod: _payment,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // TODO(المرحلة 7): استدعاء إشعار notifyNewCardRequest عبر Render/Edge Function
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم إرسال الطلب — بانتظار موافقة المدير')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('طلب سحب — باقة ${widget.pkg.name}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('المتاح حالياً: ${widget.available}', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'الكمية'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'CREDIT', label: Text('آجل')),
              ButtonSegment(value: 'CASH', label: Text('نقدي')),
            ],
            selected: {_payment},
            onSelectionChanged: (s) => setState(() => _payment = s.first),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('إرسال الطلب'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
