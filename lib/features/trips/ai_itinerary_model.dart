import 'package:hive/hive.dart';

// ✅ CRITICAL: This line allows the generator to build the adapter
part 'ai_itinerary_model.g.dart';

class AIItineraryResponse {
  final String summary;
  final List<AIPlace> places;

  AIItineraryResponse({
    required this.summary,
    required this.places,
  });

  factory AIItineraryResponse.fromJson(Map<String, dynamic> json) {
    return AIItineraryResponse(
      summary: json['summary'] ?? "Here is your plan!",
      places: (json['places'] as List<dynamic>?)
          ?.map((item) => AIPlace.fromJson(item))
          .toList() ??
          [],
    );
  }
}

// ✅ ADD HIVE ANNOTATIONS HERE
@HiveType(typeId: 22) // Unique ID for AIPlace
class AIPlace {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final String description;

  @HiveField(2)
  final int day;

  @HiveField(3)
  final String bestTime;

  @HiveField(4)
  final String visitTip;

  AIPlace({
    required this.name,
    required this.description,
    required this.day,
    required this.bestTime,
    required this.visitTip,
  });

  // 1. Existing JSON Factory (Kept unchanged)
  factory AIPlace.fromJson(Map<String, dynamic> json) {
    return AIPlace(
      name: json['name'] ?? json['placeName'] ?? "Unknown Place",
      description: json['description'] ?? "",
      day: json['day'] is int ? json['day'] : int.tryParse(json['day'].toString()) ?? 1,
      bestTime: json['bestTime'] ?? "Morning",
      visitTip: json['visitTip'] ?? "Best visited during the ${json['bestTime']?.toString().toLowerCase() ?? 'day'}.",
    );
  }

  // 🚀 2. NEW: The "From Map" Factory (Required for Supabase Sync)
  // This is what the TripRepository is looking for!
  factory AIPlace.fromMap(Map<String, dynamic> map) {
    return AIPlace(
      name: map['name'] ?? "Unknown Place",
      description: map['description'] ?? "",
      day: map['day'] is int ? map['day'] : int.tryParse(map['day'].toString()) ?? 1,
      bestTime: map['bestTime'] ?? "Morning",
      visitTip: map['visitTip'] ?? "",
    );
  }
}