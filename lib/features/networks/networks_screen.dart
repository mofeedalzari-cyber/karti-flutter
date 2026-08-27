// نفس تصميم src/routes/app.networks.index.tsx — قائمة بطاقات الشبكات مع
// عدّاد الباقات/المتاح/المباع/القيمة، وإضافة/تعديل/حذف للمدير والسوبر أدمن.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';
import 'networks_providers.dart';

class NetworksScreen extends ConsumerWidget {
  const NetworksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (profile) {
        final canCreate = profile?.isAdminOrAbove ?? false;
        return _NetworksBody(canCreate: canCreate, isSuperadmin: profile?.isSuperadmin ?? false);
      },
    );
  }
}

class _NetworksBody extends ConsumerWidget {
  final bool canCreate;
  final bool isSuperadmin;
  const _NetworksBody({required this.canCreate, required this.isSuperadmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(networksListProvider);
    final countsAsync = ref.watch(networkCountsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networksListProvider);
        ref.invalidate(networkCountsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('الشبكات',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (canCreate)
                FilledButton.icon(
                  onPressed: () => _openForm(context, ref, editing: null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('شبكة جديدة'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(canCreate ? 'إدارة شبكات الإنترنت المتاحة' : 'الشبكات المتاحة للبيع',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          networksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('تعذر التحميل: $e', style: const TextStyle(color: Colors.red)),
            data: (networks) {
              if (networks.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(children: [
                    Icon(Icons.wifi_off, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('لا توجد شبكات بعد.'),
                  ]),
                );
              }
              final counts = countsAsync.value ?? {};
              return Column(
                children: networks
                    .map((n) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _NetworkCard(
                            network: n,
                            counts: counts[n.id] ?? const NetworkCounts(),
                            canManage: canCreate,
                            onEdit: () => _openForm(context, ref, editing: n),
                            onDelete: () => _confirmDelete(context, ref, n),
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

  void _openForm(BuildContext context, WidgetRef ref, {required NetworkModel? editing}) {
    showDialog(
      context: context,
      builder: (ctx) => _NetworkFormDialog(editing: editing, isSuperadmin: isSuperadmin),
    ).then((_) {
      ref.invalidate(networksListProvider);
      ref.invalidate(networkCountsProvider);
    });
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, NetworkModel n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الشبكة'),
        content: Text('حذف "${n.name}"؟ سيتم حذف كل البيانات المرتبطة بها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await deleteNetwork(n.id);
                ref.invalidate(networksListProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final NetworkModel network;
  final NetworkCounts counts;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NetworkCard({
    required this.network,
    required this.counts,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF009688);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = _parseColor(network.primaryColor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.wifi, color: primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(network.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      if (network.description != null)
                        Text(network.description!,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (!network.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(999)),
                    child: const Text('معطّلة', style: TextStyle(fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _MiniStat(label: 'الباقات', value: '${counts.packages}')),
                Expanded(child: _MiniStat(label: 'المتاح', value: '${counts.available}')),
                Expanded(child: _MiniStat(label: 'المباع', value: '${counts.sold}')),
                Expanded(child: _MiniStat(label: 'القيمة', value: fmtMoney(counts.value))),
              ],
            ),
            if (canManage) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('تعديل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onDelete, child: const Icon(Icons.delete_outline, size: 16)),
                ],
              ),
            ],
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
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), textDirection: TextDirection.ltr),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _NetworkFormDialog extends ConsumerStatefulWidget {
  final NetworkModel? editing;
  final bool isSuperadmin;
  const _NetworkFormDialog({required this.editing, required this.isSuperadmin});

  @override
  ConsumerState<_NetworkFormDialog> createState() => _NetworkFormDialogState();
}

class _NetworkFormDialogState extends ConsumerState<_NetworkFormDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _currency = TextEditingController(text: 'ر.س');
  String _primaryColor = '#009688';
  String _secondaryColor = '#14B8A6';
  bool _isActive = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _description.text = e.description ?? '';
      _currency.text = e.currency;
      _primaryColor = e.primaryColor;
      _secondaryColor = e.secondaryColor;
      _isActive = e.isActive;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم مطلوب')));
      return;
    }
    setState(() => _busy = true);
    try {
      final form = NetworkModel(
        id: widget.editing?.id ?? '',
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        currency: _currency.text.trim().isEmpty ? 'ر.س' : _currency.text.trim(),
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        isActive: _isActive,
        createdAt: '',
      );
      await saveNetwork(form: form, editingId: widget.editing?.id, isSuperadmin: widget.isSuperadmin);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing != null ? 'تعديل شبكة' : 'شبكة جديدة'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الشبكة')),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
              ),
              const SizedBox(height: 10),
              TextField(controller: _currency, decoration: const InputDecoration(labelText: 'العملة')),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نشطة'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
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
