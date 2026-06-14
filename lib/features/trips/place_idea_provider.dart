import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'place_idea_model.dart';

final placeIdeaProvider =
StateNotifierProvider<PlaceIdeaNotifier, List<PlaceIdea>>(
      (ref) => PlaceIdeaNotifier(),
);

class PlaceIdeaNotifier extends StateNotifier<List<PlaceIdea>> {
  // ✅ 1. Reference the box safely
  final Box<PlaceIdea> _box = Hive.box<PlaceIdea>('place_ideas');

  // ✅ 2. Load and Sort immediately in 'super'
  PlaceIdeaNotifier() : super([]) {
    // Load values
    final allIdeas = _box.values.toList();

    // Sort by created date (Oldest first)
    allIdeas.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Set state
    state = allIdeas;
  }

  void addIdea(PlaceIdea idea) {
    _box.put(idea.id, idea);
    state = [...state, idea];
  }

  void updateIdea(PlaceIdea updated) {
    _box.put(updated.id, updated);
    state = [
      for (final idea in state)
        if (idea.id == updated.id) updated else idea,
    ];
  }

  void addOrUpdateIdea(PlaceIdea idea) {
    _box.put(idea.id, idea);

    final index = state.indexWhere((i) => i.id == idea.id);
    if (index == -1) {
      state = [...state, idea];
    } else {
      state = [
        for (final i in state)
          if (i.id == idea.id) idea else i,
      ];
    }
  }

  void removeIdea(String id) {
    _box.delete(id);
    state = state.where((idea) => idea.id != id).toList();
  }

  /// 🗑️ Delete all place ideas for a trip (Phase 2.5.2)
  void deleteForTrip(String tripId) {
    // 1️⃣ Delete from Hive
    final keysToDelete = _box.keys.where((key) {
      final idea = _box.get(key);
      return idea?.tripId == tripId;
    }).toList();

    for (final key in keysToDelete) {
      _box.delete(key);
    }

    // 2️⃣ Update in-memory state
    state = state.where((idea) => idea.tripId != tripId).toList();
  }

}

//
// ✅ Trip-scoped provider (Sorted by Priority High -> Low)
//
final placeIdeasForTripProvider =
Provider.family<List<PlaceIdea>, String>((ref, tripId) {
  final ideas = ref.watch(placeIdeaProvider);

  final filtered = ideas.where((idea) => idea.tripId == tripId).toList();

  // Sort: High Priority (3) -> Low Priority (1)
  filtered.sort((a, b) => b.priority.compareTo(a.priority));

  return filtered;
});