import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  AccountType _accountType = AccountType.agent;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(authControllerProvider.notifier);
    final error = await controller.login(
      phoneOrUsername: _phoneCtrl.text,
      password: _passCtrl.text,
      accountType: _accountType,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      context.go('/app');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authControllerProvider).busy;

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
                  const SizedBox(height: 24),
                  Text('كرتي', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      )),
                  const SizedBox(height: 8),
                  Text('تسجيل الدخول', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 32),

                  // نوع الحساب: مندوب / مدير شبكة
                  SegmentedButton<AccountType>(
                    segments: const [
                      ButtonSegment(
                        value: AccountType.agent,
                        label: Text('مندوب توزيع'),
                        icon: Icon(Icons.person_outline),
                      ),
                      ButtonSegment(
                        value: AccountType.network,
                        label: Text('وكيل / مدير شبكة'),
                        icon: Icon(Icons.admin_panel_settings_outlined),
                      ),
                    ],
                    selected: {_accountType},
                    onSelectionChanged: (s) => setState(() => _accountType = s.first),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم الجوال',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => busy ? null : _submit(),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('دخول'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.push('/register-agent'),
                    child: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
