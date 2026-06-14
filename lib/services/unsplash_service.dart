import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class UnsplashService {
  static String get _accessKey => dotenv.env['UNSPLASH_ACCESS_KEY'] ?? '';

  static Future<String?> getPhotoUrl(String query) async {
    if (_accessKey.isEmpty) return null;

    // 1. Try the exact query first (e.g., "Kyoto, Japan")
    String? url = await _fetch(query);

    // 2. Fallback 1: Append generic travel terms instead of Italy
    if (url == null) {
      print("⚠️ Unsplash: No results for '$query'. Trying fallback...");
      url = await _fetch("$query travel landscape");
    }

    // 3. Fallback 2: The ultimate safety net so the UI is never empty
    if (url == null) {
      url = await _fetch("beautiful travel destination");
    }
    return url;
  }

  // Helper method to keep code clean
  static Future<String?> _fetch(String query) async {
    try {
      final uri = Uri.parse(
          'https://api.unsplash.com/search/photos?query=$query&per_page=1&orientation=landscape&client_id=$_accessKey'
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final foundUrl = data['results'][0]['urls']['regular'];
          print("📸 Image Found for '$query': $foundUrl");
          return foundUrl;
        }
      }
    } catch (_) {}
    return null;
  }

  // 🟢 ADD THIS: The Slogan Generator for the Travel Dex Badges
  static String generateSlogan(String destination) {
    final slogans = [
      "The adventure of a lifetime.",
      "A journey to remember.",
      "Discover the magic of the city.",
      "Where memories are made.",
      "Wanderlust fulfilled.",
      "A beautiful escape.",
      "Chasing horizons."
    ];

    // Pick a pseudo-random one based on the city's name length so it stays consistent for the same city!
    final index = destination.length % slogans.length;
    return slogans[index];
  }

}