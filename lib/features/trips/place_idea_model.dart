import 'package:hive/hive.dart';

part 'place_idea_model.g.dart';

@HiveType(typeId: 1)
class PlaceIdea {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String tripId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String notes;

  @HiveField(4)
  final int priority; // AI importance

  @HiveField(5)
  final int createdAt; // ordering

  PlaceIdea({
    required this.id,
    required this.tripId,
    required this.name,
    required this.notes,
    this.priority = 3,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  PlaceIdea copyWith({
    String? name,
    String? notes,
    int? priority,
  }) {
    return PlaceIdea(
      id: id,
      tripId: tripId,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      priority: priority ?? this.priority,
      createdAt: createdAt,
    );
  }
}
