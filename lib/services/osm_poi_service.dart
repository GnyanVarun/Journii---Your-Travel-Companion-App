import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
//import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PoiBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  PoiBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}

class OsmPoiService {
  // 🔄 SERVER ROTATION
  static final List<String> _servers = [
    'https://overpass-api.de/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
    'https://z.overpass-api.de/api/interpreter',
  ];
  static int _serverIndex = 0;

  /// Fetches POIs within a bounding box using a rotated server
  static Future<List<PoiModel>> fetchPOIs(PoiBounds bounds) async  {
    final serverUrl = _servers[_serverIndex];
    _serverIndex = (_serverIndex + 1) % _servers.length;

    final s = bounds.south;
    final w = bounds.west;
    final n = bounds.north;
    final e = bounds.east;

    // 🟢 UPDATED QUERY: Added place_of_worship, car, and motorcycle
    String query = """
    [out:json][timeout:5];
    (
      node["amenity"~"restaurant|cafe|fast_food|bar|pub|hospital|clinic|pharmacy|fuel|cinema|bank|atm|place_of_worship"]($s,$w,$n,$e);
      node["shop"~"supermarket|convenience|mall|department_store|car|motorcycle"]($s,$w,$n,$e);
      node["tourism"~"hotel|hostel|motel|museum|viewpoint"]($s,$w,$n,$e);
      node["building"~"office|commercial|apartments|residential"]["name"]($s,$w,$n,$e);
      node["office"]($s,$w,$n,$e);
    );
    out center 50; 
  """;

    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {
          'User-Agent': 'JourniiTravelApp/1.0',
          'Accept': '*/*',
        },
        body: {'data': query},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List;

        return elements.map((e) => PoiModel.fromJson(e)).toList();
      } else {
        print("⚠️ OSM Error ${response.statusCode} from $serverUrl");
      }
    } catch (e) {
      print("⚠️ POI Fetch Error: $e");
    }
    return [];
  }

  // --------------------------------------------------
  // 🌳 STEP 1: WANDER ENGINE
  // --------------------------------------------------
  static Future<List<LatLng>?> getWanderWaypoints({
    required LatLng start,
    required LatLng end,
    required String theme,
  }) async {
    final distanceCalc = const Distance();
    final directDistance = distanceCalc.as(LengthUnit.Meter, start, end);

    if (directDistance < 800) return null;

    final bounds = PoiBounds(
      south: math.min(start.latitude, end.latitude) - 0.015,
      west: math.min(start.longitude, end.longitude) - 0.015,
      north: math.max(start.latitude, end.latitude) + 0.015,
      east: math.max(start.longitude, end.longitude) + 0.015,
    );

    try {
      final rawPlaces = await fetchPOIs(bounds);

      List<PoiModel> themePlaces = [];
      if (theme == 'scenic') {
        themePlaces = rawPlaces.where((p) => p.category == 'viewpoint' || p.category == 'park' || p.category == 'tourism').toList();
      } else if (theme == 'foodie') {
        themePlaces = rawPlaces.where((p) => p.category == 'cafe' || p.category == 'restaurant' || p.category == 'fast_food' || p.category == 'pub').toList();
      } else if (theme == 'culture') {
        // 🟢 NEW: Added religious sites to the culture filter!
        themePlaces = rawPlaces.where((p) =>
        p.category == 'museum' ||
            p.category == 'cinema' ||
            p.category == 'monument' ||
            p.category == 'place_of_worship' ||
            p.category == 'hindu' ||
            p.category == 'muslim' ||
            p.category == 'christian' ||
            p.category == 'buddhist'
        ).toList();
      }

      if (themePlaces.isEmpty) return null;

      PoiModel? bestStop;
      double minDetourScore = double.infinity;

      for (var place in themePlaces) {
        final placeLoc = LatLng(place.lat, place.lng);

        final detourDistance = distanceCalc.as(LengthUnit.Meter, start, placeLoc) +
            distanceCalc.as(LengthUnit.Meter, placeLoc, end);

        final extraDistance = detourDistance - directDistance;

        if (extraDistance < (directDistance * 0.60)) {
          if (extraDistance < minDetourScore) {
            minDetourScore = extraDistance;
            bestStop = place;
          }
        }
      }

      if (bestStop != null) {
        print("🌳 WANDER ROUTE: Injecting ${bestStop.name} (Adds ${minDetourScore.round()}m extra)");
        return [LatLng(bestStop.lat, bestStop.lng)];
      }

      return null;
    } catch (e) {
      print("Wander Engine Error: $e");
      return null;
    }
  }
}

// 📦 THE MODEL
class PoiModel {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String category;

  PoiModel({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
  });

  factory PoiModel.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'] ?? {};

    // 🟢 NEW: Smart Category Detection (Prioritize Religion)
    String cat = "place";
    if (tags.containsKey('religion')) cat = tags['religion']; // Grabs 'hindu', 'muslim', etc.
    else if (tags.containsKey('amenity')) cat = tags['amenity'];
    else if (tags.containsKey('shop')) cat = tags['shop'];
    else if (tags.containsKey('tourism')) cat = tags['tourism'];

    return PoiModel(
      id: json['id'].toString(),
      name: tags['name'] ?? 'Unknown Place',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lon'] as num).toDouble(),
      category: cat,
    );
  }
}