import 'dart:convert';
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
/// 🚗 ROUTING SERVICE (OSRM – FREE)
/// --------------------------------------------------
class RoutingService {
  static const String _baseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  static Future<RouteResult?> getRoute({
    required LatLng from,
    required LatLng to,
    List<LatLng>? waypoints, // 🔵 NEW: Optional stops
  }) async {
    try {
      // --------------------------------------------------
      // 🛡️ COORDINATE VALIDATION
      // --------------------------------------------------
      if (!_isValidCoordinate(from) || !_isValidCoordinate(to)) {
        print('❌ Invalid coordinates passed to routing');
        return null;
      }

      // 🔵 NEW: Compile the full list of points
      final allPoints = <LatLng>[
        from,
        if (waypoints != null) ...waypoints,
        to,
      ];

      // 🔵 NEW: Format as "lon,lat;lon,lat;lon,lat"
      final coordinatesString = allPoints
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');

      final url =
          '$_baseUrl/'
          '$coordinatesString' // 🔵 NEW: Use the dynamic string
          '?overview=full'
          '&geometries=geojson'
          '&steps=true';

      print('🧭 Routing URL: $url');

      final response = await http.get(Uri.parse(url));

      // ... The rest of your JSON parsing code stays exactly the same from here down!
      if (response.statusCode != 200) {
        print('❌ Routing API failed: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);

      if (data['routes'] == null || data['routes'].isEmpty) {
        print('❌ No routes returned');
        return null;
      }

      final route = data['routes'][0];

      // --------------------------------------------------
      // 📍 POLYLINE GEOMETRY
      // --------------------------------------------------
      final geometry = route['geometry']['coordinates'] as List?;

      if (geometry == null || geometry.length < 3) {
        print('⚠️ Weak geometry received, ignoring route');
        return null;
      }

      final List<LatLng> points = geometry.map<LatLng>((coord) {
        return LatLng(
          (coord[1] as num).toDouble(),
          (coord[0] as num).toDouble(),
        );
      }).toList();

      // --------------------------------------------------
      // 📏 DISTANCE & TIME
      // --------------------------------------------------
      final distanceMeters = (route['distance'] as num).toDouble();
      final durationSeconds = (route['duration'] as num).toDouble();

      // --------------------------------------------------
      // 🧭 TURN-BY-TURN STEPS
      // --------------------------------------------------
      final List<RouteStep> steps = [];

      final legs = route['legs'] as List? ?? [];
      for (final leg in legs) {
        final legSteps = leg['steps'] as List? ?? [];

        for (final step in legSteps) {
          final maneuver = step['maneuver'];
          final location = maneuver?['location'];

          if (location == null || location.length < 2) continue;

          final lat = (location[1] as num).toDouble();
          final lon = (location[0] as num).toDouble();

          steps.add(
            RouteStep(
              instruction: _buildInstruction(step),
              location: LatLng(lat, lon),
              distanceMeters:
              (step['distance'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }

      // --------------------------------------------------
      // 🛡️ ENSURE ROUTE IS DRAWABLE
      // --------------------------------------------------
      if (points.length < 3 && steps.length >= 2) {
        print('⚠️ Rebuilding route from steps');
        points
          ..clear()
          ..addAll(steps.map((s) => s.location));
      }

      if (points.length < 3) {
        print('❌ Route not drawable, aborting');
        return null;
      }

      return RouteResult(
        points: points,
        distanceKm: distanceMeters / 1000,
        durationMin: durationSeconds / 60,
        steps: steps,
      );
    } catch (e) {
      print('🔥 Routing exception: $e');
      return null;
    }
  }

  // --------------------------------------------------
  // 🧠 HUMAN-FRIENDLY INSTRUCTION BUILDER
  // --------------------------------------------------
  // --------------------------------------------------
  // 🧠 IMPROVED INSTRUCTION BUILDER (Fixes Flyovers)
  // --------------------------------------------------
  static String _buildInstruction(dynamic step) {
    final maneuver = step['maneuver'] ?? {};
    final type = maneuver['type'] ?? '';
    final modifier = maneuver['modifier'];
    final name = step['name'] ?? '';
    final ref = step['ref']; // Road numbers like "NH 44" or "ORR"

    // Helper to add road name if available
    String withName(String base) {
      if (name.isNotEmpty) return "$base onto $name";
      if (ref != null) return "$base onto $ref";
      return base;
    }

    switch (type) {
      case 'turn':
        String direction = modifier ?? 'turn';
        // Capitalize specific turns
        if (direction == 'sharp right') direction = 'Sharp Right';
        if (direction == 'sharp left') direction = 'Sharp Left';
        return withName('Turn $direction');

      case 'new name':
        return withName('Continue');

      case 'depart':
        return withName('Start');

      case 'arrive':
        return 'You have arrived at your destination';

      case 'roundabout':
      case 'rotary':
        final exit = maneuver['exit'];
        if (exit != null) {
          return 'At roundabout, take exit $exit';
        }
        return 'Enter roundabout';

      case 'merge':
        final dir = modifier ?? 'left';
        return withName('Merge $dir');

    // 🚀 THE FLYOVER FIXES:
      case 'ramp':
      case 'on ramp':
      // "Take the ramp" usually implies entering a highway or flyover
        return withName('Take the ramp');

      case 'off ramp':
        return withName('Take exit');

      case 'fork':
      // "Fork Right" often means "Keep right to take the flyover"
        final dir = modifier ?? '';
        if (dir.contains('right')) return withName('Keep Right');
        if (dir.contains('left')) return withName('Keep Left');
        return withName('Keep $dir');

      case 'suppressed':
      // This is a subtle instruction (like "Go straight" at a confusing junction)
        return withName('Go straight');

      default:
      // If we don't know the type, try to use the modifier
        if (modifier != null && modifier.isNotEmpty) {
          return withName('$type $modifier');
        }
        return withName('Continue');
    }
  }

  // --------------------------------------------------
  // 🛡️ COORDINATE SANITY CHECK
  // --------------------------------------------------
  static bool _isValidCoordinate(LatLng c) {
    return c.latitude >= -90 &&
        c.latitude <= 90 &&
        c.longitude >= -180 &&
        c.longitude <= 180;
  }
}
