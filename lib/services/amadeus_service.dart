import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AmadeusService {
  // 🔐 LOAD KEYS FROM .ENV
  static String get _clientId => dotenv.env['AMADEUS_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['AMADEUS_CLIENT_SECRET'] ?? '';

  static String? _accessToken;
  static DateTime? _tokenExpiry;

  // 1. 🔐 AUTHENTICATE (Get the Token)
  static Future<String?> _getAccessToken() async {
    // Check if keys are missing
    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      print("❌ ERROR: Amadeus keys not found in .env file");
      return null;
    }

    // Reuse valid token if available
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    try {
      final response = await http.post(
        Uri.parse('https://test.api.amadeus.com/v1/security/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'client_credentials',
          'client_id': _clientId,
          'client_secret': _clientSecret,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];

        // Amadeus tokens expire in ~1800 seconds (30 mins). We'll refresh 5 mins early.
        final int expiresIn = data['expires_in'] ?? 1799;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 300));

        return _accessToken;
      } else {
        print("❌ Amadeus Auth Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("❌ Amadeus Connection Error: $e");
    }
    return null;
  }

  // 2. 💎 FIND HIDDEN GEMS (Points of Interest)
  // This is the method your map view is looking for!
  static Future<List<Map<String, dynamic>>> fetchHiddenGems(LatLng location) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      // Searching for SIGHTS within 1km radius
      final url = 'https://test.api.amadeus.com/v1/shopping/activities'
          '?latitude=${location.latitude}'
          '&longitude=${location.longitude}'
          '&radius=1'
          '&categories=SIGHTS,HISTORICAL'
          '&page[limit]=5'; // Get top 5

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> locations = data['data'];

        // Convert API data to a simple List
        return locations.map((item) {
          return {
            'name': item['name'],
            'category': item['category'],
            'lat': item['geoCode']['latitude'],
            'lng': item['geoCode']['longitude'],
          };
        }).toList();
      } else {
        print("❌ Amadeus API Error: ${response.body}");
      }
    } catch (e) {
      print("Amadeus Scan Error: $e");
    }
    return [];
  }

  // ✈️ 1. SEARCH FLIGHTS (The "Getting There" Engine)
  static Future<List<Map<String, dynamic>>> searchFlights({
    required String origin,      // IATA Code (e.g., 'HYD')
    required String destination, // IATA Code (e.g., 'CDG')
    required String date,        // YYYY-MM-DD (e.g., '2026-05-12')
  }) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    // Search for 1 adult, economy class
    final url = 'https://test.api.amadeus.com/v2/shopping/flight-offers'
        '?originLocationCode=$origin'
        '&destinationLocationCode=$destination'
        '&departureDate=$date'
        '&adults=1'
        '&max=5'; // Limit to top 5 results

    try {
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> offers = data['data'];

        return offers.map((offer) {
          // Flatten the complex API response into a simple map
          final itinerary = offer['itineraries'][0];
          final segment = itinerary['segments'][0];
          final price = offer['price'];

          return {
            'airline': segment['carrierCode'], // e.g., 'BA'
            'flightNumber': "${segment['carrierCode']} ${segment['number']}",
            'departure': segment['departure']['at'], // ISO Date
            'arrival': segment['arrival']['at'],
            'duration': itinerary['duration'].toString().replaceAll('PT', '').toLowerCase(),
            'price': "${price['currency']} ${price['total']}", // 'EUR 450.00'
          };
        }).toList();
      }
    } catch (e) {
      print("✈️ Flight Search Error: $e");
    }
    return [];
  }

  // 🏨 2. SEARCH HOTELS (The "Staying There" Engine)
  static Future<List<Map<String, dynamic>>> searchHotels({
    required String cityCode, // IATA Code (e.g., 'PAR' for Paris)
  }) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    // Step 1: Find Hotels in the City
    final url = 'https://test.api.amadeus.com/v1/reference-data/locations/hotels/by-city'
        '?cityCode=$cityCode'
        '&radius=5'
        '&radiusUnit=KM'
        '&hotelSource=ALL';

    try {
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> hotels = data['data'];

        // Return top 5 hotels
        return hotels.take(5).map((hotel) {
          return {
            'name': hotel['name'],
            'hotelId': hotel['hotelId'],
            'lat': hotel['geoCode']['latitude'],
            'lng': hotel['geoCode']['longitude'],
            // Hotels usually don't have photos in this lightweight API,
            // so we'll use a placeholder in the UI.
          };
        }).toList();
      }
    } catch (e) {
      print("🏨 Hotel Search Error: $e");
    }
    return [];
  }

  // 🏙️ FIND CITY CODE (e.g., "Paris" -> "PAR")
  static Future<String?> getCityCode(String cityName) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final url = 'https://test.api.amadeus.com/v1/reference-data/locations'
          '?subType=CITY'
          '&keyword=$cityName'
          '&page[limit]=1';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'].isNotEmpty) {
          return data['data'][0]['iataCode']; // Returns "PAR", "TYO", etc.
        }
      }
    } catch (e) {
      print("City Code Error: $e");
    }
    return null;
  }

}