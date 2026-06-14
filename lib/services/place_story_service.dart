import 'dart:convert';
import 'package:http/http.dart' as http;

class PlaceStoryService {
  /// Fetches a rich history/summary of the place from Wikipedia
  static Future<String?> fetchPlaceHistory(String placeName) async {
    try {
      // 1. Clean the name for the API (e.g., "Eiffel Tower" -> "Eiffel_Tower")
      final cleanName = placeName.trim().replaceAll(' ', '_');

      // 2. Call Wikipedia Summary API (Free, No Key needed)
      final url = Uri.parse("https://en.wikipedia.org/api/rest_v1/page/summary/$cleanName");

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 'extract' contains the nice summary/history text
        return data['extract'] as String?;
      }
      return null;
    } catch (e) {
      print("Error fetching story: $e");
      return null;
    }
  }
}