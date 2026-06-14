import 'package:hive/hive.dart';

part 'itinerary_item_model.g.dart';

/// --------------------------------------------------
/// 📌 STATUS OF AN ITINERARY ITEM
/// --------------------------------------------------
@HiveType(typeId: 3)
enum ItineraryStatus {
  @HiveField(0)
  planned,

  @HiveField(1)
  skipped,

  @HiveField(2)
  completed,
}

/// --------------------------------------------------
/// 🕒 OPTIONAL VISIT TIME HINT
/// --------------------------------------------------
@HiveType(typeId: 4)
enum VisitTime {
  @HiveField(0)
  morning,
  @HiveField(1)
  afternoon,
  @HiveField(2)
  evening,
  @HiveField(3)
  night,
}

/// --------------------------------------------------
/// 🗺️ ITINERARY ITEM MODEL
/// --------------------------------------------------
@HiveType(typeId: 2)
class ItineraryItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String tripId;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final String description;

  @HiveField(4)
  final int day;

  @HiveField(5)
  final bool isAiGenerated;

  @HiveField(6)
  final bool isLocked;

  // 📍 Map fields
  @HiveField(7)
  final double? latitude;

  @HiveField(8)
  final double? longitude;

  // ✅ Status (default = planned)
  @HiveField(9)
  final ItineraryStatus status;

  // 🕒 Optional experience hints
  @HiveField(10)
  final String? visitTip;

  @HiveField(11)
  final VisitTime? preferredVisitTime;

  // 🆕 ADDED FIELD: Category
  @HiveField(12)
  final String? category;

  ItineraryItem({
    required this.id,
    required this.tripId,
    required this.title,
    required this.description,
    required this.day,
    required this.isAiGenerated,
    required this.isLocked,
    this.latitude,
    this.longitude,
    this.status = ItineraryStatus.planned,
    this.visitTip,
    this.preferredVisitTime,
    this.category,
  });

  // 🏭 1. FACTORY: Create from Cloud JSON
  factory ItineraryItem.fromJson(Map<String, dynamic> json) {
    return ItineraryItem(
      id: json['id'],
      tripId: json['trip_id'] ?? '',
      title: json['title'] ?? 'Untitled',
      description: json['description'] ?? '',
      day: json['day_number'] ?? 1,
      isAiGenerated: json['is_ai_generated'] ?? false,
      isLocked: json['is_locked'] ?? false,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      status: _parseStatus(json['status']),

      // ✅ CRITICAL FIX: Mapping 'ai_insight' from DB to 'visitTip' in App
      visitTip: json['ai_insight'],

      preferredVisitTime: _parseVisitTime(json['preferred_visit_time']),
      category: json['category'],
    );
  }

// 📤 2. CONVERT TO JSON (For saving to Cloud)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'title': title,
      'description': description,
      'day_number': day,
      'is_ai_generated': isAiGenerated,
      'is_locked': isLocked,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.name,

      // ✅ CRITICAL FIX: Saving 'visitTip' to 'ai_insight' column
      'ai_insight': visitTip,

      'preferred_visit_time': preferredVisitTime?.name,
      'category': category,
    };
  }

  // Helper: Parse Status String from DB
  static ItineraryStatus _parseStatus(String? statusStr) {
    if (statusStr == null) return ItineraryStatus.planned;
    try {
      return ItineraryStatus.values.firstWhere((e) => e.name == statusStr);
    } catch (_) {
      return ItineraryStatus.planned;
    }
  }

  // Helper: Parse VisitTime String from DB
  static VisitTime? _parseVisitTime(String? timeStr) {
    if (timeStr == null) return null;
    try {
      return VisitTime.values.firstWhere((e) => e.name == timeStr);
    } catch (_) {
      return null;
    }
  }

  ItineraryItem copyWith({
    String? id,
    String? tripId,
    String? title,
    String? description,
    int? day,
    bool? isAiGenerated,
    bool? isLocked,
    double? latitude,
    double? longitude,
    ItineraryStatus? status,
    String? visitTip,
    VisitTime? preferredVisitTime,
    String? category,
  }) {
    return ItineraryItem(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      title: title ?? this.title,
      description: description ?? this.description,
      day: day ?? this.day,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      isLocked: isLocked ?? this.isLocked,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      visitTip: visitTip ?? this.visitTip,
      preferredVisitTime: preferredVisitTime ?? this.preferredVisitTime,
      category: category ?? this.category,
    );
  }
}