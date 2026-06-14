import 'package:hive/hive.dart';
import 'place_plan_model.dart';

part 'day_plan_model.g.dart';

@HiveType(typeId: 12)
class DayPlan {
  @HiveField(0)
  final int dayNumber;

  @HiveField(1)
  final List<PlacePlan> places;

  DayPlan({
    required this.dayNumber,
    required this.places,
  });
}
