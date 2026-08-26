// نفس مفهوم src/routes/app.mikrotiks.tsx لكن الاتصال يصير من الجوال مباشرة
// عبر RouterOSApi (بروتوكول ثنائي) بدل REST — يعمل مع RouterOS v6 وv7، ومن
// نفس الشبكة المحلية أو عبر الإنترنت لو الجهاز عنده IP عام/Port Forward.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/routeros_api.dart';
import '../../services/supabase_service.dart';
import 'mikrotik_providers.dart';

class MikrotikScreen extends ConsumerWidget {
  const MikrotikScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(mikrotiksListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('أجهزة مايكروتك'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _openForm(context, ref, editing: null)),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
        data: (devices) {
          if (devices.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.router_outlined, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('لا توجد أجهزة مضافة بعد.'),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: () => _openForm(context, ref, editing: null), icon: const Icon(Icons.add, size: 16), label: const Text('إضافة جهاز')),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            itemBuilder: (context, i) {
              final d = devices[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${d.host}:${d.port}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(context, ref, editing: d)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('حذف الجهاز'),
                            content: Text('حذف "${d.name}"؟'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                              FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await deleteMikrotik(d.id);
                          ref.invalidate(mikrotiksListProvider);
                        }
                      },
                    ),
                  ]),
                  onTap: () => showDialog(context: context, builder: (ctx) => _MikrotikDetailDialog(device: d)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref, {required MikrotikDevice? editing}) {
    showDialog(context: context, builder: (ctx) => _MikrotikFormDialog(editing: editing)).then((_) => ref.invalidate(mikrotiksListProvider));
  }
}

class _MikrotikFormDialog extends ConsumerStatefulWidget {
  final MikrotikDevice? editing;
  const _MikrotikFormDialog({required this.editing});

  @override
  ConsumerState<_MikrotikFormDialog> createState() => _MikrotikFormDialogState();
}

class _MikrotikFormDialogState extends ConsumerState<_MikrotikFormDialog> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _port = TextEditingController(text: '8728');
  bool _useSsl = false;
  bool _busy = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _host.text = e.host;
      _username.text = e.username;
      _port.text = e.port.toString();
      _useSsl = e.useSsl;
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final r = await testMikrotikConnection(
        host: _host.text.trim(),
        port: int.tryParse(_port.text) ?? 8728,
        username: _username.text.trim(),
        password: _password.text,
        useSsl: _useSsl,
      );
      setState(() => _testResult = '✅ نجح الاتصال — الجهاز: ${r['identity']}');
    } catch (e) {
      setState(() => _testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _host.text.trim().isEmpty || _username.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم والعنوان واسم المستخدم مطلوبة')));
      return;
    }
    setState(() => _busy = true);
    try {
      // نحتاج network_id — نستخدم أول شبكة للمدير الحالي (مطابق لمنطق admin_network)
      final networkId = await _resolveNetworkId();
      await saveMikrotik(
        networkId: networkId,
        name: _name.text,
        host: _host.text,
        username: _username.text,
        password: _password.text.isEmpty ? null : _password.text,
        port: int.tryParse(_port.text) ?? 8728,
        useSsl: _useSsl,
        editingId: widget.editing?.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _resolveNetworkId() async {
    if (widget.editing != null) return widget.editing!.networkId;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('يجب تسجيل الدخول');
    final prof = await supabase.from('profiles').select('network_id').eq('id', uid).maybeSingle();
    final netId = prof?['network_id'] as String?;
    if (netId == null) throw Exception('لا توجد شبكة مرتبطة بحسابك');
    return netId;
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _username, _password, _port]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing != null ? 'تعديل جهاز' : 'إضافة جهاز ميكروتك'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الجهاز')),
              const SizedBox(height: 10),
              TextField(controller: _host, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'العنوان (IP)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _username, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'اسم المستخدم'))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المنفذ'))),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: widget.editing != null ? 'كلمة المرور (اتركها فارغة للإبقاء على القديمة)' : 'كلمة المرور'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('استخدام SSL (api-ssl)'),
                subtitle: const Text('فعّل لو خدمة api-ssl مُشغّلة بدل api العادية', style: TextStyle(fontSize: 11)),
                value: _useSsl,
                onChanged: (v) => setState(() => _useSsl = v),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering, size: 16),
                label: const Text('اختبار الاتصال'),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(_testResult!, style: TextStyle(fontSize: 12, color: _testResult!.startsWith('✅') ? Colors.green : Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
        ),
      ],
    );
  }
}

class _MikrotikDetailDialog extends StatelessWidget {
  final MikrotikDevice device;
  const _MikrotikDetailDialog({required this.device});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 500,
        height: 600,
        child: DefaultTabController(
          length: 4,
          child: Column(
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text(device.name),
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
                bottom: const TabBar(tabs: [Tab(text: 'عامة'), Tab(text: 'النشطون'), Tab(text: 'الكروت'), Tab(text: 'الباقات')]),
              ),
              Expanded(
                child: TabBarView(children: [
                  _OverviewTab(device: device),
                  _ActiveTab(device: device),
                  _UsersTab(device: device),
                  _ProfilesTab(device: device),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorBox({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('تعذّر الاتصال بالميكروتيك', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.orange.shade800)),
        const SizedBox(height: 6),
        Text('$error', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 14), label: const Text('إعادة المحاولة')),
      ]),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  final MikrotikDevice device;
  const _OverviewTab({required this.device});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Future<Map<String, String>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = withMikrotik(widget.device, (api) async {
      final res = await api.talk('/system/resource/print');
      final idn = await api.talk('/system/identity/print');
      final r = res.isNotEmpty ? res.first : <String, String>{};
      final i = idn.isNotEmpty ? idn.first : <String, String>{};
      return {
        'identity': i['name'] ?? '',
        'version': r['version'] ?? '',
        'board': r['board-name'] ?? '',
        'uptime': r['uptime'] ?? '',
        'cpu': r['cpu-load'] ?? '',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return _ErrorBox(error: snap.error!, onRetry: () => setState(_load));
        final d = snap.data!;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2,
            children: [
              _Stat('اسم الجهاز', d['identity'] ?? '—'),
              _Stat('الإصدار', d['version'] ?? '—'),
              _Stat('اللوحة', d['board'] ?? '—'),
              _Stat('مدة التشغيل', d['uptime'] ?? '—'),
              _Stat('حمل المعالج', '${d['cpu'] ?? '—'}%'),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), textDirection: TextDirection.ltr),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ]),
    );
  }
}

class _ActiveTab extends StatefulWidget {
  final MikrotikDevice device;
  const _ActiveTab({required this.device});

  @override
  State<_ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends State<_ActiveTab> {
  Future<List<Map<String, String>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = withMikrotik(widget.device, (api) => api.talk('/ip/hotspot/active/print'));

  Future<void> _kick(String id) async {
    await withMikrotik(widget.device, (api) => api.talk('/ip/hotspot/active/remove', ['=.id=$id']));
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, String>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return _ErrorBox(error: snap.error!, onRetry: () => setState(_load));
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لا يوجد مستخدمون نشطون'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final u = list[i];
            return ListTile(
              dense: true,
              title: Text(u['user'] ?? '—', textDirection: TextDirection.ltr),
              subtitle: Text('IP: ${u['address'] ?? '—'}', style: const TextStyle(fontSize: 10), textDirection: TextDirection.ltr),
              trailing: IconButton(icon: const Icon(Icons.logout, size: 16, color: Colors.red), onPressed: () => _kick(u['.id'] ?? '')),
            );
          },
        );
      },
    );
  }
}

class _UsersTab extends StatefulWidget {
  final MikrotikDevice device;
  const _UsersTab({required this.device});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  Future<List<Map<String, String>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = withMikrotik(widget.device, (api) => api.talk('/ip/hotspot/user/print'));

  Future<void> _delete(String id) async {
    await withMikrotik(widget.device, (api) => api.talk('/ip/hotspot/user/remove', ['=.id=$id']));
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, String>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return _ErrorBox(error: snap.error!, onRetry: () => setState(_load));
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لا توجد كروت'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final u = list[i];
            return ListTile(
              dense: true,
              title: Text(u['name'] ?? '—', textDirection: TextDirection.ltr),
              subtitle: Text('Profile: ${u['profile'] ?? 'default'}', style: const TextStyle(fontSize: 10), textDirection: TextDirection.ltr),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(u['.id'] ?? '')),
            );
          },
        );
      },
    );
  }
}

class _ProfilesTab extends StatefulWidget {
  final MikrotikDevice device;
  const _ProfilesTab({required this.device});

  @override
  State<_ProfilesTab> createState() => _ProfilesTabState();
}

class _ProfilesTabState extends State<_ProfilesTab> {
  Future<List<Map<String, String>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = withMikrotik(widget.device, (api) => api.talk('/ip/hotspot/user/profile/print'));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, String>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return _ErrorBox(error: snap.error!, onRetry: () => setState(_load));
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لا توجد باقات'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final p = list[i];
            return ListTile(
              dense: true,
              title: Text(p['name'] ?? '—', textDirection: TextDirection.ltr),
              subtitle: Text('Rate: ${p['rate-limit'] ?? '—'}', style: const TextStyle(fontSize: 10), textDirection: TextDirection.ltr),
            );
          },
        );
      },
    );
  }
}
