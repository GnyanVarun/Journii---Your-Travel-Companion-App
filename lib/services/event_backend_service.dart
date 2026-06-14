import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// 🟢 This Provider makes the service accessible anywhere in your app
final eventBackendProvider = Provider((ref) => EventBackendService());

class EventBackendService {
  final _supabase = Supabase.instance.client;

  // 1. Check if an event is already in the wishlist on load
  Future<bool> isEventSaved(String eventId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await _supabase
          .from('saved_events')
          .select('id')
          .match({'user_id': userId, 'event_id': eventId})
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint("Error checking saved status: $e");
      return false;
    }
  }

  // 2. Add or Remove the event
  Future<void> toggleWishlist(Map<String, dynamic> event, bool isCurrentlySaved) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not logged in");

    try {
      if (isCurrentlySaved) {
        // Remove from wishlist
        await _supabase
            .from('saved_events')
            .delete()
            .match({'user_id': userId, 'event_id': event['id']});
      } else {
        // Add to wishlist
        await _supabase.from('saved_events').insert({
          'user_id': userId,
          'event_id': event['id'],
          'event_data': event,
        });
      }
    } catch (e) {
      debugPrint("Error updating wishlist: $e");
      rethrow;
    }
  }

  // Add this to your EventBackendService class
  Future<void> addEventToItinerary(Map<String, dynamic> event, String tripId) async {
    await Supabase.instance.client.from('itinerary_events').insert({
      'trip_id': tripId,
      'event_id': event['id'],
      // Flatten the important stuff so you can actually read your table
      'event_name': event['name'],
      'event_date': event['date'],
      'venue_name': event['venue'],
      'event_data': event, // Keep the full original map as a backup
    });
  }

  // Add this method to your EventBackendService class
  Future<bool> isEventAddedToItinerary(String eventId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      // We check if an itinerary event exists with this event_id
      // Joining with trips ensures we only check events belonging to the user
      final response = await Supabase.instance.client
          .from('itinerary_events')
          .select('id, trips!inner(user_id)')
          .eq('event_id', eventId)
          .eq('trips.user_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint("Error checking itinerary status: $e");
      return false;
    }
  }

}