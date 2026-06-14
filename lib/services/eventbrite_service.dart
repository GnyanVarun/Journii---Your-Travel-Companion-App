import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EventbriteService {
  // 🟢 The standard Eventbrite discovery endpoint
  static const String _baseUrl = 'https://www.eventbriteapi.com/v3/events/search/';

  static Future<List<Map<String, dynamic>>> fetchLocalEvents({
    required String category,
    required double lat,
    required double lon,
  }) async {
    final apiKey = dotenv.env['EVENTBRITE_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      print("⚠️ Eventbrite API Key is missing!");
      return [];
    }

    // 1. Map your UI categories to Eventbrite search queries
    String searchQuery = "";
    if (category == "Concerts 🎸") searchQuery = "live music";
    if (category == "Sports ⚽") searchQuery = "sports";
    if (category == "Festivals 🎪") searchQuery = "festival";
    if (category == "Theater 🎭") searchQuery = "performing arts";

    // 2. Construct the URL with location and expansion parameters
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': searchQuery,
      'location.latitude': lat.toString(),
      'location.longitude': lon.toString(),
      'location.within': '50km', // Cast a 50km net for local events
      'expand': 'venue', // 🟢 CRITICAL: Forces Eventbrite to return latitude/longitude for the map
      'sort_by': 'date',
    });

    try {
      final response = await http.get(
        uri,
        headers: {
          // Eventbrite requires the token to be passed as a Bearer Authorization header
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List rawEvents = data['events'] ?? [];
        List<Map<String, dynamic>> formattedEvents = [];

        for (var event in rawEvents) {
          // Drop canceled events
          if (event['status'] == 'canceled') continue;

          // Eventbrite stores the main image inside the 'logo' object
          String imageUrl = 'https://via.placeholder.com/400x200';
          if (event['logo'] != null && event['logo']['original'] != null) {
            imageUrl = event['logo']['original']['url'];
          }

          // Extract coordinates and venue name from the expanded venue object
          double eLat = 0.0, eLon = 0.0;
          String vName = 'Local Venue';
          if (event['venue'] != null) {
            vName = event['venue']['name'] ?? vName;
            eLat = double.tryParse(event['venue']['latitude'] ?? '0') ?? 0.0;
            eLon = double.tryParse(event['venue']['longitude'] ?? '0') ?? 0.0;
          }

          formattedEvents.add({
            'id': event['id'],
            'name': event['name']['text'] ?? 'Awesome Local Event',
            // Eventbrite local start times look like: "2026-05-14T19:00:00"
            'date': event['start']['local']?.split('T')[0] ?? 'TBA',
            'imageUrl': imageUrl,
            'venue': vName,
            'latitude': eLat,
            'longitude': eLon,
            'ticketUrl': event['url'] ?? '',
            'categoryTag': category,
          });

          // Limit to top 15 results to match Ticketmaster
          if (formattedEvents.length >= 15) break;
        }
        return formattedEvents;
      } else {
        print("⚠️ Eventbrite Error ${response.statusCode}: ${response.body}");
        return [];
      }
    } catch (e) {
      print("⚠️ Error fetching Eventbrite events: $e");
      return [];
    }
  }
}