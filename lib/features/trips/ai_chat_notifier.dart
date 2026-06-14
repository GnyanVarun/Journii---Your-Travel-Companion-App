import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

import '../../services/ai_travel_service.dart';
import '../../services/ai_travel_service_provider.dart';
import 'ai_chat_state.dart';
import 'chat_message_model.dart';
import 'ai_itinerary_model.dart';

// ✅ IMPORT THE REPO
import '../../features/trips/trip_repository.dart';

final aiChatProvider =
StateNotifierProvider.family<AIChatNotifier, AIChatState, String>(
      (ref, tripId) => AIChatNotifier(
    ref.read(aiTravelServiceProvider),
    tripId,
  ),
);

class AIChatNotifier extends StateNotifier<AIChatState> {
  final AITravelService _service;
  final String _tripId;
  final _uuid = const Uuid();

  AIChatNotifier(this._service, this._tripId) : super(AIChatState.initial());

  /// 🧠 SMART START: Hive -> Cloud -> Fresh Start
  Future<void> loadHistoryOrStart(String basePrompt) async {
    if (state.messages.isNotEmpty) {
      print("🧠 Memory check: Messages already loaded.");
      return;
    }

    final box = Hive.box<List>('chat_history');

    // 1️⃣ CHECK HIVE (Local)
    if (box.containsKey(_tripId)) {
      final storedList = box.get(_tripId);
      if (storedList != null && storedList.isNotEmpty) {
        try {
          final messages = storedList.map((e) => e as ChatMessage).toList();
          print("✅ Hive: Loaded ${messages.length} messages.");
          state = state.copyWith(
            messages: messages,
            isLoading: false,
            contextPrompt: basePrompt,
          );
          return; // Found locally, we are done!
        } catch (e) {
          print("🔥 Hive Error: $e");
        }
      }
    }

    // 2️⃣ CHECK CLOUD (Supabase) - 🆕 NEW STEP
    print("☁️ Hive empty. Checking Supabase for history...");
    final cloudMessages = await TripRepository().fetchMessages(_tripId);

    if (cloudMessages.isNotEmpty) {
      print("✅ Cloud: Restored ${cloudMessages.length} messages.");

      // Save to Hive so next time we don't need network
      box.put(_tripId, cloudMessages);

      state = state.copyWith(
        messages: cloudMessages,
        isLoading: false,
        contextPrompt: basePrompt,
      );
      return;
    }

    // 3️⃣ FRESH START (If both Hive and Cloud are empty)
    print("🚀 No history found anywhere. Starting fresh.");
    await start(basePrompt);
  }

  Future<void> start(String basePrompt) async {
    if (state.messages.isNotEmpty) return;

    state = state.copyWith(
      contextPrompt: basePrompt,
      isLoading: true,
    );

    await _generateResponse();
  }

  Future<void> sendMessage(String text) async {
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: ChatRole.user,
      text: text,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
    );

    _saveToHive();
    TripRepository().saveMessage(userMsg, _tripId); // ☁️ Sync to Cloud

    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    try {
      final history = state.messages.map((msg) => {
        'role': msg.role == ChatRole.user ? 'user' : 'ai',
        'text': msg.text,
      }).toList();

      if (history.isEmpty && state.contextPrompt.isNotEmpty) {
        history.add({'role': 'user', 'text': state.contextPrompt});
      }

      final AIItineraryResponse response =
      await _service.generateItineraryWithHistory(history);

      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        role: ChatRole.ai,
        text: response.summary,
        itineraryPlaces: response.places,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        isLoading: false,
      );

      _saveToHive();
      TripRepository().saveMessage(aiMsg, _tripId); // ☁️ Sync to Cloud

    } catch (e) {
      print("Error in Chat Notifier: $e");

      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        role: ChatRole.ai,
        text: "I'm having a little trouble connecting. Please try again!",
        isError: true,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, errorMsg],
        isLoading: false,
      );
    }
  }

  void _saveToHive() {
    final box = Hive.box<List>('chat_history');
    box.put(_tripId, state.messages);
  }
}