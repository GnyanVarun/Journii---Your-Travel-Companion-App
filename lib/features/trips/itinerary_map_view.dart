import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_compass/flutter_compass.dart';

// 🌟 MAPBOX IMPORTS
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart' as ll;

import '../../services/social_drop_service.dart';
import '../../services/unsplash_service.dart';
import 'itinerary_provider.dart';
import 'itinerary_item_model.dart';
import 'place_details_sheet.dart';
import 'navigation_provider.dart';
import '../../services/serendipity_service.dart';
import '../../services/amadeus_service.dart';
import 'package:journii/features/trips/map_poi_sheet.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ItineraryMapView extends ConsumerStatefulWidget {
  final String tripId;
  const ItineraryMapView({super.key, required this.tripId});

  @override
  ConsumerState<ItineraryMapView> createState() => _ItineraryMapViewState();
}

class _ItineraryMapViewState extends ConsumerState<ItineraryMapView> with TickerProviderStateMixin {

  // 🟢 MAPBOX STATE
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _routeManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _textManager;

  mapbox.PolylineAnnotation? _completedRouteAnnotation;
  mapbox.PolylineAnnotation? _remainingRouteAnnotation;

  final Map<String, VoidCallback> _markerTaps = {};

  final String _publicToken = dotenv.env['MAPBOX_PUBLIC_TOKEN'] ?? '';

  static const String _journiiDarkStyle =
      'mapbox://styles/anarchy-son/cmq9gsktv000a01s7hjf48wwe';

  bool _hasFitRouteOnce = false;
  bool _hasFitPinsOnce = false;
  bool _isMapReady = false;
  bool _isNavigating3D = false;

  bool _isUpdatingRoute = false;

  // 🧭 COMPASS & LOCATION STATE
  bool _isCompassMode = false;
  double _sensorHeading = 0.0;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _positionStream;
  ll.LatLng? _cachedUserLocation;
  bool _isAutoCenter = false;
  double _currentSpeed = 0.0;

  ll.LatLng? _previousRouteLocation;
  double _routeLockedBearing = 0.0;

  // 📡 SERENDIPITY STATE
  Timer? _debounceTimer;
  bool _isScanningSerendipity = false;
  ll.LatLng? _lastSerendipityScanLocation;

  List<SocialDrop> _nearbyDrops = [];
  Set<String> _shownDropIds = {};
  Set<String> _collectedDropIds = {};

  // 🟢 Track theme changes to cleanly redraw pins
  bool? _lastDarkTheme;
  bool _isDarkCached = false;

  // ----------------------------------------------------------------
  // 🧭 MATH UTILITY
  // ----------------------------------------------------------------
  double _calculateStrictBearing(ll.LatLng start, ll.LatLng end) {
    final lat1 = start.latitude * (math.pi / 180.0);
    final long1 = start.longitude * (math.pi / 180.0);
    final lat2 = end.latitude * (math.pi / 180.0);
    final long2 = end.longitude * (math.pi / 180.0);

    final dLon = long2 - long1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);

    return (brng * 180.0 / math.pi + 360.0) % 360.0;
  }

  ll.LatLng _projectAhead(
      ll.LatLng start,
      double bearingDegrees,
      double distanceMeters,
      )
  {
    const earthRadius = 6378137.0;

    final bearing = bearingDegrees * math.pi / 180.0;

    final lat1 = start.latitude * math.pi / 180.0;
    final lon1 = start.longitude * math.pi / 180.0;

    final angularDistance = distanceMeters / earthRadius;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) *
              math.sin(angularDistance) *
              math.cos(bearing),
    );

    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) *
              math.sin(angularDistance) *
              math.cos(lat1),
          math.cos(angularDistance) -
              math.sin(lat1) * math.sin(lat2),
        );

    return ll.LatLng(
      lat2 * 180.0 / math.pi,
      lon2 * 180.0 / math.pi,
    );
  }

  ll.LatLng _getLookAheadPoint(
      List<ll.LatLng> route,
      double lookAheadMeters,
      ) {
    if (route.isEmpty) {
      return _cachedUserLocation ?? const ll.LatLng(0, 0);
    }

    if (route.length == 1) {
      return route.first;
    }

    const distance = ll.Distance();

    double accumulated = 0;

    for (int i = 0; i < route.length - 1; i++) {
      final segmentDistance = distance(
        route[i],
        route[i + 1],
      );

      accumulated += segmentDistance;

      if (accumulated >= lookAheadMeters) {
        return route[i + 1];
      }
    }

    return route.last;
  }

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(_publicToken);
    _initCompass();
    _initLocationStream();
    _loadCollectedDrops();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _compassSubscription?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // 🗺️ MAPBOX CORE INITIALIZATION
  // ----------------------------------------------------------------
  _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;

    _routeManager = await map.annotations.createPolylineAnnotationManager();
    _circleManager = await map.annotations.createCircleAnnotationManager();
    _textManager = await map.annotations.createPointAnnotationManager();

    _circleManager?.addOnCircleAnnotationClickListener(_CircleClickListener(_markerTaps));
    _textManager?.addOnPointAnnotationClickListener(_PointClickListener(_markerTaps));

    await _mapboxMap?.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: true,
        showAccuracyRing: true,
        pulsingEnabled: true,
        puckBearingEnabled: true,
        puckBearing: mapbox.PuckBearing.HEADING,
        locationPuck: mapbox.LocationPuck(
          locationPuck2D: mapbox.DefaultLocationPuck2D(),
        ),
      ),
    );

    _moveToUserLocation(animate: true);

    setState(() {
      _isMapReady = true;
    });

    _syncCurrentItinerary();
    _fetchGeoDropsOnly();
  }

  void _syncCurrentItinerary() {
    if (!_isMapReady) return;

    final selectedDay = ref.read(selectedDayProvider);
    final allItems = ref.read(itineraryProvider).where((i) =>
    i.tripId == widget.tripId &&
        i.status != ItineraryStatus.skipped &&
        i.latitude != null &&
        i.longitude != null
    ).toList();

    final visibleItems = selectedDay == 0
        ? allItems
        : allItems.where((i) => i.day == selectedDay).toList();

    _syncMapboxMarkers(visibleItems, isAllDaysView: selectedDay == 0);
  }

  Future<void> _syncMapboxMarkers(List<ItineraryItem> visibleItems, {required bool isAllDaysView}) async {
    if (_circleManager == null || _textManager == null) return;
    if (!mounted) return;

    final isDark = _isDarkCached;

    await _circleManager?.deleteAll();
    await _textManager?.deleteAll();
    _markerTaps.clear();

    List<mapbox.CircleAnnotationOptions> circleOptions = [];
    List<mapbox.PointAnnotationOptions> textOptions = [];
    List<VoidCallback> circleActions = [];
    List<VoidCallback> textActions = [];

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final userLoc = _cachedUserLocation ?? ll.LatLng(0, 0);

    // 🟢 White text on dark maps, black text on light maps
    final titleTextColor = isDark ? Colors.white.value : Colors.black.value;
    final titleHaloColor = isDark ? Colors.black.value : Colors.white.value;

    for (var drop in _nearbyDrops) {
      final isOwnDrop = currentUserId != null && drop.userId == currentUserId;
      final distance = const ll.Distance().as(ll.LengthUnit.Meter, userLoc, drop.location);
      final isUnlocked = isOwnDrop || distance < 50;
      final pos = mapbox.Position(drop.location.longitude, drop.location.latitude);

      int circleColor;
      if (isDark) {
        circleColor = isOwnDrop ? Colors.deepPurple.shade300.value : (isUnlocked ? Colors.deepPurple.shade300.value : Colors.blueGrey.shade400.value);
      } else {
        circleColor = isOwnDrop ? Colors.deepPurple.value : (isUnlocked ? Colors.deepPurple.value : Colors.blueGrey.shade700.value);
      }

      int borderColor = isOwnDrop ? Colors.cyanAccent.value : (isUnlocked ? Colors.amber.value : Colors.white.value);
      String symbol = isOwnDrop ? "📌" : (isUnlocked ? "✨" : "🔒");

      circleOptions.add(
          mapbox.CircleAnnotationOptions(
              geometry: mapbox.Point(coordinates: pos),
              circleColor: circleColor,
              circleRadius: 14.0,
              circleStrokeWidth: 2.0,
              circleStrokeColor: borderColor
          )
      );

      textOptions.add(
          mapbox.PointAnnotationOptions(
              geometry: mapbox.Point(coordinates: pos),
              textField: symbol,
              textSize: 12.0,
              textAnchor: mapbox.TextAnchor.CENTER
          )
      );

      action() {
        if (isUnlocked) {
          _handleDropTap(drop);
        } else {
          showDialog(
              context: context,
              builder: (_) => AlertDialog(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  title: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      const Text("Locked Memory", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  content: const Text("You must be within 50 meters to read this memory! Walk closer."),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold))
                    )
                  ]
              )
          );
        }
      }
      circleActions.add(action);
      textActions.add(action);
    }

    for (var item in visibleItems) {
      final baseColor = Colors.primaries[item.day % Colors.primaries.length];

      // 🟢 Uses the bright shade300 variant in dark mode so the pin is beautiful and visible
      final markerColorValue = isDark ? baseColor.shade300.value : baseColor.value;

      final pos = mapbox.Position(item.longitude!, item.latitude!);

      circleOptions.add(
          mapbox.CircleAnnotationOptions(
              geometry: mapbox.Point(coordinates: pos),
              circleColor: markerColorValue,
              circleRadius: 10.0,
              circleStrokeWidth: 2.0,
              circleStrokeColor: Colors.white.value
          )
      );

      circleActions.add(() => _openPlaceDetails(context, item));

      textOptions.add(
          mapbox.PointAnnotationOptions(
              geometry: mapbox.Point(coordinates: pos),
              textField: "▼",
              textColor: markerColorValue,
              textSize: 20.0,
              textOffset: [0.0, 0.45],
              textHaloColor: titleHaloColor,
              textHaloWidth: 1.0
          )
      );

      textActions.add(() => _openPlaceDetails(context, item));

      if (!isAllDaysView) {
        textOptions.add(
            mapbox.PointAnnotationOptions(
                geometry: mapbox.Point(coordinates: pos),
                textField: item.title,
                textColor: titleTextColor,
                textHaloColor: titleHaloColor,
                textHaloWidth: 2.0,
                textSize: 13.0,
                textOffset: [0.0, 1.8],
                textAnchor: mapbox.TextAnchor.TOP
            )
        );
        textActions.add(() => _openPlaceDetails(context, item));
      }
    }

    if (circleOptions.isNotEmpty) {
      final circles = await _circleManager?.createMulti(circleOptions);
      if (circles != null) {
        for (int i = 0; i < circles.length; i++) {
          if (circles[i]?.id != null) {
            _markerTaps[circles[i]!.id] = circleActions[i];
          }
        }
      }
    }

    if (textOptions.isNotEmpty) {
      final texts = await _textManager?.createMulti(textOptions);
      if (texts != null) {
        for (int i = 0; i < texts.length; i++) {
          if (texts[i]?.id != null) {
            _markerTaps[texts[i]!.id] = textActions[i];
          }
        }
      }
    }
  }

  // ----------------------------------------------------------------
  // 🚗 MAPBOX ROUTE ENGINE
  // ----------------------------------------------------------------
  void _drawNavigationRoutes(
      List<ll.LatLng> fullRoute,
      List<ll.LatLng> remainingRoute,
      ll.LatLng? currentLocation,
      ) async {

    if (_routeManager == null || fullRoute.isEmpty) {
      return;
    }

    final completedCount = fullRoute.length - remainingRoute.length;

    List<ll.LatLng> connectedCompleted = [];
    if (completedCount > 0) {
      connectedCompleted = fullRoute.sublist(0, completedCount);
      if (currentLocation != null) {
        connectedCompleted.add(currentLocation);
      } else if (remainingRoute.isNotEmpty) {
        connectedCompleted.add(remainingRoute.first);
      }
    }

    List<ll.LatLng> connectedRemaining = List.of(remainingRoute);
    if (currentLocation != null && connectedRemaining.isNotEmpty) {
      connectedRemaining.insert(0, currentLocation);
    }

    final completedGeometry = mapbox.LineString(
      coordinates: connectedCompleted
          .map((p) => mapbox.Position(p.longitude, p.latitude))
          .toList(),
    );

    final remainingGeometry = mapbox.LineString(
      coordinates: connectedRemaining
          .map((p) => mapbox.Position(p.longitude, p.latitude))
          .toList(),
    );

    if (connectedCompleted.length > 1) {
      if (_completedRouteAnnotation == null) {
        _completedRouteAnnotation = await _routeManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: completedGeometry,
            lineColor: Colors.grey.value,
            lineWidth: 8.0,
            lineOpacity: 0.7,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      } else {
        _completedRouteAnnotation!.geometry = completedGeometry;
        await _routeManager!.update(_completedRouteAnnotation!);
      }
    }

    // 🟢 FIXED: Route dynamic color tracking
    final isDark = _isDarkCached;
    final routeColor = isDark ? const Color(0xFF00E5FF).value : const Color(0xFF2E3192).value;

    if (_remainingRouteAnnotation == null) {
      _remainingRouteAnnotation = await _routeManager!.create(
        mapbox.PolylineAnnotationOptions(
          geometry: remainingGeometry,
          lineColor: routeColor,
          lineWidth: 8.0,
          lineOpacity: 1.0,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
    } else {
      _remainingRouteAnnotation!.geometry = remainingGeometry;
      await _routeManager!.update(_remainingRouteAnnotation!);
    }
  }

  void _start3DNavigation() async {
    if (_mapboxMap == null) return;

    setState(() {
      _isNavigating3D = true;
      _isAutoCenter = true;
    });

    await _updateNavigationPuckUI(true, null, 0.0);

    _mapboxMap?.easeTo(
        mapbox.CameraOptions(pitch: 65.0, zoom: 17.5),
        mapbox.MapAnimationOptions(duration: 1000)
    );
  }

  void _stop3DNavigation() async {
    if (_mapboxMap == null) return;

    setState(() {
      _isNavigating3D = false;
      _isAutoCenter = false;

      _previousRouteLocation = null;
      _routeLockedBearing = 0.0;
    });

    await _updateNavigationPuckUI(false, null, 0.0);

    _mapboxMap?.easeTo(
        mapbox.CameraOptions(
            pitch: 0.0,
            bearing: 0.0,
            padding: mapbox.MbxEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        ),
        mapbox.MapAnimationOptions(duration: 400)
    );
  }

  // ----------------------------------------------------------------
  // 📍 THE PUCK MANAGER
  // ----------------------------------------------------------------
  Future<void> _updateNavigationPuckUI(
      bool isNavigatingMode,
      ll.LatLng? snappedLocation,
      double heading,
      ) async {

    if (_mapboxMap == null) return;

    if (isNavigatingMode) {
      await _mapboxMap!.location.updateSettings(
        mapbox.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: false,
          showAccuracyRing: false,
          puckBearingEnabled: true,
          puckBearing: mapbox.PuckBearing.COURSE,
        ),
      );
    } else {
      await _mapboxMap!.location.updateSettings(
        mapbox.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          showAccuracyRing: true,
          puckBearingEnabled: true,
          puckBearing: mapbox.PuckBearing.HEADING,
        ),
      );
    }
  }

  void _fitBounds(List<ll.LatLng> points) async {
    if (points.isEmpty || _mapboxMap == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    try {
      final cameraOptions = await _mapboxMap?.cameraForCoordinateBounds(
        mapbox.CoordinateBounds(
            southwest: mapbox.Point(coordinates: mapbox.Position(minLng, minLat)),
            northeast: mapbox.Point(coordinates: mapbox.Position(maxLng, maxLat)),
            infiniteBounds: false
        ),
        mapbox.MbxEdgeInsets(top: 100.0, left: 40.0, bottom: 260.0, right: 40.0),
        null,
        null,
        null,
        null,
      );

      if (cameraOptions != null) {
        _mapboxMap?.flyTo(cameraOptions, mapbox.MapAnimationOptions(duration: 1000));
      }
    } catch (e) {
      print('Bounds Error: $e');
    }
  }

  // ----------------------------------------------------------------
  // 📡 BACKGROUND LOGIC
  // ----------------------------------------------------------------
  void _initLocationStream() {
    _positionStream?.cancel();
    final locationSettings = const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      final newLoc = ll.LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _cachedUserLocation = newLoc;
          _currentSpeed = position.speed;
        });
        _checkForDiscoveryAlert(_nearbyDrops);
      }

      if (_lastSerendipityScanLocation == null) {
        _lastSerendipityScanLocation = newLoc;
      } else {
        final dist = const ll.Distance().as(ll.LengthUnit.Meter, _lastSerendipityScanLocation!, newLoc);

        if (dist > 500 && !_isScanningSerendipity) {
          _lastSerendipityScanLocation = newLoc;
          _triggerSerendipityScan(silent: true);
        }
      }
    });
  }

  void _initCompass() {
    _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading == null) return;

      if (mounted) {
        setState(() => _sensorHeading = event.heading!);
      }

      if (_isAutoCenter && _isCompassMode && !_isNavigating3D) {
        _mapboxMap?.flyTo(mapbox.CameraOptions(bearing: _sensorHeading), null);
      }
    });
  }

  Future<void> _fetchGeoDropsOnly([ll.LatLng? specificLocation]) async {
    if (!mounted || _mapboxMap == null) return;

    ll.LatLng center = specificLocation ?? ll.LatLng(
        (await _mapboxMap!.getCameraState()).center.coordinates.lat.toDouble(),
        (await _mapboxMap!.getCameraState()).center.coordinates.lng.toDouble()
    );

    final drops = await SocialDropService.scanNearby(center);

    if (mounted) {
      setState(() => _nearbyDrops = drops);
      _checkForDiscoveryAlert(drops);
      _syncCurrentItinerary();
    }
  }

  Future<void> _loadCollectedDrops() async {
    final collectedIds = await SocialDropService.getCollectedDropIds();
    if (mounted) {
      setState(() => _collectedDropIds = collectedIds.toSet());
    }
  }

  void _checkForDiscoveryAlert(List<SocialDrop> drops) {
    final userLoc = _cachedUserLocation;
    if (userLoc == null || !_isMapReady) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    for (var drop in drops) {
      if (currentUserId != null && drop.userId == currentUserId) continue;
      if (_shownDropIds.contains(drop.id) || _collectedDropIds.contains(drop.id)) continue;

      if (const ll.Distance().as(ll.LengthUnit.Meter, userLoc, drop.location) < 50) {
        _shownDropIds.add(drop.id);
        _handleDropTap(drop);
        break;
      }
    }
  }

  void _handleDropTap(SocialDrop drop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    // 🟢 FIXED: Drop popups now match theme
                    colors: [accentColor.withOpacity(0.9), const Color(0xFF1BFFFF).withOpacity(0.6)],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 24),
                    const Text("Memory Found! ✨", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 16),
                    Text('"${drop.message}"', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontStyle: FontStyle.italic, height: 1.4)),
                    const SizedBox(height: 12),
                    Text('- ${drop.userName}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Dismiss", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? accentForeground : Colors.white,
                              foregroundColor: accentColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              bool success = await SocialDropService.collectMemory(drop.id);
                              if (success) {
                                setState(() => _collectedDropIds.add(drop.id));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: accentColor,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    content: Text("Added to your Travel Dex! 📖", style: TextStyle(color: accentForeground, fontWeight: FontWeight.bold)),
                                  ),
                                );
                              }
                            },
                            child: const Text("Collect", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
    );
  }

  Future<void> _moveToUserLocation({bool animate = true}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final latLng = ll.LatLng(position.latitude, position.longitude);

      if (mounted) setState(() => _cachedUserLocation = latLng);

      if (animate) {
        _mapboxMap?.flyTo(
            mapbox.CameraOptions(
                center: mapbox.Point(coordinates: mapbox.Position(latLng.longitude, latLng.latitude)),
                zoom: 16.0
            ),
            mapbox.MapAnimationOptions(duration: 1000)
        );
      }
      _fetchGeoDropsOnly(latLng);
    } catch (e) {
      print(e);
    }
  }

  void _showNativePoiDetails(String name, String category, double lat, double lng) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => MapPoiSheet(
            title: name,
            category: category,
            lat: lat,
            lon: lng,
            tripId: widget.tripId
        )
    );
  }

  void _openPlaceDetails(BuildContext context, ItineraryItem item) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PlaceDetailsSheet(item: item)
    );
  }

  void _focusOnDay(int dayIndex) {
    ref.read(selectedDayProvider.notifier).state = dayIndex;

    setState(() {
      _isAutoCenter = false;
      _hasFitPinsOnce = false;
    });

    final allItems = ref.read(itineraryProvider);
    final dayItems = dayIndex == 0 ? allItems : allItems.where((i) => i.day == dayIndex).toList();
    final points = dayItems.where((i) => i.latitude != null && i.longitude != null).map((i) => ll.LatLng(i.latitude!, i.longitude!)).toList();

    _fitBounds(points);
    _syncCurrentItinerary();
  }

  Future<void> _triggerSerendipityScan({bool silent = false}) async {
    if (_cachedUserLocation == null) return;
    if (!silent) setState(() => _isScanningSerendipity = true);

    try {
      final rawGems = await AmadeusService.fetchHiddenGems(_cachedUserLocation!);

      if (mounted) {
        if (!silent) setState(() => _isScanningSerendipity = false);

        if (rawGems.isNotEmpty) {
          final firstGem = rawGems.first;
          final result = SerendipityResult(
              name: firstGem['name'] ?? 'Unknown Gem',
              location: ll.LatLng(firstGem['lat'], firstGem['lng']),
              reason: "A popular ${firstGem['category']?.toLowerCase() ?? 'place'} spotted nearby. Worth a detour!",
              photoUrl: null,
              detourMinutes: 10
          );

          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1C1C1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.amber.withOpacity(0.3))),
                  duration: const Duration(seconds: 8),
                  content: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text("HIDDEN GEM NEARBY", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                                  Text(result.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)
                                ]
                            )
                        )
                      ]
                  ),
                  action: SnackBarAction(
                      label: "VIEW",
                      textColor: Colors.amber,
                      onPressed: () => _showDetourPreview(context, result)
                  )
              )
          );
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), content: const Text("No hidden gems found nearby right now."))
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _isScanningSerendipity = false);
    }
  }

  void _showDetourPreview(BuildContext context, SerendipityResult result) {
    if (_cachedUserLocation == null) return;

    final distanceMeters = const ll.Distance().as(ll.LengthUnit.Meter, _cachedUserLocation!, result.location);
    String distanceString = distanceMeters < 1000
        ? "${distanceMeters.round()} m"
        : "${(distanceMeters / 1000).toStringAsFixed(1)} km";
    final walkingMinutes = (distanceMeters / 80).ceil();

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _DetourDetailSheet(
            result: result,
            distanceString: distanceString,
            walkingMinutes: walkingMinutes,
            onStartNavigation: () {
              Navigator.pop(ctx);
              ref.read(navigationProvider.notifier).startNavigation(
                  tripId: widget.tripId,
                  destLat: result.location.latitude,
                  destLng: result.location.longitude
              );
            }
        )
    );
  }

  // ----------------------------------------------------------------
  // 📱 BUILD UI
  // ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final navigation = ref.watch(navigationProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final isNavigating = navigation.isNavigating;

    // 🟢 SAFELY CACHE THEME IN BUILD METHOD
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _isDarkCached = isDark;

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    // 🟢 1. TRIGGER THEME MAP CHANGE (Triggers onStyleLoadedListener to safely redraw pins!)
    if (_lastDarkTheme != null && _lastDarkTheme != isDark) {
      _lastDarkTheme = isDark;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_isMapReady && _mapboxMap != null) {
          await _mapboxMap!.loadStyleURI(
            //isDark
            //  ? _journiiDarkStyle
            mapbox.MapboxStyles.MAPBOX_STREETS,
          );
        }
      });
    } else if (_lastDarkTheme == null) {
      _lastDarkTheme = isDark;
    }

    final allItems = ref.watch(itineraryProvider).where((i) =>
    i.tripId == widget.tripId &&
        i.status != ItineraryStatus.skipped &&
        i.latitude != null &&
        i.longitude != null
    ).toList();

    final visibleItems = selectedDay == 0
        ? allItems
        : allItems.where((i) => i.day == selectedDay).toList();

    final days = allItems.map((e) => e.day).toSet().toList()..sort();

    ref.listen(selectedDayProvider, (prev, next) {
      if (_isMapReady) _syncCurrentItinerary();
    });

    ref.listen(itineraryProvider, (prev, next) {
      if (_isMapReady) _syncCurrentItinerary();
    });

    ref.listen(navigationProvider, (prev, next) {
      if (next.hasRoute && !_hasFitRouteOnce) {
        _fitBounds(next.fullRoute);
        _hasFitRouteOnce = true;
        _hasFitPinsOnce = true;
      }

      if (next.hasRoute && !next.hasArrived) {
        _drawNavigationRoutes(
          next.fullRoute,
          next.remainingRoute,
          next.currentLocation,
        );
      }

      if (next.isNavigating && prev?.isNavigating != true && _isMapReady) {
        _start3DNavigation();
      }

      if (next.hasArrived && prev?.hasArrived != true) {
        _stop3DNavigation();
        _completedRouteAnnotation = null;
        _remainingRouteAnnotation = null;
        _routeManager?.deleteAll();
        _hasFitRouteOnce = false;
      }

      if (next.isNavigating && next.currentLocation != null && _isAutoCenter && _isMapReady) {
        if (next.remainingRoute.length > 3) {
          _routeLockedBearing = _calculateStrictBearing(
            next.remainingRoute.first,
            next.remainingRoute[3],
          );
        } else {
          _routeLockedBearing = next.heading ?? 0.0;
        }

        _previousRouteLocation = next.currentLocation;

        double forwardDistance = 90.0;
        if (_currentSpeed > 20) forwardDistance = 180.0;
        else if (_currentSpeed > 12) forwardDistance = 140.0;
        else if (_currentSpeed > 5) forwardDistance = 110.0;

        final cameraTarget = _projectAhead(
          next.currentLocation!,
          _routeLockedBearing,
          forwardDistance,
        );

        double dynamicZoom = 17.0;
        if (_currentSpeed > 25) dynamicZoom = 15.8;
        else if (_currentSpeed > 15) dynamicZoom = 16.3;
        else if (_currentSpeed > 8) dynamicZoom = 16.8;
        else if (_currentSpeed > 3) dynamicZoom = 17.3;
        else dynamicZoom = 18.0;

        _mapboxMap?.easeTo(
            mapbox.CameraOptions(
                center: mapbox.Point(coordinates: mapbox.Position(cameraTarget.longitude, cameraTarget.latitude)),
                bearing: _routeLockedBearing,
                pitch: 65.0,
                zoom: dynamicZoom,
                padding: mapbox.MbxEdgeInsets(top: 0.0, left: 0.0, bottom: 240.0, right: 0.0)
            ),
            mapbox.MapAnimationOptions(duration: 1000)
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigation.hasRoute && visibleItems.isNotEmpty && !_hasFitPinsOnce) {
        _fitBounds(visibleItems.map((i) => ll.LatLng(i.latitude!, i.longitude!)).toList());
        _hasFitPinsOnce = true;
      }
    });

    return Stack(
      children: [
        mapbox.MapWidget(
          key: const ValueKey("mapboxMap"),
          cameraOptions: mapbox.CameraOptions(zoom: 2.0),
          styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
          onMapCreated: _onMapCreated,

          onStyleLoadedListener: (mapbox.StyleLoadedEventData event) async {
            if (_isMapReady && _mapboxMap != null) {
              _circleManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
              _textManager = await _mapboxMap!.annotations.createPointAnnotationManager();
              _routeManager = await _mapboxMap!.annotations.createPolylineAnnotationManager();

              _circleManager?.addOnCircleAnnotationClickListener(
                _CircleClickListener(_markerTaps),
              );

              _textManager?.addOnPointAnnotationClickListener(
                _PointClickListener(_markerTaps),
              );

              _syncCurrentItinerary();

              final navState = ref.read(navigationProvider);

              if (navState.hasRoute && !navState.hasArrived) {
                _completedRouteAnnotation = null;
                _remainingRouteAnnotation = null;

                _drawNavigationRoutes(
                  navState.fullRoute,
                  navState.remainingRoute,
                  navState.currentLocation,
                );
              }
            }
          },

          onTapListener: (mapbox.MapContentGestureContext gestureContext) async {
            if (_isAutoCenter || _isNavigating3D) {
              setState(() {
                _isAutoCenter = false;
                _isNavigating3D = false;
              });
            }

            try {
              final screenCoord = await _mapboxMap!.pixelForCoordinate(gestureContext.point);
              final box = mapbox.ScreenBox(
                  min: mapbox.ScreenCoordinate(x: screenCoord.x - 20, y: screenCoord.y - 20),
                  max: mapbox.ScreenCoordinate(x: screenCoord.x + 20, y: screenCoord.y + 20)
              );

              print(
                "Tapped: "
                    "${gestureContext.point.coordinates.lat}, "
                    "${gestureContext.point.coordinates.lng}",
              );

              final camera = await _mapboxMap!.getCameraState();

              print("Current Zoom: ${camera.zoom}");

              final renderedFeatures = await _mapboxMap?.queryRenderedFeatures(
                mapbox.RenderedQueryGeometry.fromScreenBox(box),
                mapbox.RenderedQueryOptions(
                  layerIds: null,
                  filter: null,
                ),
              );

              print("Features found: ${renderedFeatures?.length}");

              if (renderedFeatures != null && renderedFeatures.isNotEmpty) {
                print(renderedFeatures.first);
              }

              if (renderedFeatures != null && renderedFeatures.isNotEmpty) {
                final featureData = renderedFeatures.first?.queriedFeature?.feature;
                if (featureData != null) {
                  final featureMap = featureData as Map<dynamic, dynamic>;
                  final properties = featureMap['properties'] as Map<dynamic, dynamic>?;
                  final geometry = featureMap['geometry'] as Map<dynamic, dynamic>?;

                  if (properties != null && geometry != null && geometry['type'] == 'Point') {
                    _showNativePoiDetails(
                        properties['name']?.toString() ?? 'Unknown Place',
                        properties['maki']?.toString() ?? properties['class']?.toString() ?? 'place',
                        (geometry['coordinates'] as List<dynamic>)[1] as double,
                        (geometry['coordinates'] as List<dynamic>)[0] as double
                    );
                  }
                }
              }
            } catch (e) {
              print("Query Rendered Features Error: $e");
            }
          },
          onScrollListener: (mapbox.MapContentGestureContext context) {
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 800), () => _fetchGeoDropsOnly());
          },
        ),

        // 🟢 TURN-BY-TURN HUD
        if (isNavigating && navigation.currentStep != null)
          Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: _TurnByTurnBanner(navigation, isDark)
          ),

        // 🟢 NAVIGATION CONTROLS
        if (isNavigating && !_isNavigating3D)
          Positioned(
              bottom: 140,
              right: 24,
              child: _buildGlassFab(
                icon: Icons.center_focus_strong_rounded,
                color: accentColor,
                isDark: isDark,
                onTap: () async {
                  setState(() => _isAutoCenter = true);
                  await _moveToUserLocation(animate: false);
                  _start3DNavigation();
                },
              )
          ),

        if (isNavigating)
          Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: const BorderSide(color: Colors.transparent),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text("Exit Navigation", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      onPressed: () {
                        ref.read(navigationProvider.notifier).stopNavigation();
                        _completedRouteAnnotation = null;
                        _remainingRouteAnnotation = null;
                        _routeManager?.deleteAll();
                        _stop3DNavigation();
                      }
                  ),
                ),
              )
          ),

        // 🟢 EXPLORATION CONTROLS
        if (!isNavigating) ...[
          // Floating Segmented Filter
          Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              right: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      // 🟢 FIXED: Gave it a solid dark background so it doesn't wash out against the map!
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white.withOpacity(0.9),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.white),
                      borderRadius: BorderRadius.circular(28),
                      // Added a subtle shadow to lift it cleanly off the map
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                            children: [
                              _buildFilterChip('All Days', 0, selectedDay, isDark, accentColor, accentForeground),
                              ...days.map((d) => _buildFilterChip('Day $d', d, selectedDay, isDark, accentColor, accentForeground))
                            ]
                        )
                    ),
                  ),
                ),
              )
          ),

          // 🟢 UNIFIED RIGHT-SIDE VERTICAL COMMAND PILL
          Positioned(
            right: 24,
            bottom: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Navigation / Compass
                      _buildPillAction(
                          icon: _isCompassMode ? Icons.explore_rounded : Icons.my_location_rounded,
                          color: _isCompassMode ? accentColor : (isDark ? Colors.white : Colors.black87),
                          onTap: () async {
                            if (!_isAutoCenter) {
                              setState(() { _isAutoCenter = true; _isCompassMode = false; });
                              await _moveToUserLocation();
                              return;
                            }
                            if (!_isCompassMode) {
                              setState(() => _isCompassMode = true);
                              return;
                            }
                            setState(() => _isCompassMode = false);
                            _mapboxMap?.easeTo(mapbox.CameraOptions(bearing: 0.0), mapbox.MapAnimationOptions(duration: 600));
                          }
                      ),

                      Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : Colors.black12, indent: 12, endIndent: 12),

                      // 2. Discover / Serendipity
                      _isScanningSerendipity
                          ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
                      )
                          : _buildPillAction(
                        icon: Icons.diamond_outlined,
                        color: Colors.amber,
                        onTap: _triggerSerendipityScan,
                      ),

                      Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : Colors.black12, indent: 12, endIndent: 12),

                      // 3. Drop Memory
                      _buildPillAction(
                        icon: Icons.add_location_alt_rounded,
                        color: Colors.deepPurple,
                        onTap: _showCreateDropDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (navigation.hasRoute && navigation.distanceKm != null)
            Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: _EtaBanner(
                    navigation: navigation,
                    isDark: isDark,
                    onClose: () {
                      ref.read(navigationProvider.notifier).stopNavigation();
                      _completedRouteAnnotation = null;
                      _remainingRouteAnnotation = null;
                      _routeManager?.deleteAll();
                      _hasFitRouteOnce = false;
                    }
                )
            ),
        ],

        if (navigation.hasArrived)
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: _ArrivalBanner(
              isDark: isDark,
              onDismiss: () {
                ref.read(navigationProvider.notifier).stopNavigation();
                _completedRouteAnnotation = null;
                _remainingRouteAnnotation = null;
                _routeManager?.deleteAll();
                _hasFitRouteOnce = false;
              },
              onMarkCompleted: () async {
                ref.read(navigationProvider.notifier).stopNavigation();
                _completedRouteAnnotation = null;
                _remainingRouteAnnotation = null;
                _routeManager?.deleteAll();
                _hasFitRouteOnce = false;
              },
            ),
          ),
      ],
    );
  }

  Widget _buildGlassFab({required IconData icon, required Color color, required bool isDark, required VoidCallback onTap}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.white),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildPillAction({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.transparent,
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildFilterChip(String label, int value, int selected, bool isDark, Color accentColor, Color accentForeground) {
    final isActive = selected == value;
    return GestureDetector(
      onTap: () => _focusOnDay(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            // 🟢 FIXED: Ensures text switches to black when active in dark mode
            color: isActive ? accentForeground : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _showCreateDropDialog() {
    final TextEditingController _messageController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32))
                ),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      Row(
                        children: [
                          Text("Leave a Memory", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)),
                          const SizedBox(width: 8),
                          const Icon(Icons.push_pin_rounded, color: Colors.amber),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text("Leave a note for other travelers at this exact spot.", style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14)),
                      const SizedBox(height: 24),
                      TextField(
                          controller: _messageController,
                          maxLength: 140,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black),
                          decoration: InputDecoration(
                            hintText: "e.g. Best sunset view is right here!",
                            hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                            contentPadding: const EdgeInsets.all(20),
                          ),
                          maxLines: 3
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                              icon: const Icon(Icons.send_rounded),
                              label: const Text("Drop Memory", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor: accentForeground,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
                              ),
                              onPressed: () async {
                                if (_messageController.text.isNotEmpty && _cachedUserLocation != null) {
                                  Navigator.pop(ctx);
                                  bool success = await SocialDropService.createDrop(
                                      location: _cachedUserLocation!,
                                      message: _messageController.text
                                  );
                                  await _fetchGeoDropsOnly();
                                  if (success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            behavior: SnackBarBehavior.floating,
                                            backgroundColor: accentColor,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            content: Text("✨ Memory dropped successfully!", style: TextStyle(color: accentForeground, fontWeight: FontWeight.bold))
                                        )
                                    );
                                  }
                                }
                              }
                          )
                      )
                    ]
                )
            )
        )
    );
  }
}

// ----------------------------------------------------------------
// 🛠️ UTILITY CLASSES & WIDGETS
// ----------------------------------------------------------------

class _CircleClickListener extends mapbox.OnCircleAnnotationClickListener {
  final Map<String, VoidCallback> actions;
  _CircleClickListener(this.actions);
  @override
  void onCircleAnnotationClick(mapbox.CircleAnnotation annotation) {
    actions[annotation.id]?.call();
  }
}

class _PointClickListener extends mapbox.OnPointAnnotationClickListener {
  final Map<String, VoidCallback> actions;
  _PointClickListener(this.actions);
  @override
  void onPointAnnotationClick(mapbox.PointAnnotation annotation) {
    actions[annotation.id]?.call();
  }
}

class _TurnByTurnBanner extends StatelessWidget {
  final NavigationState navigation;
  final bool isDark;

  const _TurnByTurnBanner(this.navigation, this.isDark);

  IconData _getIconForInstruction(String text) {
    final t = text.toLowerCase();
    if (t.contains('left')) return Icons.turn_left_rounded;
    if (t.contains('right')) return Icons.turn_right_rounded;
    if (t.contains('u-turn')) return Icons.u_turn_left_rounded;
    if (t.contains('straight')) return Icons.straight_rounded;
    if (t.contains('roundabout')) return Icons.rotate_right_rounded;
    if (t.contains('destination') || t.contains('arrive')) return Icons.flag_rounded;
    return Icons.navigation_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final step = navigation.currentStep!;
    final remainingKm = navigation.distanceKm?.toStringAsFixed(1) ?? '--';
    final remainingMin = navigation.durationMin?.round() ?? 0;
    final arrivalTime = navigation.durationMin != null ? DateTime.now().add(Duration(minutes: navigation.durationMin!.round())) : null;
    final etaText = arrivalTime != null ? '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}' : '--:--';

    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E).withOpacity(0.85) : Colors.white.withOpacity(0.9),
              border: Border.all(color: isDark ? Colors.white12 : Colors.white),
            ),
            child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                    child: Icon(_getIconForInstruction(step.instruction), color: accentForeground, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                step.instruction,
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87, letterSpacing: -0.5, height: 1.2),
                                maxLines: 2
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  'In ${navigation.distanceMeters?.toStringAsFixed(0) ?? 0}m',
                                  style: TextStyle(color: isDark ? accentColor : const Color(0xFF2E3192), fontSize: 14, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '$remainingKm km • Arrive $etaText',
                                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            )
                          ]
                      )
                  )
                ]
            )
        ),
      ),
    );
  }
}

class _EtaBanner extends StatelessWidget {
  final NavigationState navigation;
  final bool isDark;
  final VoidCallback onClose;

  const _EtaBanner({required this.navigation, required this.isDark, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.9),
              border: Border.all(color: isDark ? Colors.white12 : Colors.white),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route_rounded, color: accentColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                          '${navigation.distanceKm!.toStringAsFixed(1)} km • ${navigation.durationMin!.round()} min',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : Colors.black87)
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05), shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, size: 16, color: isDark ? Colors.white : Colors.black),
                    ),
                  )
                ]
            )
        ),
      ),
    );
  }
}

class _ArrivalBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback onDismiss;
  final VoidCallback onMarkCompleted;

  const _ArrivalBanner({
    super.key,
    required this.isDark,
    required this.onDismiss,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E).withOpacity(0.9) : Colors.white.withOpacity(0.95),
            border: Border.all(color: isDark ? Colors.white12 : Colors.white),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'You’ve arrived 🎉',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'You have successfully reached your destination.',
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onDismiss,
                      child: Text('Dismiss', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text('Complete', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        onPressed: onMarkCompleted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetourDetailSheet extends StatelessWidget {
  final SerendipityResult result;
  final String distanceString;
  final int walkingMinutes;
  final VoidCallback onStartNavigation;

  const _DetourDetailSheet({
    required this.result,
    required this.distanceString,
    required this.walkingMinutes,
    required this.onStartNavigation
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36))
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  flex: 5,
                  child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                      child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<String?>(
                                future: UnsplashService.getPhotoUrl(result.name),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data != null) {
                                    return Image.network(snapshot.data!, fit: BoxFit.cover);
                                  }
                                  return Container(
                                      color: isDark ? Colors.black26 : Colors.black12,
                                      child: const Center(child: Icon(Icons.image_rounded, color: Colors.white24, size: 40))
                                  );
                                }
                            ),
                            DecoratedBox(
                                decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, bgColor],
                                        stops: const [0.4, 1.0]
                                    )
                                )
                            ),
                            Positioned(
                              top: 16, right: 16,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                            )
                          ]
                      )
                  )
              ),
              Expanded(
                  flex: 5,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                children: [
                                  Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withOpacity(0.3))),
                                      child: const Text("HIDDEN GEM", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.amber, letterSpacing: 1.0))
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      children: [
                                        Icon(Icons.directions_walk_rounded, size: 14, color: isDark ? Colors.white70 : Colors.black87),
                                        const SizedBox(width: 6),
                                        Text("$distanceString • $walkingMinutes min", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                  )
                                ]
                            ),
                            const SizedBox(height: 20),
                            Text(
                                result.name,
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5, height: 1.1),
                                maxLines: 2
                            ),
                            const SizedBox(height: 12),
                            Text(
                                result.reason,
                                style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54, height: 1.5, fontWeight: FontWeight.w500),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis
                            ),
                            const Spacer(),
                            SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                    onPressed: onStartNavigation,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: accentForeground,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
                                    ),
                                    icon: const Icon(Icons.navigation_rounded, size: 20),
                                    label: const Text("Navigate There", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5))
                                )
                            )
                          ]
                      )
                  )
              )
            ]
        )
    );
  }
}