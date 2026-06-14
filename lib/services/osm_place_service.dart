import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/trips/place_live_data.dart';

class OsmPlaceService {
  static final List<String> _servers = [
    'https://overpass-api.de/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
    'https://z.overpass-api.de/api/interpreter',
  ];
  static int _serverIndex = 0;

  static Future<PlaceLiveData?> fetchPlaceData({
    required double lat,
    required double lon,
    required String placeName,
  }) async {
    final endpoint = _servers[_serverIndex];
    _serverIndex = (_serverIndex + 1) % _servers.length;

    try {
      final query = '''
[out:json][timeout:10];
(
  node(around:150,$lat,$lon);
  way(around:150,$lat,$lon);
  relation(around:150,$lat,$lon);
);
out tags center;
''';

      final response = await http.post(
        Uri.parse(endpoint),
        headers: const {'Content-Type': 'text/plain'},
        body: query,
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final elements = data['elements'] as List?;

      if (elements == null || elements.isEmpty) return null;

      Map<String, dynamic>? bestTags;
      int bestScore = -999;

      for (final el in elements) {
        final tags = el['tags'];
        if (tags == null) continue;

        int score = 10;

        // 1. CASE-INSENSITIVE NAME MATCH (Boosts the exact place)
        final tagName = tags['name']?.toString().toLowerCase() ?? '';
        final searchName = placeName.toLowerCase();

        if (tagName == searchName) {
          score += 1000;
        } else if (tagName.contains(searchName) || searchName.contains(tagName)) {
          // Partial match just in case (e.g., "PVR Nexus Mall" vs "Nexus Mall")
          score += 500;
        }

        // 🟢 2. THE DATA GRAVITY PULL!
        // If this element actually possesses the data we are looking for, pull it to the top!
        if (tags.containsKey('opening_hours')) {
          score += 800; // Massive boost! We want the hours!
        }
        if (tags.containsKey('website') || tags.containsKey('contact:website')) {
          score += 400; // Big boost for website!
        }

        // 3. Standard Priority Scoring
        if (tags['tourism'] == 'attraction' || tags['tourism'] == 'museum' || tags['tourism'] == 'landmark') {
          score += 100;
        } else if (tags.containsKey('historic')) {
          score += 90;
        } else if (tags['amenity'] == 'restaurant' || tags['amenity'] == 'cafe' || tags['amenity'] == 'bar' || tags['amenity'] == 'cinema' || tags['shop'] == 'mall') {
          score += 70;
        } else if (tags['amenity'] == 'place_of_worship' || tags['shop'] == 'car' || tags['shop'] == 'motorcycle') {
          // 🟢 NEW: Boost religious sites and auto showrooms!
          score += 70;
        }

        // ❌ Infrastructure / noise (explicitly deprioritized)
        if (tags['amenity'] == 'post_box' || tags['amenity'] == 'waste_basket' || tags['amenity'] == 'parking') {
          score -= 1000;
        }

        // Debug log so you can see exactly how it scored!
        debugPrint('🔍 OSM SCORING -> Name: ${tags['name']} | Hours: ${tags['opening_hours']} | Final Score: $score');

        if (score > bestScore) {
          bestScore = score;
          bestTags = Map<String, dynamic>.from(tags);
        }
      }

      if (bestTags == null || bestScore < 0) return null;

      // 🟢 NEW: Add bestTags['religion'] to the very front!
      // This ensures OSM returns "hindu", "muslim", or "christian" instead of just "place_of_worship"
      final category = bestTags['religion'] ?? bestTags['tourism'] ?? bestTags['historic'] ?? bestTags['amenity'] ?? bestTags['shop'];

      return PlaceLiveData(
        category: category,
        openingHours: bestTags['opening_hours'],
        website: bestTags['website'] ?? bestTags['contact:website'],
        address: _buildAddress(bestTags),
      );
    } catch (e) {
      return null;
    }
  }

  static String? _buildAddress(Map<String, dynamic> tags) {
    final parts = <String>[];
    final city = tags['addr:city:en'] ?? tags['addr:city'];
    final country = tags['addr:country:en'] ?? tags['addr:country'];

    if (tags['addr:housenumber'] != null && tags['addr:street'] != null) {
      parts.add('${tags['addr:housenumber']} ${tags['addr:street']}');
    } else if (tags['addr:street'] != null) {
      parts.add(tags['addr:street']);
    }

    if (city != null) parts.add(city);
    if (country != null) parts.add(country);

    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}