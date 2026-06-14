import 'package:journii/features/trips/chat_message_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'ai_itinerary_model.dart';
import 'trip_model.dart';
import 'trip_style.dart'; // Ensure this is imported
import 'itinerary_item_model.dart';
import '../../services/supabase_service.dart';
import '../../notifications/hype_notification_service.dart';

class TripRepository {
  final _supabase = SupabaseService.client;
  final Box<Trip> _localTrips = Hive.box<Trip>('trips');
  final Box<ItineraryItem> _localItems = Hive.box<ItineraryItem>('itinerary');

  // 🔄 1. SYNC FROM CLOUD
  Future<void> syncFromCloud() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final tripsData = await _supabase.from('trips').select().eq('user_id', user.id);

      for (final map in tripsData) {
        final start = DateTime.parse(map['start_date']);
        final end = DateTime.parse(map['end_date']);
        final days = end.difference(start).inDays + 1;

        // ✅ SAFE PARSING: Defaults to the first style in your list if match fails
        TripStyle style = TripStyle.values.first;
        if (map['trip_style'] != null) {
          try {
            style = TripStyle.values.firstWhere(
                    (e) => e.name.toLowerCase() == map['trip_style'].toString().toLowerCase(),
                orElse: () => TripStyle.values.first
            );
          } catch (_) {}
        }

        final trip = Trip(
          id: map['id'],
          title: map['title'],
          description: map['description'] ?? '',
          createdAt: DateTime.now(),
          startDate: start,
          endDate: end,
          durationDays: days,
          destination: map['destination'],
          userId: map['user_id'],
          curiosityLevel: map['curiosity_level'] ?? 2,
          style: style,
        );
        await _localTrips.put(trip.id, trip);
      }

      // Sync Items (Unchanged)
      final itemsData = await _supabase.from('itinerary_items').select().eq('user_id', user.id);
      for (final map in itemsData) {
        ItineraryStatus status = ItineraryStatus.planned;
        if (map['status'] == 'completed') status = ItineraryStatus.completed;
        if (map['status'] == 'skipped') status = ItineraryStatus.skipped;

        final item = ItineraryItem(
          id: map['id'],
          tripId: map['trip_id'],
          title: map['title'],
          description: map['description'] ?? '',
          day: map['day_number'],
          isAiGenerated: true,
          isLocked: false,
          latitude: map['latitude'],
          longitude: map['longitude'],
          status: status,
          visitTip: map['ai_insight'],
          category: map['category'],
        );
        await _localItems.put(item.id, item);
      }
      print("✅ Supabase Sync Complete.");

    } catch (e) {
      print("⚠️ Sync Error: $e");
    }
  }

  // 💾 2. CREATE / UPDATE TRIP
  Future<void> createTrip(Trip trip) async {
    await _supabase.from('trips').upsert(trip.toJson());
    await _localTrips.put(trip.id, trip);
    print("✅ Trip saved to Supabase & Local Storage.");

    // 🟢 FIRE UP THE NOTIFICATION ENGINE
    try {
      print("🚀 Attempting to breach Android AlarmManager...");

      // Convert String UUID to an integer safely for the notification package
      int notificationId = trip.id is int ? trip.id as int : trip.id.hashCode;

      String alertDestination = trip.destination != null && trip.destination!.isNotEmpty
          ? trip.destination!
          : trip.title;

      print("🕵️ DEBUG DESTINATION: ${trip.destination}");
      print("🕵️ DEBUG START DATE: ${trip.startDate}");
      print("🕵️ DEBUG END DATE: ${trip.endDate}");

      if (trip.startDate != null && trip.endDate != null) {

      await HypeNotificationService.scheduleTripNotifications(
        tripId: notificationId,
        destination: alertDestination,
        startDate: trip.startDate!,
        endDate: trip.endDate!,
      );
      print("✅ SUCCESS! Hype engine successfully wired to repository!");
    } else{
      print("⚠️ Notification skipped: Trip is missing a destination or dates.");
    }
} catch (e) {
      print("🚨 FATAL ALARM ERROR: $e");
    }
  }

  // 📍 3. SAVE ITEMS
  Future<void> saveItineraryItems(List<ItineraryItem> items) async {
    final user = _supabase.auth.currentUser;
    for (var item in items) {
      await _localItems.put(item.id, item);
      if (user != null) {
        await _supabase.from('itinerary_items').upsert({
          'id': item.id,
          'trip_id': item.tripId,
          'user_id': user.id,
          'day_number': item.day,
          'title': item.title,
          'description': item.description,
          'category': item.category,
          'ai_insight': item.visitTip,
          'latitude': item.latitude,
          'longitude': item.longitude,
          'status': item.status.name,
        });
      }
    }
  }

  // 🗑️ DELETE TRIP
  Future<void> deleteTrip(String tripId) async {
    await _localTrips.delete(tripId);
    if (Hive.isBoxOpen('chat_history')) {
      await Hive.box<List>('chat_history').delete(tripId);
    }
    try {
      await _supabase.from('messages').delete().eq('trip_id', tripId);
      await _supabase.from('itinerary_items').delete().eq('trip_id', tripId);
      await _supabase.from('trips').delete().eq('id', tripId);
    } catch (e) {
      print("⚠️ Error deleting from cloud: $e");
    }
  }

  // 💬 CHAT METHODS
  Future<List<ChatMessage>> fetchMessages(String tripId) async {
    try {
      final data = await _supabase
          .from('messages')
          .select()
          .eq('trip_id', tripId)
          .order('created_at', ascending: true);
      return (data as List).map((map) {
        return ChatMessage(
          id: map['id'],
          role: map['is_user'] == true ? ChatRole.user : ChatRole.ai,
          text: map['text'],
          timestamp: DateTime.parse(map['created_at']),
          itineraryPlaces: (map['meta_data'] as List?)?.map((x) => AIPlace.fromMap(x)).toList() ?? [],
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveMessage(ChatMessage msg, String tripId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final placesJson = msg.itineraryPlaces?.map((p) => {
      'name': p.name,
      'description': p.description,
      'day': p.day,
      'bestTime': p.bestTime,
      'visitTip': p.visitTip,
    }).toList();
    try {
      await _supabase.from('messages').insert({
        'id': msg.id,
        'trip_id': tripId,
        'user_id': user.id,
        'text': msg.text,
        'is_user': msg.role == ChatRole.user,
        'created_at': msg.timestamp.toIso8601String(),
        'meta_data': placesJson,
      });
    } catch (e) {
      print("⚠️ Save Message Error: $e");
    }
  }

  Future<List<ItineraryItem>> fetchItineraryItems(String tripId) async {
    try {
      final response = await _supabase.from('itinerary_items').select().eq('trip_id', tripId);
      if (response == null || (response as List).isEmpty) return [];
      return (response as List).map((map) {
        ItineraryStatus status = ItineraryStatus.planned;
        if (map['status'] == 'completed') status = ItineraryStatus.completed;
        if (map['status'] == 'skipped') status = ItineraryStatus.skipped;
        return ItineraryItem(
          id: map['id'],
          tripId: map['trip_id'],
          title: map['title'],
          description: map['description'] ?? '',
          day: map['day_number'],
          isAiGenerated: true,
          isLocked: false,
          latitude: map['latitude'],
          longitude: map['longitude'],
          status: status,
          visitTip: map['ai_insight'],
          category: map['category'],
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> clearLocalData() async {
    await _localTrips.clear();
    await _localItems.clear();
    if (Hive.isBoxOpen('chat_history')) {
      await Hive.box<List>('chat_history').clear();
    }
  }
}