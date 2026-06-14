import 'package:uuid/uuid.dart';
import '../features/trips/place_idea_model.dart';
import '../features/trips/itinerary_item_model.dart';

class AITripPlanner {
  static List<ItineraryItem> generateItinerary({
    required String tripId,
    required List<PlaceIdea> ideas,
  }) {
    int day = 1;

    return ideas.map((idea) {
      return ItineraryItem(
        id: const Uuid().v4(),
        tripId: tripId,
        title: idea.name,
        description: idea.notes,
        day: day++,

        // ✅ IMPORTANT
        isAiGenerated: true,
        isLocked: false,
      );
    }).toList();
  }
}
