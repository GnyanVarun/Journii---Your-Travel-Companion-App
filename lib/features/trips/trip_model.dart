import 'package:hive/hive.dart';
import 'trip_style.dart';

part 'trip_model.g.dart';

@HiveType(typeId: 0)
class Trip extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final int? durationDays;

  @HiveField(5)
  final TripStyle? style;

  @HiveField(6)
  final DateTime? startDate;

  @HiveField(7)
  final DateTime? endDate;

  @HiveField(8)
  String? userId;

  @HiveField(9)
  String? destination;

  @HiveField(10, defaultValue: 2)
  int curiosityLevel;

  @HiveField(11)
  final String? badgeImageUrl;

  @HiveField(12)
  final String? badgeSlogan;

  TripStyle? get tripStyle => style;

  Trip({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.durationDays,
    this.style,
    this.startDate,
    this.endDate,
    this.userId,
    this.destination,
    this.curiosityLevel = 2,
    this.badgeImageUrl,
    this.badgeSlogan,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'destination': destination,
      'user_id': userId,
      'curiosity_level': curiosityLevel,
      // ✅ FIX: Uses the name of the first style in your file as fallback
      'trip_style': style?.name ?? TripStyle.values.first.name,
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      startDate: json['start_date'] != null ? DateTime.parse(json['start_date']) : null,
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
      destination: json['destination'],
      userId: json['user_id'],
      curiosityLevel: json['curiosity_level'] ?? 2,
      durationDays: (json['start_date'] != null && json['end_date'] != null)
          ? DateTime.parse(json['end_date']).difference(DateTime.parse(json['start_date'])).inDays + 1
          : 0,
      badgeImageUrl: json['badge_image_url'],
      badgeSlogan: json['badge_slogan'],
    );
  }

  Trip copyWith({
    String? title,
    String? description,
    int? durationDays,
    TripStyle? style,
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? destination,
    int? curiosityLevel,
  }) {
    return Trip(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      durationDays: durationDays ?? this.durationDays,
      style: style ?? this.style,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      userId: userId ?? this.userId,
      destination: destination ?? this.destination,
      curiosityLevel: curiosityLevel ?? this.curiosityLevel,
      badgeImageUrl: badgeImageUrl ?? this.badgeImageUrl, // 🟢 ADDED THIS
      badgeSlogan: badgeSlogan ?? this.badgeSlogan,
    );
  }
}