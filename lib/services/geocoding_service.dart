import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static const _baseUrl =
      'https://nominatim.openstreetmap.org/search';

  /// Converts a place name into latitude & longitude
  /// Returns null if not found OR if a network error occurs
  static Future<LatLngResult?> geocode(String placeName) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'q': placeName,
        'format': 'json',
        'limit': '1',
      });

      final response = await http.get(
        uri,
        headers: {
          // REQUIRED by Nominatim usage policy
          'User-Agent': 'journii-app/1.0 (contact@journii.app)',
        },
      );

      if (response.statusCode != 200) return null;

      final List data = jsonDecode(response.body);

      if (data.isEmpty) return null;

      return LatLngResult(
        latitude: double.parse(data[0]['lat']),
        longitude: double.parse(data[0]['lon']),
      );
    } catch (e) {
      // 🛡️ Safety: Returns null on network failure instead of crashing the app
      print("Geocoding Error: $e");
      return null;
    }
  }
}

class LatLngResult {
  final double latitude;
  final double longitude;

  LatLngResult({
    required this.latitude,
    required this.longitude,
  });
}