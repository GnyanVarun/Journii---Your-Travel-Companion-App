import 'package:hive/hive.dart';

part 'ai_insight_model.g.dart';

@HiveType(typeId: 2)
class AIInsight extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String tripId;

  @HiveField(2)
  final String content; // AI generated text

  @HiveField(3)
  final DateTime createdAt;

  AIInsight({
    required this.id,
    required this.tripId,
    required this.content,
    required this.createdAt,
  });
}
