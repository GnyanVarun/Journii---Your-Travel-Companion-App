import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PredictHQService {
  static const String _baseUrl = 'https://api.predicthq.com/v1/events/';

  static Future<List<Map<String, dynamic>>> fetchGlobalEvents({
    required String category,
    required double lat,
    required double lon,
  }) async {
    final apiKey = dotenv.env['PREDICTHQ_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      print("⚠️ PredictHQ API Key is missing!");
      return [];
    }

    // 1. DEFINE THE WHITELIST
    const String allowedCategories = "concerts,sports,festivals,performing-arts";

    // 2. Map individual UI chips to the API categories for the search
    String phqCategory = "";
    if (category == "Concerts 🎸") phqCategory = "concerts";
    if (category == "Sports ⚽") phqCategory = "sports";
    if (category == "Festivals 🎪") phqCategory = "festivals";
    if (category == "Theater 🎭") phqCategory = "performing-arts";

    // Grab today's date dynamically in UTC format (YYYY-MM-DD)
    final String today = DateTime.now().toUtc().toIso8601String().split('T')[0];

    // 3. CONSTRUCT PARAMETERS
    final queryParams = <String, String>{
      'location_around.origin': '$lat,$lon',
      'location_around.scale': '30km',
      'within': '50km@$lat,$lon',
      'sort': 'start',
      'limit': '25',
      'state': 'active',
      'start.gte': today,
    };

    // 4. APPLY THE WHITELIST LOGIC
    queryParams['category'] = phqCategory.isNotEmpty ? phqCategory : allowedCategories;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List rawEvents = data['results'] ?? [];
        List<Map<String, dynamic>> formattedEvents = [];

        for (var event in rawEvents) {
          // Coordinate Extraction
          double eLon = 0.0, eLat = 0.0;
          if (event['location'] != null && event['location'] is List && event['location'].length >= 2) {
            eLon = (event['location'][0] as num).toDouble();
            eLat = (event['location'][1] as num).toDouble();
          }

          // 🟢 SMART CATEGORY MAPPER
          // Instead of blindly using the UI category, we read the API's actual category
          String actualCategory = "Event"; // Default
          final String rawPhqCategory = event['category']?.toString().toLowerCase() ?? '';

          if (rawPhqCategory == 'concerts') {
            actualCategory = "Concerts 🎸";
          } else if (rawPhqCategory == 'sports') {
            actualCategory = "Sports ⚽";
          } else if (rawPhqCategory == 'festivals') {
            actualCategory = "Festivals 🎪";
          } else if (rawPhqCategory == 'performing-arts') {
            actualCategory = "Theater 🎭";
          } else {
            // Fallback if it's some other category, or if we passed a specific chip
            actualCategory = (category == "All") ? "Event" : category;
          }

          String? ticketUrl = (event['url'] != null && event['url'].toString().isNotEmpty) ? event['url'] : null;
          final eventTitle = event['title'] ?? 'Global Event';
          final String fallbackUrl = "https://www.google.com/search?q=${Uri.encodeComponent(eventTitle + " tickets")}";

          formattedEvents.add({
            'id': event['id'],
            'name': eventTitle,
            'description': event['description'],
            'date': event['start']?.split('T')[0] ?? 'TBA',
            'imageUrl': 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&w=500&q=60',
            'venue': event['entities']?.isNotEmpty == true
                ? event['entities'][0]['name']
                : 'Local Venue',
            'latitude': eLat,
            'longitude': eLon,
            'ticketUrl': ticketUrl ?? fallbackUrl,

            // 🟢 WE NOW PASS THE ACTUAL CATEGORY
            'categoryTag': actualCategory,
          });
        }
        return formattedEvents;
      } else {
        print("⚠️ PredictHQ Error ${response.statusCode}: ${response.body}");
        return [];
      }
    } catch (e) {
      print("⚠️ Error fetching PredictHQ events: $e");
      return [];
    }
  }
}