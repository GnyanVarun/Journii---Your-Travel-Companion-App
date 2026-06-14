import 'package:flutter/foundation.dart';
import 'chat_message_model.dart';

@immutable
class AIChatState {
  final bool isLoading;
  // Now we store a conversation history!
  final List<ChatMessage> messages;
  final String contextPrompt;

  const AIChatState({
    required this.isLoading,
    required this.messages,
    required this.contextPrompt,
  });

  factory AIChatState.initial() {
    return const AIChatState(
      isLoading: false,
      messages: [],
      contextPrompt: '',
    );
  }

  AIChatState copyWith({
    bool? isLoading,
    List<ChatMessage>? messages,
    String? contextPrompt,
  }) {
    return AIChatState(
      isLoading: isLoading ?? this.isLoading,
      messages: messages ?? this.messages,
      contextPrompt: contextPrompt ?? this.contextPrompt,
    );
  }
}