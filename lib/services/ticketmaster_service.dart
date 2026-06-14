import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TicketmasterService {
  static const String _baseUrl = 'https://app.ticketmaster.com/discovery/v2/events.json';

  static Future<List<Map<String, dynamic>>> fetchExploreEvents({
    required String category,
    double? lat,
    double? lon,
    String? city,
  }) async {
    final apiKey = dotenv.env['TICKETMASTER_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) return [];

    String classification = "";
    if (category == "Concerts 🎸") classification = "Music";
    if (category == "Sports ⚽") classification = "Sports";
    if (category == "Festivals 🎪") classification = "Festivals";
    if (category == "Theater 🎭") classification = "Arts & Theatre";

    final now = DateTime.now().toUtc();
    final formattedDate = '${now.toIso8601String().split('.')[0]}Z';

    final queryParams = {
      'apikey': apiKey,
      'size': '50',
      'sort': 'date,asc',
      'startDateTime': formattedDate,
      'locale': '*', // 🟢 CRITICAL FIX: Ignores language barriers for global data
    };

    // 🟢 LOGIC UPGRADE: If we have coordinates, use 'latlong'. Otherwise, fallback to city.
    if (lat != null && lon != null) {
      queryParams['latlong'] = "$lat,$lon";
      queryParams['radius'] = "100"; // 🟢 INCREASED: Searches a 100km radius around the city
      queryParams['unit'] = "km";
    } else if (city != null) {
      queryParams['city'] = city;
    }

    if (classification.isNotEmpty) {
      queryParams['classificationName'] = classification;
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['_embedded'] != null && data['_embedded']['events'] != null) {
          final List rawEvents = data['_embedded']['events'];
          Set<String> seenEventNames = {};
          List<Map<String, dynamic>> uniqueEvents = [];

          for (var event in rawEvents) {
            final status = event['dates']?['status']?['code']?.toString().toLowerCase() ?? 'onsale';
            if (status == 'canceled' || status == 'cancelled') continue;

            final eventName = event['name'] ?? 'Awesome Event';
            if (seenEventNames.contains(eventName)) continue;
            seenEventNames.add(eventName);

            // Image and Coordinate extraction...
            String imageUrl = 'https://via.placeholder.com/400x200';
            if (event['images'] != null) {
              final images = List<Map<String, dynamic>>.from(event['images']);
              imageUrl = images.firstWhere((img) => img['ratio'] == '16_9', orElse: () => images.first)['url'];
            }

            double eLat = 0.0, eLon = 0.0;
            String vName = 'Unknown Venue';
            if (event['_embedded']?['venues'] != null) {
              final v = event['_embedded']['venues'][0];
              vName = v['name'] ?? vName;
              eLat = double.tryParse(v['location']?['latitude'] ?? '0') ?? 0.0;
              eLon = double.tryParse(v['location']?['longitude'] ?? '0') ?? 0.0;
            }

            uniqueEvents.add({
              'id': event['id'],
              'name': eventName,
              'date': event['dates']?['start']?['localDate'] ?? 'TBA',
              'imageUrl': imageUrl,
              'venue': vName,
              'latitude': eLat,
              'longitude': eLon,
              'ticketUrl': event['url'] ?? '',
              'categoryTag': category,
            });
            if (uniqueEvents.length >= 15) break;
          }
          return uniqueEvents;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}