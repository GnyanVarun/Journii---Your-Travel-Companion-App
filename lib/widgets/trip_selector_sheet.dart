import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journii/features/trips/trip_provider.dart';
import '../../services/event_backend_service.dart';
import '../features/trips/itinerary_provider.dart';

class TripSelectorSheet extends ConsumerWidget {
  final Map<String, dynamic> event;
  final VoidCallback onAdded;

  const TripSelectorSheet({super.key, required this.event,required this.onAdded,});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Select a Trip", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // 🟢 The Visual List of Trips
          ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: trips.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final trip = trips[index];
              return Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.withOpacity(0.1),
                    child: const Icon(Icons.flight_takeoff, color: Colors.indigo),
                  ),
                  title: Text(trip.destination ?? trip.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${trip.startDate?.year ?? '2026'}"),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () async {
                    try {
                      await ref.read(eventBackendProvider).addEventToItinerary(event, trip.id);

                      onAdded();
                      ref.invalidate(savedEventsProvider(trip.id));
                      Navigator.pop(context);

                      // 🟢 SAFE FALLBACK: If destination/title is null, show "trip"
                      final tripName = trip.destination ?? trip.title ?? "your trip";

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Added to $tripName!"),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (e) {
                      // ... error handling
                    }
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}