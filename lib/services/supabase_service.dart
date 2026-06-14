import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static Future<void> initialize() async {
    // 1. Read keys from .env
    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

    // 2. Safety Check
    if (url == null || anonKey == null) {
      print("⚠️ CRITICAL ERROR: Supabase keys missing in .env file!");
      return;
    }

    // 3. Initialize
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    print("✅ Supabase Connected Successfully (Secure Mode)!");
  }

  static SupabaseClient get client => Supabase.instance.client;
}