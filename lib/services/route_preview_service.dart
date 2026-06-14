import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutePreviewResult {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;

  RoutePreviewResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

class RoutePreviewService {
  static Future<RoutePreviewResult?> fetchRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    final res = await http.get(Uri.parse(url));

    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    final route = data['routes']?[0];
    if (route == null) return null;

    final coords = route['geometry']['coordinates'] as List;

    final points = coords
        .map((c) => LatLng(c[1] as double, c[0] as double))
        .toList();

    return RoutePreviewResult(
      points: points,
      distanceKm: route['distance'] / 1000,
      durationMin: route['duration'] / 60,
    );
  }
}
