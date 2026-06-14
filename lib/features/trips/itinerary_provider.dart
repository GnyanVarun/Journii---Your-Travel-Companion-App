import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'itinerary_item_model.dart';
import 'trip_repository.dart';

final itineraryProvider =
StateNotifierProvider<ItineraryNotifier, List<ItineraryItem>>(
      (ref) => ItineraryNotifier(),
);

// Fetch the events added via the "Add to Itinerary" button
// Change FutureProvider to StreamProvider
final savedEventsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, tripId) {
  return Supabase.instance.client
      .from('itinerary_events')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId);
});

class ItineraryNotifier extends StateNotifier<List<ItineraryItem>> {
  final Box<ItineraryItem> box = Hive.box<ItineraryItem>('itinerary');

  ItineraryNotifier()
      : super(Hive.box<ItineraryItem>('itinerary').values.toList());

  /// --------------------------------------------------
  /// 📦 READ HELPERS
  /// --------------------------------------------------
  List<ItineraryItem> itineraryForTrip(String tripId) {
    return state.where((item) => item.tripId == tripId).toList();
  }

  /// --------------------------------------------------
  /// ☁️ SYNC FROM CLOUD (MIRROR MODE - FIXES DUPLICATES)
  /// --------------------------------------------------
  Future<void> syncFromCloud(String tripId) async {
    try {
      print("☁️ Syncing Trip $tripId from cloud...");

      // 1. Fetch the source of truth from Supabase
      final cloudItems = await TripRepository().fetchItineraryItems(tripId);

      // 2. 🧹 CLEAR LOCAL CACHE FOR THIS TRIP
      // This deletes the 6 duplicate items locally so we can save the correct 3.
      final keysToDelete = box.keys.where((key) {
        final item = box.get(key);
        return item?.tripId == tripId;
      }).toList();

      await box.deleteAll(keysToDelete);

      // 3. SAVE FRESH DATA
      if (cloudItems.isNotEmpty) {
        for (final item in cloudItems) {
          await box.put(item.id, item);
        }
        print("✅ Synced ${cloudItems.length} items (Mirror Mode).");
      } else {
        print("☁️ Trip is empty in the cloud.");
      }

      // 4. Update UI State
      state = box.values.toList();
      normalizeDaysForTrip(tripId);

    } catch (e) {
      print("⚠️ Sync Failed: $e");
    }
  }

  /// --------------------------------------------------
  /// ➕ ADD / ✏️ UPDATE / ❌ DELETE
  /// --------------------------------------------------

  Future<void> addItem(ItineraryItem item, {bool syncToCloud = true}) async {
    if (syncToCloud) {
      await TripRepository().saveItineraryItems([item]);
    }
    await box.put(item.id, item);
    state = [...state, item];
  }

  Future<void> updateItem(ItineraryItem updatedItem) async {
    await TripRepository().saveItineraryItems([updatedItem]);
    await box.put(updatedItem.id, updatedItem);

    state = [
      for (final item in state)
        if (item.id == updatedItem.id) updatedItem else item,
    ];
  }

  Future<void> deleteItem(String id) async {
    try {
      await Supabase.instance.client
          .from('itinerary_items')
          .delete()
          .eq('id', id);
    } catch (e) {
      print("⚠️ Cloud delete failed: $e");
    }
    await box.delete(id);
    state = state.where((item) => item.id != id).toList();
  }

  Future<void> deleteForTrip(String tripId) async {
    try {
      await Supabase.instance.client
          .from('itinerary_items')
          .delete()
          .eq('trip_id', tripId);
    } catch (e) {
      print("⚠️ Cloud delete failed: $e");
    }

    final keysToDelete = box.keys.where((key) {
      final item = box.get(key);
      return item?.tripId == tripId;
    }).toList();

    await box.deleteAll(keysToDelete);
    state = state.where((item) => item.tripId != tripId).toList();
  }

  /// --------------------------------------------------
  /// ⭐ REPLACE UNLOCKED AI ITEMS (THE FIX)
  /// --------------------------------------------------

  Future<void> replaceUnlockedForTrip({
    required String tripId,
    required List<ItineraryItem> newItems,
  }) async {
    // 1. Identify OLD items to remove (Locally)
    final itemsToRemove = state
        .where((item) => item.tripId == tripId && !item.isLocked)
        .toList();

    final idsToRemove = itemsToRemove.map((e) => e.id).toList();

    print("🗑️ Replacing: Removing ${idsToRemove.length} old items from Cloud...");

    // 2. 🔴 CRITICAL FIX: Delete OLD items from Cloud
    if (idsToRemove.isNotEmpty) {
      try {
        await Supabase.instance.client
            .from('itinerary_items') // ⚠️ Ensure this matches your table name
            .delete()
            .filter('id', 'in', idsToRemove); // ✅ FIXED: Replaced .in_() with .filter()
      } catch (e) {
        print("⚠️ Failed to delete old items from cloud: $e");
      }
    }

    // 3. Delete OLD items from Local (Hive)
    final keysToDelete = box.keys.where((key) {
      final item = box.get(key);
      return item != null && idsToRemove.contains(item.id);
    }).toList();

    await box.deleteAll(keysToDelete);

    // 4. Save NEW items to Cloud
    await TripRepository().saveItineraryItems(newItems);

    // 5. Save NEW items to Hive
    for (var item in newItems) {
      await box.put(item.id, item);
    }

    // 6. Update State
    state = box.values.toList();
    normalizeDaysForTrip(tripId);
  }

  void normalizeDaysForTrip(String tripId) {
    final items = state
        .where((i) => i.tripId == tripId)
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));
  }

  /// --------------------------------------------------
  /// 🧭 STATUS MANAGEMENT
  /// --------------------------------------------------

  Future<void> updateStatus({
    required String itemId,
    required ItineraryStatus status,
  }) async {
    final item = box.get(itemId);
    if (item == null) return;

    final updated = item.copyWith(status: status);
    await TripRepository().saveItineraryItems([updated]);
    await box.put(updated.id, updated);

    state = [
      for (final i in state)
        if (i.id == itemId) updated else i,
    ];
  }

  void skipItem(String itemId) {
    updateStatus(itemId: itemId, status: ItineraryStatus.skipped);
  }

  void restoreItem(String itemId) {
    updateStatus(itemId: itemId, status: ItineraryStatus.planned);
  }

  ItineraryItem? _findNextPlannedItem(ItineraryItem completedItem) {
    final sameDayItems = state
        .where((i) =>
    i.tripId == completedItem.tripId && i.day == completedItem.day)
        .toList();

    final currentIndex =
    sameDayItems.indexWhere((i) => i.id == completedItem.id);

    if (currentIndex == -1) return null;

    for (int i = currentIndex + 1; i < sameDayItems.length; i++) {
      final item = sameDayItems[i];
      if (item.status == ItineraryStatus.planned) {
        return item;
      }
    }
    return null;
  }

  Future<ItineraryItem?> markCompleted(String itemId) async {
    final item = box.get(itemId);
    if (item == null) return null;

    final updated = item.copyWith(status: ItineraryStatus.completed);
    await TripRepository().saveItineraryItems([updated]);
    await box.put(updated.id, updated);

    state = [
      for (final i in state)
        if (i.id == itemId) updated else i,
    ];

    return _findNextPlannedItem(updated);
  }

  Future<void> moveItemToDay({
    required String itemId,
    required int newDay,
  }) async {
    final item = box.get(itemId);
    if (item == null) return;

    final updated = item.copyWith(day: newDay);
    await TripRepository().saveItineraryItems([updated]);
    await box.put(updated.id, updated);

    state = [
      for (final i in state)
        if (i.id == itemId) updated else i,
    ];
  }
}

final selectedDayProvider = StateProvider.autoDispose<int>((ref) => 0);