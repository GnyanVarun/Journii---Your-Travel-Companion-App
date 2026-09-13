import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
    final destination = LatLng(
      widget.item.latitude!,
      widget.item.longitude!,
    );

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
    final destination = LatLng(
      widget.item.latitude!,
      widget.item.longitude!,
    );

    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    // --------------------------------------------------
    // DYNAMIC THEME COLORS
    // --------------------------------------------------
    final accentColor = isDark
        ? const Color(0xFF00E5FF)
        : const Color(0xFF2E3192);

    final accentForeground =
    isDark ? Colors.black : Colors.white;

    // --------------------------------------------------
    // CARTO API KEY
    // --------------------------------------------------
    //
    // The key is stored in the .env file as:
    //
    // CARTO_API_KEY=your_actual_key
    //
    final cartoApiKey = dotenv.env['CARTO_API_KEY'] ?? '';

    // --------------------------------------------------
    // DYNAMIC CARTO MAP TILES
    // --------------------------------------------------
    //
    // Dark mode  -> CARTO Dark Matter
    // Light mode -> CARTO Positron
    //
    // This keeps the original Journii map style.
    //
    final tileUrl = isDark
        ? 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key=$cartoApiKey'
        : 'https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png?key=$cartoApiKey';

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: destination,
            initialZoom: 13,
            // interactionOptions: const InteractionOptions(
            //   flags: InteractiveFlag.all,
            // ),
          ),
          children: [
            // --------------------------------------------------
            // CARTO MAP TILES
            // --------------------------------------------------
            TileLayer(
              urlTemplate: tileUrl,
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.journii.app',
            ),

            // --------------------------------------------------
            // PREMIUM ROUTE LINE
            // --------------------------------------------------
            if (_route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  // Outer stroke for visibility
                  Polyline(
                    points: _route,
                    strokeWidth: 8,
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.white.withOpacity(0.6),
                  ),

                  // Inner colored route
                  Polyline(
                    points: _route,
                    strokeWidth: 5,
                    color: accentColor,
                  ),
                ],
              ),

            // --------------------------------------------------
            // PREMIUM CUSTOM MARKERS
            // --------------------------------------------------
            MarkerLayer(
              markers: [
                // --------------------------------------------------
                // START: CURRENT GPS LOCATION
                // --------------------------------------------------
                Marker(
                  point: widget.currentLocation,
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF)
                              .withOpacity(0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),

                // --------------------------------------------------
                // END: DESTINATION PIN
                // --------------------------------------------------
                Marker(
                  point: destination,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
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
                      color: accentForeground,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            // --------------------------------------------------
            // CARTO / OPENSTREETMAP ATTRIBUTION
            // --------------------------------------------------
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                ),
                TextSourceAttribution(
                  'CARTO',
                ),
              ],
            ),
          ],
        ),

        // --------------------------------------------------
        // NOTE:
        // The bottom floating container that previously
        // displayed distance/time remains removed.
        //
        // RoutePreviewSheet already displays that information
        // in the premium glassmorphic dashboard.
        // --------------------------------------------------
      ],
    );
  }
}