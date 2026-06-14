import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';

// ✅ IMPORT YOUR REPOSITORY AND PROVIDERS
import '../features/trips/trip_repository.dart';
import '../features/trips/trip_provider.dart';
import '../features/trips/itinerary_provider.dart';

// 1. STATE: Who is the current user?
final userProvider = StreamProvider<User?>((ref) {
  return SupabaseService.client.auth.onAuthStateChange.map((state) => state.session?.user);
});

// 2. SERVICE: The actions
class AuthService {
  final _supabase = SupabaseService.client;
  final Ref ref;

  AuthService(this.ref);

  // 📧 Sign Up (Pure Supabase)
  Future<void> signUp(String email, String password, String username) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
      },
      emailRedirectTo: 'journii://reset-callback',
    );

    if (response.user == null) {
      throw Exception("Sign up failed");
    }
  }

  // 🔑 Login
  Future<void> login(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw Exception("Login failed");
    }
  }

  // 🔄 Reset Password (NEW)
  Future<void> resetPassword(String email) async {
    await Supabase.instance.client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'journii://reset-callback',
    );
  }

  // 🚪 Logout (Cleans up Local Data + RAM)
  Future<void> logout() async {
    try {
      print("🧹 LOGOUT: Starting Cleanup...");

      // 1. WIPE THE DISK (Hive)
      await TripRepository().clearLocalData();
      print("✅ Disk Wiped.");

      // 2. WIPE THE RAM (Riverpod State)
      // This forces the app to destroy the old lists immediately.
      ref.invalidate(tripProvider);
      ref.invalidate(itineraryProvider);
      print("✅ RAM Wiped (Providers Invalidated).");

    } catch (e) {
      print("⚠️ Error clearing data: $e");
    }

    // 3. NOW SIGN OUT FROM SUPABASE
    await _supabase.auth.signOut();
  }
}

// 3. PROVIDER: Access the service anywhere
final authServiceProvider = Provider((ref) => AuthService(ref));