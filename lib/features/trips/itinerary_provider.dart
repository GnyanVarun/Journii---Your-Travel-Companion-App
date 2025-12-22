import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'itinerary_item_model.dart';

final itineraryProvider =
StateNotifierProvider<ItineraryNotifier, List<ItineraryItem>>(
      (ref) => ItineraryNotifier(),
);

class ItineraryNotifier extends StateNotifier<List<ItineraryItem>> {
  ItineraryNotifier() : super([]);

  void setItinerary(List<ItineraryItem> items) {
    state = items;
  }

  List<ItineraryItem> itineraryForTrip(String tripId) {
    return state.where((item) => item.tripId == tripId).toList();
  }
}
