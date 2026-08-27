import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../dashboard/role_dashboard.dart';
import '../packages/packages_screen.dart';
import '../networks/networks_screen.dart';
import '../requests/requests_screen.dart';
import '../cards/cards_upload_screen.dart';
import '../manage_cards/manage_cards_screen.dart';
import '../auth/profile_provider.dart';
import '../auth/auth_controller.dart';

/// القالب الرئيسي — شريط تنقل سفلي (نفس عناصر النسخة الحالية: الرئيسية،
/// الشبكات، الباقات، الطلبات) + قائمة جانبية لأدوات المدير (رفع الكروت،
/// إدارة الكروت). باقي الصفحات تُضاف تباعاً بالمراحل القادمة.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _screens = [
    RoleDashboard(),
    NetworksScreen(),
    PackagesScreen(),
    RequestsScreen(),
  ];

  static const _titles = ['كرتي', 'الشبكات', 'الباقات', 'الطلبات'];

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final isAdmin = profileAsync.value?.isAdminOrAbove ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const DrawerHeader(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('كرتي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_outlined),
                title: const Text('الزبائن'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/app/customers');
                },
              ),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('كبينة البيع'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/app/cabin');
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('المبيعات'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/app/sales');
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('المدفوعات'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/payments');
                  },
                ),
              if (isAdmin) ...[
                ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: const Text('أجهزة مايكروتك'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/mikrotiks');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('المناديب'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/agents');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_outlined),
                  title: const Text('طلبات الانضمام'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/join-requests');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('حسابات المناديب'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/agent-accounts');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('رفع الكروت'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const Scaffold(
                        body: SafeArea(child: CardsUploadScreen()),
                      ),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('إدارة الكروت'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const Scaffold(body: SafeArea(child: ManageCardsScreen())),
                    ));
                  },
                ),
                const Divider(),
              ],
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('الإعدادات'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/app/settings');
                },
              ),
              if (isAdmin) ...[
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('سجل النشاط'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/logs');
                  },
                ),
              ],
              if (profileAsync.value?.isSuperadmin == true) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('لوحة السوبر أدمن'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/superadmin');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_reset_outlined),
                  title: const Text('استعادة كلمة المرور'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/app/password-resets');
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/');
                },
              ),
            ],
          ),
        ),
      ),
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.wifi_outlined), selectedIcon: Icon(Icons.wifi), label: 'الشبكات'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'الباقات'),
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'الطلبات'),
        ],
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('صفحة "$title" — قيد البناء بالمرحلة القادمة',
              style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
