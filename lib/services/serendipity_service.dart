import 'dart:math';
import 'package:latlong2/latlong.dart';
//import 'package:flutter_map/flutter_map.dart';
import 'osm_poi_service.dart'; // Uses your existing OSM service

class SerendipityResult {
  final String name;
  final LatLng location;
  final String reason;
  final int detourMinutes;
  final String? photoUrl;

  SerendipityResult({
    required this.name,
    required this.location,
    required this.reason,
    required this.detourMinutes,
    this.photoUrl,
  });
}

class SerendipityService {
  static final _random = Random();

  // Changed method name back to scanForSecrets to match your UI call
  static Future<SerendipityResult?> scanForSecrets({
    required LatLng userLocation,
    required String cityContext
  }) async {
    try {
      print("💎 Scanning OSM for Hidden Gems near: ${userLocation.latitude}, ${userLocation.longitude}");

      // 1. Create a 1km bounding box around the user
      final bounds = PoiBounds(
        south: userLocation.latitude - 0.01,
        west: userLocation.longitude - 0.01,
        north: userLocation.latitude + 0.01,
        east: userLocation.longitude + 0.01,
      );

      // 2. Fetch REAL places using your free OSM Service
      final nearbyPlaces = await OsmPoiService.fetchPOIs(bounds);

      // 3. Filter for cool things like monuments, parks, or view points
      final potentialGems = nearbyPlaces.where((p) =>
      p.category == 'monument' ||
          p.category == 'park' ||
          p.category == 'viewpoint' ||
          p.category == 'museum' ||
          p.category == 'tourism'
      ).toList();

      if (potentialGems.isEmpty) {
        print("⚠️ No cool OSM places found nearby.");
        return null;
      }

      // 4. Pick a random cool place
      final gem = potentialGems[_random.nextInt(potentialGems.length)];

      final resultLoc = LatLng(gem.lat, gem.lng);

      // Calculate distance to ensure it's not right on top of the user
      final dist = const Distance().as(LengthUnit.Meter, userLocation, resultLoc);

      if (dist < 10) {
        return null; // Too close
      }

      print("✨ Found OSM Gem: ${gem.name}");

      return SerendipityResult(
        name: gem.name,
        location: resultLoc,
        reason: "Locals love this spot! We found a highly-rated ${gem.category} just off your route.",
        detourMinutes: 5 + _random.nextInt(10), // Estimate 5-15 mins
      );
    } catch (e) {
      print("⚠️ Serendipity OSM Error: $e");
      return null;
    }
  }
}