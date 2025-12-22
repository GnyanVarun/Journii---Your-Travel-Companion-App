import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'trip_model.dart';
import 'place_idea_model.dart';
import 'place_idea_provider.dart';
import 'itinerary_provider.dart';
import '../../services/ai_trip_planner.dart';

class TripDetailPage extends ConsumerWidget {
  final Trip trip;

  const TripDetailPage({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeNotifier = ref.watch(placeIdeaProvider.notifier);
    final itineraryNotifier = ref.watch(itineraryProvider.notifier);

    final ideas = placeNotifier.ideasForTrip(trip.id);
    final itinerary = itineraryNotifier.itineraryForTrip(trip.id);

    return Scaffold(
      appBar: AppBar(title: Text(trip.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(trip.description),
          const SizedBox(height: 24),

          // 🔹 Brainstorm section
          const Text(
            'Brainstorm Places',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ...ideas.map(
                (idea) => ListTile(
              title: Text(idea.name),
              subtitle: Text(idea.notes),
            ),
          ),

          const SizedBox(height: 32),

          // 🔹 AI Itinerary section
          const Text(
            'AI Itinerary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ...itinerary.map(
                (item) => ListTile(
              leading: CircleAvatar(child: Text('Day ${item.day}')),
              title: Text(item.title),
              subtitle: Text(item.description),
            ),
          ),
        ],
      ),

      // 🔹 Floating buttons
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'ai',
            onPressed: () {
              final generated = AITripPlanner.generateItinerary(
                tripId: trip.id,
                ideas: ideas,
              );

              ref
                  .read(itineraryProvider.notifier)
                  .setItinerary(generated);
            },
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => _addIdea(ref),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _addIdea(WidgetRef ref) {
    ref.read(placeIdeaProvider.notifier).addIdea(
      PlaceIdea(
        id: const Uuid().v4(),
        tripId: trip.id,
        name: 'New Place',
        notes: 'Why this place?',
      ),
    );
  }
}
