import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'place_idea_model.dart';

final placeIdeaProvider =
StateNotifierProvider<PlaceIdeaNotifier, List<PlaceIdea>>(
      (ref) => PlaceIdeaNotifier(),
);

class PlaceIdeaNotifier extends StateNotifier<List<PlaceIdea>> {
  PlaceIdeaNotifier() : super([]);

  void addIdea(PlaceIdea idea) {
    state = [...state, idea];
  }

  List<PlaceIdea> ideasForTrip(String tripId) {
    return state.where((idea) => idea.tripId == tripId).toList();
  }
}
