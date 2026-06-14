import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_preview_service.dart';
import 'itinerary_item_model.dart';

class RoutePreviewMapView extends StatefulWidget {
  final ItineraryItem item;
  final LatLng currentLocation;

  const RoutePreviewMapView({
    super.key,
    required this.item,
    required this.currentLocation,
  });

  @override
  State<RoutePreviewMapView> createState() => _RoutePreviewMapViewState();
}

class _RoutePreviewMapViewState extends State<RoutePreviewMapView> {
  List<LatLng> _route = [];
  double? _distanceKm;
  double? _durationMin;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final destination = LatLng(widget.item.latitude!, widget.item.longitude!);

    final result = await RoutePreviewService.fetchRoute(
      start: widget.currentLocation,
      end: destination,
    );

    if (result == null) return;

    if (mounted) {
      setState(() {
        _route = result.points;
        _distanceKm = result.distanceKm;
        _durationMin = result.durationMin;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = LatLng(widget.item.latitude!, widget.item.longitude!);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🟢 DYNAMIC THEME COLORS: Replaces the hardcoded purple for the map elements!
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    // 🟢 DYNAMIC MAP TILES: Switches between light and dark modes perfectly
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: destination,
            initialZoom: 13,
            // interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            // 🟢 PREMIUM MAP TILES
            TileLayer(
              urlTemplate: tileUrl,
              subdomains: const ['a', 'b', 'c', 'd'],
            ),

            // 🟢 PREMIUM ROUTE LINE
            if (_route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  // Outer stroke for visibility (white glow effect)
                  Polyline(
                    points: _route,
                    strokeWidth: 8,
                    color: isDark ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.6),
                  ),
                  // Inner colored route
                  Polyline(
                    points: _route,
                    strokeWidth: 5,
                    color: accentColor, // 🟢 FIXED: Follows dynamic theme logic
                  ),
                ],
              ),

            // 🟢 PREMIUM CUSTOM MARKERS
            MarkerLayer(
              markers: [
                // Start: Glowing GPS Dot
                Marker(
                  point: widget.currentLocation,
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF), // GPS Blue
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withOpacity(0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                // End: Destination Pin
                Marker(
                  point: destination,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter, // Points exactly at the coordinate
                  child: Container(
                    decoration: BoxDecoration(
                      color: accentColor, // 🟢 FIXED: Follows dynamic theme logic
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      color: accentForeground, // 🟢 FIXED: Contrast dynamically updates
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // 🟢 NOTE: The bottom floating container that displayed distance/time was removed.
        // It was visually clashing with the massive, premium glassmorphic dashboard
        // we built in the parent `RoutePreviewSheet` which already displays that data!
      ],
    );
  }
}