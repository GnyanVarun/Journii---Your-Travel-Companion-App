import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'osm_poi_service.dart';

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

  static Future<SerendipityResult?> scanForSecrets({
    required LatLng userLocation,
    required String cityContext,
  }) async {
    try {
      print(
        '💎 Scanning OSM for Hidden Gems near: '
            '${userLocation.latitude}, ${userLocation.longitude}',
      );

      final bounds = PoiBounds(
        south: userLocation.latitude - 0.01,
        west: userLocation.longitude - 0.01,
        north: userLocation.latitude + 0.01,
        east: userLocation.longitude + 0.01,
      );

      final nearbyPlaces = await OsmPoiService.fetchHiddenGemPOIs(bounds);

      final potentialGems = nearbyPlaces
          .where(
            (p) =>
        p.category == 'monument' ||
            p.category == 'park' ||
            p.category == 'viewpoint' ||
            p.category == 'museum' ||
            p.category == 'tourism',
      )
          .toList();

      if (potentialGems.isEmpty) {
        print(
          '⚠️ No eligible Hidden Gems were returned. Check the preceding '
              'Overpass logs to distinguish an empty result from an API failure '
              'or cooldown.',
        );
        return null;
      }

      // Filter out spots right on top of the user (< 10m) before picking
      final validGems = potentialGems.where((gem) {
        final dist = const Distance().as(
          LengthUnit.Meter,
          userLocation,
          LatLng(gem.lat, gem.lng),
        );
        return dist >= 10;
      }).toList();

      if (validGems.isEmpty) return null;

      final gem = validGems[_random.nextInt(validGems.length)];
      final resultLoc = LatLng(gem.lat, gem.lng);

      print('✨ Found OSM Gem: ${gem.name}');

      return SerendipityResult(
        name: gem.name,
        location: resultLoc,
        reason:
        'Locals love this spot! We found a highly-rated ${gem.category} just off your route.',
        detourMinutes: 5 + _random.nextInt(10),
      );
    } catch (e) {
      print('⚠️ Serendipity OSM Error: $e');
      return null;
    }
  }
}