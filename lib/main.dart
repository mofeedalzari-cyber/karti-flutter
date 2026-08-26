import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'services/supabase_service.dart';
import 'services/push_notifications.dart';
import 'theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/shell/app_shell.dart';
import 'features/agents/agents_screen.dart';
import 'features/join_requests/join_requests_screen.dart';
import 'features/agent_accounts/agent_accounts_screen.dart';
import 'features/sales/sales_screen.dart';
import 'features/payments/payments_screen.dart';
import 'features/cabin/cabin_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/logs/logs_screen.dart';
import 'features/password_resets/password_resets_screen.dart';
import 'features/superadmin/superadmin_screen.dart';
import 'features/mikrotik/mikrotik_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  // لا تنتظر (await) تهيئة الإشعارات — لا يجب أن تُبطئ إقلاع التطبيق، ونفس
  // سلوك النسخة الأصلية (تُهيَّأ بالخلفية بمجرد جهوزية التوجيه).
  initPushNotifications(_router);
  runApp(const ProviderScope(child: KartiApp()));
}

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final loggedIn = supabase.auth.currentUser != null;
    final publicPaths = {'/', '/register-agent', '/register-network'};
    final isPublicPath = publicPaths.contains(state.matchedLocation);
    if (!loggedIn && !isPublicPath) return '/';
    if (loggedIn && state.matchedLocation == '/') return '/app';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register-agent', builder: (context, state) => const RegisterScreen(initialAccountType: 'agent')),
    GoRoute(path: '/register-network', builder: (context, state) => const RegisterScreen(initialAccountType: 'network')),
    GoRoute(path: '/app', builder: (context, state) => const AppShell()),
    GoRoute(path: '/app/agents', builder: (context, state) => const AgentsScreen()),
    GoRoute(path: '/app/join-requests', builder: (context, state) => const JoinRequestsScreen()),
    GoRoute(path: '/app/agent-accounts', builder: (context, state) => const AgentAccountsScreen()),
    GoRoute(path: '/app/sales', builder: (context, state) => const SalesScreen()),
    GoRoute(path: '/app/payments', builder: (context, state) => const PaymentsScreen()),
    GoRoute(path: '/app/cabin', builder: (context, state) => const CabinScreen()),
    GoRoute(path: '/app/customers', builder: (context, state) => const CustomersScreen()),
    GoRoute(path: '/app/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/app/logs', builder: (context, state) => const LogsScreen()),
    GoRoute(path: '/app/password-resets', builder: (context, state) => const PasswordResetsScreen()),
    GoRoute(path: '/app/superadmin', builder: (context, state) => const SuperadminScreen()),
    GoRoute(path: '/app/mikrotiks', builder: (context, state) => const MikrotikScreen()),
  ],
);

class KartiApp extends ConsumerWidget {
  const KartiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // إعادة تقييم مسار التوجيه تلقائياً عند تغيّر حالة الدخول
    ref.watch(authStateChangesProvider);

    return MaterialApp.router(
      title: 'كرتي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      routerConfig: _router,
    );
  }
}
