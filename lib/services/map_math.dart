import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class MapMath {
  // 🧲 SNAP TO ROUTE: Finds the closest point on the polyline to the user's raw location
  static LatLng snapToRoute(LatLng rawLocation, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return rawLocation;

    double minDistance = double.infinity;
    LatLng closestPoint = rawLocation;

    // We check every segment of the route (A -> B)
    for (int i = 0; i < routePoints.length - 1; i++) {
      final start = routePoints[i];
      final end = routePoints[i + 1];

      final projected = _getProjectedPoint(rawLocation, start, end);
      final distance = _getDistance(rawLocation, projected);

      // If this part of the road is closer, snap to it!
      if (distance < minDistance) {
        minDistance = distance;
        closestPoint = projected;
      }
    }

    // 🛑 SAFETY: If the user is too far (>50m) from the route, don't snap.
    // They might be off-road or taking a detour.
    if (minDistance > 0.0005) { // Approx 50 meters
      return rawLocation;
    }

    return closestPoint;
  }

  // 📐 BEARING: Calculates the angle of the car based on the route (not the compass)
  static double calculateRouteBearing(LatLng start, LatLng end) {
    final dLon = (end.longitude - start.longitude) * (math.pi / 180.0);
    final lat1 = start.latitude * (math.pi / 180.0);
    final lat2 = end.latitude * (math.pi / 180.0);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (bearing * (180.0 / math.pi) + 360.0) % 360.0;
  }

  // --- Internal Math Helpers ---

  static LatLng _getProjectedPoint(LatLng p, LatLng a, LatLng b) {
    double apX = p.latitude - a.latitude;
    double apY = p.longitude - a.longitude;
    double abX = b.latitude - a.latitude;
    double abY = b.longitude - a.longitude;

    double ab2 = abX * abX + abY * abY;
    double ap_ab = apX * abX + apY * abY;
    double t = ap_ab / ab2;

    if (t < 0) return a;
    if (t > 1) return b;

    return LatLng(a.latitude + abX * t, a.longitude + abY * t);
  }

  static double _getDistance(LatLng a, LatLng b) {
    return math.sqrt(math.pow(a.latitude - b.latitude, 2) +
        math.pow(a.longitude - b.longitude, 2));
  }

  // 📐 CALCULATE BEARING (Angle between two GPS points)
  static double calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * (math.pi / 180.0);
    final long1 = start.longitude * (math.pi / 180.0);
    final lat2 = end.latitude * (math.pi / 180.0);
    final long2 = end.longitude * (math.pi / 180.0);

    final dLon = long2 - long1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearingRadians = math.atan2(y, x);
    final bearingDegrees = bearingRadians * (180.0 / math.pi);

    // Normalize to 0-360 degrees
    return (bearingDegrees + 360.0) % 360.0;
  }

  // 📏 SIMPLE DISTANCE (Euclidean approximation for short distances)
  static double getDistance(LatLng p1, LatLng p2) {
    return math.sqrt(math.pow(p1.latitude - p2.latitude, 2) +
        math.pow(p1.longitude - p2.longitude, 2));
  }
}