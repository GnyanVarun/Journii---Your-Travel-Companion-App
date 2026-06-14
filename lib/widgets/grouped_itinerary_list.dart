import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ✅ FIXED IMPORTS: Pointing to the correct location in your features folder
// Adjust 'journii' if your project name is different in pubspec.yaml
import '../features/trips/itinerary_item_model.dart';
import '../features/trips/itinerary_provider.dart';

class GroupedItineraryList extends ConsumerWidget {
  final String tripId;

  const GroupedItineraryList({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Get all items for this trip
    // We cast to List<ItineraryItem> to ensure Dart knows the type
    final List<ItineraryItem> allItems = ref.watch(itineraryProvider)
        .where((item) => item.tripId == tripId)
        .toList();

    if (allItems.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "No places added yet.\nChat with the AI to plan your days!",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // 2. Group them by Day
    final Map<int, List<ItineraryItem>> grouped = {};
    for (var item in allItems) {
      grouped.putIfAbsent(item.day, () => []).add(item);
    }

    // 3. Sort the days (Day 1, Day 2...)
    final sortedDays = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80), // Space for FAB
      itemCount: sortedDays.length,
      itemBuilder: (context, index) {
        final dayNum = sortedDays[index];
        final dayItems = grouped[dayNum] ?? [];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- DAY HEADER ---
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Text(
                      "Day $dayNum",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),

              // --- LIST OF PLACES FOR THIS DAY ---
              ...dayItems.map((item) => ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.place, color: Colors.redAccent),
                ),
                // ✅ FIXED: Using 'name' or 'placeName' depending on your model
                // If your model uses 'name', change this to item.name
                title: Text(
                  item.title  ,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () {
                    // ✅ FIXED: Ensure deleteItem exists in your provider
                    ref.read(itineraryProvider.notifier).deleteItem(item.id);
                  },
                ),
              )),
            ],
          ),
        );
      },
    );
  }
}