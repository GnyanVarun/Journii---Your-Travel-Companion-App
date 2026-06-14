import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ✅ Now this will work

class LiveDataService {

  // 1. 🌤️ GET LIVE WEATHER (Open-Meteo)
  Future<String> getWeatherContext(double lat, double lng) async {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current_weather'];

        final temp = current['temperature'];
        final code = current['weathercode']; // WMO Code

        final desc = _getWeatherDescription(code);
        return "$desc • $temp°C";
      }
    } catch (e) {
      print("Open-Meteo Error: $e");
    }
    return "Weather unavailable";
  }

  // 2. 🚗 GET OSRM ROUTE STATS
  Future<Map<String, dynamic>?> getOsrmRouteStats(LatLng origin, LatLng dest) async {
    final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${dest.longitude},${dest.latitude}?overview=false'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          return {
            "duration": (route['duration'] / 60).round(), // Minutes
            "distance": (route['distance'] / 1000).toStringAsFixed(1) // Km
          };
        }
      }
    } catch (e) {
      print("OSRM Error: $e");
    }
    return null;
  }

  // 3. 🚌 GET TRANSIT DEPARTURE (Transitland)
  // 3. 🚌 GET TRANSIT SCHEDULE (Smart 2-Step)
  Future<String> getTransitDeparture(double lat, double lng) async {
    final String apiKey = dotenv.env['TRANSITLAND_API_KEY'] ?? "";
    if (apiKey.isEmpty) return "Config Error";

    // ------------------------------------------
    // STEP 1: FIND THE NEAREST STOP ID
    // ------------------------------------------
    final stopUrl = Uri.parse(
        'https://transit.land/api/v2/rest/stops?lat=$lat&lon=$lng&radius=500&limit=1&apikey=$apiKey'
    );

    try {
      final response = await http.get(stopUrl);
      if (response.statusCode != 200) return "Schedule unavailable";

      final data = jsonDecode(response.body);
      if (data['stops'] == null || data['stops'].isEmpty) {
        return "No transit nearby";
      }

      final stop = data['stops'][0];
      final String stopId = stop['onestop_id'];
      final String stopName = stop['stop_name'];

      // ------------------------------------------
      // STEP 2: GET DEPARTURES FOR THIS STOP
      // ------------------------------------------
      // We ask for departures starting "now"
      final now = DateTime.now().toIso8601String();

      final depUrl = Uri.parse(
          'https://transit.land/api/v2/rest/stops/$stopId/departures?start_time=$now&limit=3&apikey=$apiKey'
      );

      final depResponse = await http.get(depUrl);

      if (depResponse.statusCode == 200) {
        final depData = jsonDecode(depResponse.body);

        // Check if we have departures
        if (depData['stops'] != null &&
            depData['stops'].isNotEmpty &&
            depData['stops'][0]['departures'].isNotEmpty) {

          // Get the very first departure time string (e.g. "14:35:00")
          String timeStr = depData['stops'][0]['departures'][0]['arrival']['time'].toString();

          // Clean it up: "14:35:00" -> "14:35"
          if (timeStr.length > 5) {
            timeStr = timeStr.substring(0, 5);
          }

          // ✅ RETURN: "Next: 14:35 • Champ de Mars"
          return "Next: $timeStr • $stopName";
        }
      }

      // Fallback: If no schedule found (common in some areas), just show the name
      return "Stop: $stopName";

    } catch (e) {
      print("Transit Error: $e");
      return "Transit info unavailable";
    }
  }

  // 📖 Helper: Translate WMO Codes
  String _getWeatherDescription(int code) {
    if (code == 0) return "Clear Sky ☀️";
    if (code >= 1 && code <= 3) return "Cloudy ☁️";
    if (code >= 45 && code <= 48) return "Foggy 🌫️";
    if (code >= 51 && code <= 67) return "Rainy 🌧️";
    if (code >= 71 && code <= 77) return "Snowy ❄️";
    if (code >= 95) return "Stormy ⚡";
    return "Unknown";
  }
}