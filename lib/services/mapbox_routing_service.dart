import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// --------------------------------------------------
/// 🧭 TURN-BY-TURN STEP MODEL
/// --------------------------------------------------
class RouteStep {
  final String instruction;
  final LatLng location;
  final double distanceMeters;

  RouteStep({
    required this.instruction,
    required this.location,
    required this.distanceMeters,
  });
}

/// --------------------------------------------------
/// 📦 ROUTE RESULT
/// --------------------------------------------------
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;
  final List<RouteStep> steps;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    required this.steps,
  });
}

/// --------------------------------------------------
/// 🗺️ MAPBOX DIRECTIONS SERVICE
/// --------------------------------------------------
class MapboxRoutingService {

  /// Use the same public token you're already using in Journii.
  static String get _accessToken => dotenv.env['MAPBOX_PUBLIC_TOKEN'] ?? '';

  static const String _baseUrl =
      'https://api.mapbox.com/directions/v5/mapbox/driving-traffic';

  static Future<RouteResult?> getRoute({
    required LatLng from,
    required LatLng to,
    List<LatLng>? waypoints,
  }) async {
    try {

      // --------------------------------------------------
      // 🛡️ COORDINATE VALIDATION
      // --------------------------------------------------
      if (!_isValidCoordinate(from) ||
          !_isValidCoordinate(to)) {
        print('❌ Invalid coordinates supplied');
        return null;
      }

      // --------------------------------------------------
      // 📍 BUILD COORDINATES STRING
      // --------------------------------------------------
      final allPoints = <LatLng>[
        from,
        if (waypoints != null) ...waypoints,
        to,
      ];

      final coordinatesString = allPoints
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');

      // --------------------------------------------------
      // 🌍 MAPBOX DIRECTIONS URL
      // --------------------------------------------------
      final url =
          '$_baseUrl/'
          '$coordinatesString'
          '?alternatives=false'
          '&steps=true'
          '&geometries=geojson'
          '&overview=full'
          '&voice_instructions=true'
          '&banner_instructions=true'
          '&access_token=$_accessToken';

      print('🧭 MAPBOX ROUTE URL: $url');

      final response = await http.get(
        Uri.parse(url),
      );

      if (response.statusCode != 200) {
        print(
            '❌ Mapbox Directions failed: ${response.statusCode}');
        print(response.body);
        return null;
      }

      final data = jsonDecode(response.body);

      if (data['routes'] == null ||
          data['routes'].isEmpty) {
        print('❌ No routes returned');
        return null;
      }

      final route = data['routes'][0];

      print(
          'GEOMETRY_COORDS='
              '${route['geometry']['coordinates'].length}'
      );

      // --------------------------------------------------
      // 📍 ROUTE GEOMETRY
      // --------------------------------------------------
      final geometry =
      route['geometry']['coordinates'] as List?;

      if (geometry == null || geometry.isEmpty) {
        print('❌ Route geometry missing');
        return null;
      }

      final List<LatLng> points =
      geometry.map<LatLng>((coord) {
        return LatLng(
          (coord[1] as num).toDouble(),
          (coord[0] as num).toDouble(),
        );
      }).toList();

      // --------------------------------------------------
      // 📏 DISTANCE & DURATION
      // --------------------------------------------------
      final distanceMeters =
      (route['distance'] as num).toDouble();

      final durationSeconds =
      (route['duration'] as num).toDouble();

      // --------------------------------------------------
      // 🧭 TURN-BY-TURN STEPS
      // --------------------------------------------------
      final List<RouteStep> steps = [];

      final legs = route['legs'] as List? ?? [];

      for (final leg in legs) {

        final legSteps =
            leg['steps'] as List? ?? [];

        for (final step in legSteps) {

          final maneuver =
          step['maneuver'];

          if (maneuver == null) continue;

          final location =
          maneuver['location'];

          if (location == null ||
              location.length < 2) {
            continue;
          }

          final lat =
          (location[1] as num).toDouble();

          final lon =
          (location[0] as num).toDouble();

          String instruction = 'Continue';

          // --------------------------------------------------
          // 🧠 MAPBOX INSTRUCTION EXTRACTION
          // --------------------------------------------------
          if (maneuver['instruction'] != null) {
            instruction =
                maneuver['instruction']
                    .toString();
          } else if (step['name'] != null &&
              step['name'].toString().isNotEmpty) {
            instruction =
            'Continue on ${step['name']}';
          }

          steps.add(
            RouteStep(
              instruction: instruction,
              location: LatLng(lat, lon),
              distanceMeters:
              (step['distance'] as num?)
                  ?.toDouble() ??
                  0,
            ),
          );
        }
      }

      print(
          '✅ Route loaded | '
              '${distanceMeters / 1000} km | '
              '${steps.length} steps');

      print(
          'MAPBOX_ROUTE_POINTS=${points.length}'
      );

      return RouteResult(
        points: points,
        distanceKm: distanceMeters / 1000,
        durationMin: durationSeconds / 60,
        steps: steps,
      );

    } catch (e, stack) {
      print('🔥 Mapbox Directions Error: $e');
      print(stack);
      return null;
    }
  }

  /// --------------------------------------------------
  /// 🛡️ COORDINATE SANITY CHECK
  /// --------------------------------------------------
  static bool _isValidCoordinate(
      LatLng coordinate) {
    return coordinate.latitude >= -90 &&
        coordinate.latitude <= 90 &&
        coordinate.longitude >= -180 &&
        coordinate.longitude <= 180;
  }
}