import 'package:hive/hive.dart';
import 'ai_itinerary_model.dart';

// ⚠️ This part file name must match your file name
part 'chat_message_model.g.dart';

@HiveType(typeId: 21) // Unique ID for the Enum
enum ChatRole {
  @HiveField(0)
  user,
  @HiveField(1)
  ai,
}

@HiveType(typeId: 20) // Unique ID for the Class
class ChatMessage {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final ChatRole role;

  @HiveField(2)
  final String text;

  @HiveField(3)
  final List<AIPlace>? itineraryPlaces;

  @HiveField(4)
  final bool isError;

  // ✅ ADDED: Required by your Notifier to sort/save messages
  @HiveField(5)
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.itineraryPlaces,
    this.isError = false,
    required this.timestamp, // ✅ Required now
  });

  bool get hasItinerary => itineraryPlaces != null && itineraryPlaces!.isNotEmpty;
}