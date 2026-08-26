// نفس تصميم ومنطق register-agent.tsx و register-network.tsx — شاشة واحدة
// بمفتاح accountType، مطابقة لبطاقتي الاختيار بأعلى النموذج بالنسخة الأصلية.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'register_controller.dart';

class RegisterScreen extends StatefulWidget {
  final String initialAccountType; // "agent" أو "network"
  const RegisterScreen({super.key, this.initialAccountType = 'agent'});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late String _accountType = widget.initialAccountType;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _networkCtrl = TextEditingController(); // اسم الشبكة (وكيل) أو معرّفها (مندوب)
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  List<Map<String, dynamic>> _networks = [];
  String? _selectedNetworkId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_accountType == 'agent') _loadNetworks();
  }

  Future<void> _loadNetworks() async {
    try {
      final list = await listActiveNetworks();
      if (mounted) setState(() => _networks = list);
    } catch (_) {
      /* تجاهل — الحقل سيبقى فارغاً */
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final networkValue = _accountType == 'agent'
        ? (_networks.firstWhere((n) => n['id'] == _selectedNetworkId, orElse: () => {})['name'] as String? ?? '')
        : _networkCtrl.text;
    final error = await registerAccount(
      fullName: _nameCtrl.text,
      phone: _phoneCtrl.text,
      networkName: networkValue,
      password: _passCtrl.text,
      password2: _pass2Ctrl.text,
      accountType: _accountType,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إنشاء الحساب! سيتم تفعيله من قبل مدير الشبكة قبل البدء.')),
    );
    context.go('/');
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _networkCtrl, _passCtrl, _pass2Ctrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAgent = _accountType == 'agent';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('كرتي', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      )),
                  const SizedBox(height: 8),
                  const Text('إنشاء حساب جديد', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('يتم تفعيل الحساب بعد موافقة مدير الشبكة.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 24),

                  Row(children: [
                    Expanded(
                      child: _TypeCard(
                        icon: Icons.pedal_bike_outlined,
                        label: 'مندوب توزيع',
                        active: isAgent,
                        onTap: () => setState(() {
                          _accountType = 'agent';
                          if (_networks.isEmpty) _loadNetworks();
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TypeCard(
                        icon: Icons.share_outlined,
                        label: 'وكيل / مدير شبكة',
                        active: !isAgent,
                        onTap: () => setState(() => _accountType = 'network'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الرباعي')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'رقم الجوال'),
                  ),
                  const SizedBox(height: 12),
                  if (isAgent)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedNetworkId,
                      decoration: const InputDecoration(labelText: 'الشبكة التي تتبع لها'),
                      items: _networks
                          .map((n) => DropdownMenuItem(value: n['id'] as String, child: Text(n['name'] as String)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedNetworkId = v),
                    )
                  else
                    TextField(controller: _networkCtrl, decoration: const InputDecoration(labelText: 'اسم الشبكة')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass2Ctrl,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إنشاء الحساب'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => context.go('/'), child: const Text('لديك حساب؟ سجّل الدخول')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TypeCard({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? primary : Colors.transparent, width: 1.5),
        ),
        child: Column(children: [
          Icon(icon, color: active ? primary : Colors.grey.shade600),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? primary : Colors.grey.shade700)),
        ]),
      ),
    );
  }
}
