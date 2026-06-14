class AIPlaceSuggestion {
  final String name;
  final String description;
  final int day;

  AIPlaceSuggestion({
    required this.name,
    required this.description,
    required this.day,
  });
}

class AIItineraryResponse {
  final List<AIPlaceSuggestion> suggestions;

  AIItineraryResponse({required this.suggestions});
}
