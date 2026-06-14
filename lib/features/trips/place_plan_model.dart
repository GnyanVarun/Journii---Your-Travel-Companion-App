import 'package:hive/hive.dart';

part 'place_plan_model.g.dart';

@HiveType(typeId: 13)
class PlacePlan {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final String description;

  @HiveField(2)
  final String timeSlot; // Morning / Afternoon / Evening

  PlacePlan({
    required this.name,
    required this.description,
    required this.timeSlot,
  });
}
