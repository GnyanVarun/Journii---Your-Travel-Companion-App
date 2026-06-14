import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_travel_service.dart';

final aiTravelServiceProvider = Provider<AITravelService>((ref) {
  return AITravelService();
});
