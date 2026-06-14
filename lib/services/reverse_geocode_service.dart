import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// 🟢 NEW: Import your Live Data model
import '../features/trips/place_live_data.dart';

class ReverseGeocodeService {
  static const _endpoint = 'https://nominatim.openstreetmap.org/reverse';
  static final Map<String, String> _cache = {};

  // Your original method (untouched)
  static Future<String?> getFriendlyLocation({
    required double lat,
    required double lon,
  }) async {
    final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'format': 'json',
        'lat': lat.toString(),
        'lon': lon.toString(),
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'en',
      });

      final res = await http.get(uri, headers: {'User-Agent': 'journii-app/1.0'});
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final addr = data['address'] ?? {};

      final area = addr['city_district'] ?? addr['suburb'] ?? addr['neighbourhood'];
      final city = addr['city'] ?? addr['town'];

      String? label;
      if (area != null && city != null) {
        label = '$area · $city';
      } else if (area != null) {
        label = area;
      } else if (city != null) {
        label = city;
      } else {
        label = addr['road'];
      }

      if (label != null) _cache[key] = label;
      return label;
    } catch (_) {
      return null;
    }
  }

  // 🟢 NEW: The Nominatim "Deep Data" Fetcher
  static Future<PlaceLiveData?> getRichLocationDetails({
    required double lat,
    required double lon,
  }) async {
    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'format': 'json',
        'lat': lat.toString(),
        'lon': lon.toString(),
        'zoom': '18', // Building level zoom
        'addressdetails': '1',
        'extratags': '1', // 👈 THE MAGIC BULLET! Tells Nominatim to fetch hours & website!
        'accept-language': 'en',
      });

      final res = await http.get(uri, headers: {'User-Agent': 'journii-app/1.0'});
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);

      // 1. Get the Address exactly like you did before
      final addr = data['address'] ?? {};
      final parts = <String>[];
      if (addr['house_number'] != null && addr['road'] != null) {
        parts.add('${addr['house_number']} ${addr['road']}');
      } else if (addr['road'] != null) {
        parts.add(addr['road']);
      }
      final city = addr['city'] ?? addr['town'];
      if (city != null) parts.add(city);
      if (addr['country'] != null) parts.add(addr['country']);

      final fullAddress = parts.isNotEmpty ? parts.join(', ') : null;

      // 2. Get the Extra Tags (Hours, Website, etc.)
      final extratags = data['extratags'] ?? {};

      return PlaceLiveData(
        category: data['type'] ?? 'place',
        address: fullAddress,
        openingHours: extratags['opening_hours'],
        website: extratags['website'] ?? extratags['contact:website'],

        // 🟢 NEW: Grabbing the extra data from OSM!
        phone: extratags['phone'] ?? extratags['contact:phone'],
        cuisine: extratags['cuisine'],
        wheelchair: extratags['wheelchair'],
      );

      return PlaceLiveData(
        category: data['type'] ?? 'place',
        address: fullAddress,
        openingHours: extratags['opening_hours'], // 👈 Pulled directly from Nominatim!
        website: extratags['website'] ?? extratags['contact:website'],
      );

    } catch (e) {
      debugPrint("Nominatim Rich Fetch Error: $e");
      return null;
    }
  }
}