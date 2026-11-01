import 'package:hive/hive.dart';

part 'ai_itinerary_model.g.dart';

class AIItineraryResponse {
  final String summary;
  final List<AIPlace> places;

  AIItineraryResponse({
    required this.summary,
    required this.places,
  });

  factory AIItineraryResponse.fromJson(Map<String, dynamic> json) {
    final parsedPlaces = <AIPlace>[];

    if (json['places'] is List) {
      for (final item in json['places'] as List<dynamic>) {
        if (item is Map<String, dynamic>) {
          parsedPlaces.add(AIPlace.fromJson(item));
        } else if (item is Map) {
          parsedPlaces.add(AIPlace.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (json['days'] is List) {
      for (final dayObj in json['days'] as List<dynamic>) {
        if (dayObj is! Map) continue;
        final dayNum = dayObj['day'] is int
            ? dayObj['day'] as int
            : int.tryParse(dayObj['day']?.toString() ?? '') ?? 1;
        final dayCity =
        (dayObj['city'] ?? dayObj['geoContext'] ?? dayObj['location'])
            ?.toString();
        final dayPlaces = dayObj['places'];
        if (dayPlaces is List) {
          for (final p in dayPlaces) {
            if (p is! Map) continue;
            final map = Map<String, dynamic>.from(p);
            map['day'] ??= dayNum;
            map['geoContext'] ??= dayCity;
            parsedPlaces.add(AIPlace.fromJson(map));
          }
        }
      }
    }

    return AIItineraryResponse(
      summary: json['summary']?.toString() ?? "Here is your plan!",
      places: parsedPlaces,
    );
  }
}

@HiveType(typeId: 22)
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

  @HiveField(5)
  final String? geoContext;

  AIPlace({
    required this.name,
    required this.description,
    required this.day,
    required this.bestTime,
    required this.visitTip,
    this.geoContext,
  });

  static String? _extractGeoContext(Map<String, dynamic> map) {
    final raw = map['geoContext'] ??
        map['geo_context'] ??
        map['city'] ??
        map['locality'] ??
        map['location'] ??
        map['region'];
    final trimmed = raw?.toString().trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  factory AIPlace.fromJson(Map<String, dynamic> json) {
    return AIPlace(
      name: json['name'] ?? json['placeName'] ?? "Unknown Place",
      description: json['description'] ?? "",
      day: json['day'] is int
          ? json['day']
          : int.tryParse(json['day'].toString()) ?? 1,
      bestTime: json['bestTime'] ?? "Morning",
      visitTip: json['visitTip'] ??
          "Best visited during the ${json['bestTime']?.toString().toLowerCase() ?? 'day'}.",
      geoContext: _extractGeoContext(json),
    );
  }

  factory AIPlace.fromMap(Map<String, dynamic> map) {
    return AIPlace(
      name: map['name'] ?? "Unknown Place",
      description: map['description'] ?? "",
      day: map['day'] is int
          ? map['day']
          : int.tryParse(map['day'].toString()) ?? 1,
      bestTime: map['bestTime'] ?? "Morning",
      visitTip: map['visitTip'] ?? "",
      geoContext: _extractGeoContext(map),
    );
  }
}