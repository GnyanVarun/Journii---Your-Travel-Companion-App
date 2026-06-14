import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/trips/trip_repository.dart';
import '../features/trips/itinerary_item_model.dart';
import '../features/trips/itinerary_provider.dart';

class SyncService {
  static final _supabase = Supabase.instance.client;

  // 🔄 SYNC EVERYTHING (Trips + Items)
  static Future<void> syncAll(WidgetRef ref) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    print("☁️ STARTING MASTER SYNC...");

    // 1. Sync TRIPS (Using your existing Repository)
    // This fills the Trip List
    await TripRepository().syncFromCloud();

    // 2. Sync ITINERARY ITEMS (The missing part!)
    // This fills the details INSIDE the trips
    final response = await _supabase
        .from('itinerary_items')
        .select()
        .eq('user_id', userId);

    final List<dynamic> data = response as List<dynamic>;

    if (data.isNotEmpty) {
      final cloudItems = data.map((json) => ItineraryItem.fromJson(json)).toList();

      // Update the Provider locally
      final notifier = ref.read(itineraryProvider.notifier);
      for (var item in cloudItems) {
        // syncToCloud: false ensures we don't re-upload what we just downloaded
        await notifier.addItem(item, syncToCloud: false);
      }
    }

    print("✅ MASTER SYNC COMPLETE: Trips and Itineraries loaded.");
  }
}