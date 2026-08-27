// نفس منطق src/routes/app.index.tsx → DashboardPage بالضبط:
// role === "admin" ? <AdminDashboard /> : <AgentHome />
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/profile_provider.dart';
import 'dashboard_screen.dart';
import 'agent_home_screen.dart';

class RoleDashboard extends ConsumerWidget {
  const RoleDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (profile) {
        final isAdmin = profile?.isAdminOrAbove ?? false;
        return isAdmin ? const DashboardScreen() : const AgentHomeScreen();
      },
    );
  }
}
