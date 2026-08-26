import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

/// تهيئة Supabase مرة واحدة عند بدء التطبيق (استدعِها في main() قبل runApp).
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
}

/// اختصار سريع للوصول للعميل من أي مكان بالتطبيق.
SupabaseClient get supabase => Supabase.instance.client;
