import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../services/map_math.dart';
import '../../services/mapbox_routing_service.dart';
import 'dart:math' as math;
import 'package:wakelock_plus/wakelock_plus.dart';

/// --------------------------------------------------
/// 🧭 TURN-BY-TURN STEP MODEL
/// --------------------------------------------------
class NavigationStep {
  final String instruction;
  final double distanceMeters;
  final LatLng location;

  const NavigationStep({
    required this.instruction,
    required this.distanceMeters,
    required this.location,
  });
}

/// --------------------------------------------------
/// 🧠 NAVIGATION STATE
/// --------------------------------------------------
class NavigationState {
  final String? tripId;

  // Route Data
  final List<LatLng> fullRoute;
  final List<LatLng> remainingRoute;
  final double? distanceKm;
  final double? durationMin;

  // Turn-by-turn
  final List<NavigationStep> steps;
  final int currentStepIndex;

  // Live Metrics
  final double? distanceMeters;

  // Live Status
  final LatLng? currentLocation;
  final LatLng? destination;
  final double? heading;
  final bool isNavigating;
  final bool hasArrived;
  final bool isRerouting;

  // UI
  final bool isLoading;
  final String? errorMessage;

  const NavigationState({
    this.tripId,
    this.fullRoute = const [],
    this.remainingRoute = const [],
    this.distanceKm,
    this.durationMin,
    this.steps = const [],
    this.currentStepIndex = 0,
    this.distanceMeters,
    this.currentLocation,
    this.destination,
    this.heading,
    this.isNavigating = false,
    this.hasArrived = false,
    this.isRerouting = false,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get hasRoute => fullRoute.isNotEmpty;

  // 🟢 FIXED: Dynamic Arrival Message Interception for the UI
  NavigationStep? get currentStep {
    if (steps.isEmpty || currentStepIndex >= steps.length) return null;

    final step = steps[currentStepIndex];
    final metersLeft = (distanceKm ?? 0) * 1000.0;

    // If we are on the very last step, but still further than 200m away,
    // suppress the Mapbox arrival message and show a generic continuation.
    if (currentStepIndex == steps.length - 1 && metersLeft > 200) {
      return NavigationStep(
        instruction: "Continue on route",
        distanceMeters: step.distanceMeters,
        location: step.location,
      );
    }

    return step;
  }

  NavigationState copyWith({
    String? tripId,
    List<LatLng>? fullRoute,
    List<LatLng>? remainingRoute,
    double? distanceKm,
    double? durationMin,
    List<NavigationStep>? steps,
    int? currentStepIndex,
    double? distanceMeters,
    LatLng? currentLocation,
    LatLng? destination,
    double? heading,
    bool? isNavigating,
    bool? hasArrived,
    bool? isRerouting,
    bool? isLoading,
    String? errorMessage,
  }) {
    return NavigationState(
      tripId: tripId ?? this.tripId,
      fullRoute: fullRoute ?? this.fullRoute,
      remainingRoute: remainingRoute ?? this.remainingRoute,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMin: durationMin ?? this.durationMin,
      steps: steps ?? this.steps,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      currentLocation: currentLocation ?? this.currentLocation,
      destination: destination ?? this.destination,
      heading: heading ?? this.heading,
      isNavigating: isNavigating ?? this.isNavigating,
      hasArrived: hasArrived ?? this.hasArrived,
      isRerouting: isRerouting ?? this.isRerouting,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// --------------------------------------------------
/// 🚀 NAVIGATION NOTIFIER
/// --------------------------------------------------
class NavigationNotifier extends StateNotifier<NavigationState> {
  NavigationNotifier() : super(const NavigationState()) {
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);
    _tts.setLanguage('en-US');
  }

  final FlutterTts _tts = FlutterTts();
  StreamSubscription<Position>? _positionStream;
  final Set<int> _announcedSteps = {};

  // --------------------------------------------------
  // 📏 ORIGINAL ROUTE METRICS
  // --------------------------------------------------
  double? _originalRouteDistanceKm;
  double? _originalRouteDurationMin;

  // 🎯 SETTINGS
  static const double _arrivalRadiusMeters = 40;
  static const double _rerouteThresholdMeters = 40;

  /// --------------------------------------------------
  /// 🚀 START NAVIGATION
  /// --------------------------------------------------
  Future<void> startNavigation({
    required String tripId,
    required double destLat,
    required double destLng,
    List<LatLng>? waypoints,
  }) async {
    debugPrint('🧭 Starting navigation for trip $tripId');
    await stopNavigation();

    state = state.copyWith(isLoading: true, errorMessage: null, hasArrived: false);

    try {
      final destination = LatLng(destLat, destLng);
      final position = await _determinePosition();
      final start = LatLng(position.latitude, position.longitude);

      await _calculateAndSetRoute(start, destination, tripId, waypoints);

      await WakelockPlus.enable();

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen(_onLocationUpdate);

    } catch (e) {
      debugPrint('❌ Navigation error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// --------------------------------------------------
  /// 🔄 CALCULATE ROUTE (Helper)
  /// --------------------------------------------------
  Future<void> _calculateAndSetRoute(
      LatLng start,
      LatLng dest,
      String? tripId,
      [List<LatLng>? waypoints]
      ) async {

    final result = await MapboxRoutingService.getRoute(
        from: start,
        to: dest,
        waypoints: waypoints
    );

    await WakelockPlus.enable();

    if (state.hasArrived) {
      debugPrint('🛑 Reroute ignored: User already arrived at destination.');
      return;
    }

    if (result == null) {
      if (tripId != null) throw Exception('Unable to calculate route.');
      return;
    }

    final steps = result.steps.map((s) => NavigationStep(
      instruction: s.instruction,
      distanceMeters: s.distanceMeters,
      location: s.location,
    )).toList();

    _announcedSteps.clear();

    debugPrint(
        'ROUTE BUILT -> '
            'points=${result.points.length} '
            'steps=${result.steps.length}'
    );

    _originalRouteDistanceKm = result.distanceKm;
    _originalRouteDurationMin = result.durationMin;

    state = state.copyWith(
      tripId: tripId ?? state.tripId,
      fullRoute: result.points,
      remainingRoute: result.points,
      steps: steps,
      currentStepIndex: 0,
      distanceMeters: steps.isNotEmpty ? steps.first.distanceMeters : 0,
      distanceKm: result.distanceKm,
      durationMin: result.durationMin,
      currentLocation: start,
      destination: dest,
      isNavigating: true,
      isLoading: false,
      hasArrived: false,
      isRerouting: false,
    );

    if (steps.isNotEmpty) {
      // Don't speak "Your destination is on the left" instantly if the route is just 1 straight long line
      if (steps.length == 1 && result.distanceKm * 1000 > 200) {
        await _tts.speak("Continue on route");
      } else {
        await _tts.speak(steps.first.instruction);
      }
    }
  }

  Future<void> _onLocationUpdate(Position position) async {
    if (!state.isNavigating || state.destination == null) return;

    final rawLoc = LatLng(position.latitude, position.longitude);
    final distanceCalc = const Distance();

    // 1. 🏁 ARRIVAL CHECK
    final metersToDest = distanceCalc(rawLoc, state.destination!);
    if (metersToDest <= _arrivalRadiusMeters) {

      String arrivalMessage = _getArrivalSide(rawLoc, state.destination!);
      await _speakImmediate(arrivalMessage);

      _originalRouteDistanceKm = null;
      _originalRouteDurationMin = null;

      state = state.copyWith(
        hasArrived: true,
        isNavigating: false,
        isRerouting: false,
        fullRoute: [],
        remainingRoute: [],
        steps: [],
        distanceKm: null,
        durationMin: null,
        currentLocation: rawLoc,
        distanceMeters: 0,
      );

      await _positionStream?.cancel();
      _positionStream = null;

      await WakelockPlus.disable();

      return;
    }

    // 2. ✂️ SMART POLYLINE SLICING
    List<LatLng> currentRoute = state.fullRoute;
    int searchRadius = 1500;

    int routeStartIndex = math.max(
      0,
      currentRoute.length - state.remainingRoute.length,
    );

    int closestIndex = routeStartIndex;
    double minPenaltyScore = double.infinity;
    double actualDistanceAtClosest = distanceCalc(rawLoc, currentRoute[routeStartIndex]);

    final int endIndex = math.min(
      currentRoute.length,
      routeStartIndex + searchRadius,
    );

    for (int i = routeStartIndex; i < endIndex - 1; i++) {
      final d = distanceCalc(rawLoc, currentRoute[i]);

      double directionPenalty = 0.0;

      if (position.speed > 1.5 && position.heading >= 0) {
        double segmentBearing = _calculateBearing(currentRoute[i], currentRoute[i + 1]);

        double headingDiff = (segmentBearing - position.heading).abs();
        if (headingDiff > 180) headingDiff = 360 - headingDiff;

        if (headingDiff > 90) {
          directionPenalty = 150.0;
        }
      }

      final score = d + directionPenalty;

      if (score < minPenaltyScore) {
        minPenaltyScore = score;
        closestIndex = i;
        actualDistanceAtClosest = d;
      }
    }

    List<LatLng> newRemaining = currentRoute.sublist(
      math.min(closestIndex, currentRoute.length - 1),
    );

    // --------------------------------------------------
    // 📏 LIVE REMAINING DISTANCE
    // --------------------------------------------------
    double remainingMeters = 0;

    for (int i = 0; i < newRemaining.length - 1; i++) {
      remainingMeters += distanceCalc(
        newRemaining[i],
        newRemaining[i + 1],
      );
    }

    final remainingKm = remainingMeters / 1000.0;

    // --------------------------------------------------
    // ⏱️ LIVE REMAINING ETA
    // --------------------------------------------------
    double remainingDurationMin = 0;

    if (_originalRouteDistanceKm != null &&
        _originalRouteDistanceKm! > 0 &&
        _originalRouteDurationMin != null) {

      final ratio = remainingKm / _originalRouteDistanceKm!;
      remainingDurationMin = _originalRouteDurationMin! * ratio;
    }

    // 3. 🧲 SNAP TO ROUTE
    LatLng displayLoc = rawLoc;
    if (newRemaining.length > 2) {
      final snappedLoc = MapMath.snapToRoute(rawLoc, newRemaining);
      if (distanceCalc(rawLoc, snappedLoc) < 30) {
        displayLoc = snappedLoc;
      }
    }

    // 4. 🔄 REROUTING TRIGGER
    if (actualDistanceAtClosest > _rerouteThresholdMeters && !state.isRerouting) {
      debugPrint('🔄 Off-route ($actualDistanceAtClosest m), Recalculating...');
      state = state.copyWith(isRerouting: true);
      await _speakImmediate("Recalculating route");
      await _calculateAndSetRoute(rawLoc, state.destination!, null);
      return;
    }

    // 5. ✅ INSTRUCTION SYNC
    int nextStepIndex = state.currentStepIndex;
    double distToNextAction = 0.0;

    if (state.steps.isNotEmpty && nextStepIndex < state.steps.length) {
      final targetStepLoc = state.steps[nextStepIndex].location;
      double distToTarget = distanceCalc(displayLoc, targetStepLoc);

      double announceDistance;

      if (position.speed > 15) {
        announceDistance = 250;
      } else if (position.speed > 8) {
        announceDistance = 200;
      } else {
        announceDistance = 150;
      }

      if (distToTarget < announceDistance &&
          distToTarget > 70 &&
          !_announcedSteps.contains(nextStepIndex)) {
        _announcedSteps.add(nextStepIndex);

        // 🟢 FIXED: Suppress TTS if it is the final step and > 200m
        if (nextStepIndex == state.steps.length - 1 && remainingKm * 1000 > 200) {
          // Do nothing here, we handle the approach later.
        } else {
          await _tts.speak(
            'In ${distToTarget.round()} meters, ${state.steps[nextStepIndex].instruction}',
          );
        }
      }

      double triggerDistance;

      if (position.speed > 15) {
        triggerDistance = 150;
      } else if (position.speed > 8) {
        triggerDistance = 90;
      } else if (position.speed > 3) {
        triggerDistance = 60;
      } else {
        triggerDistance = 35;
      }

      if (distToTarget < triggerDistance && nextStepIndex < state.steps.length - 1) {
        nextStepIndex++;
        final newStep = state.steps[nextStepIndex];

        // 🟢 FIXED: Suppress immediate TTS if advancing to the final step early
        if (nextStepIndex == state.steps.length - 1 && remainingKm * 1000 > 200) {
          await _speakImmediate("Continue on route");
        } else {
          await _speakImmediate(newStep.instruction);
        }

        distToTarget = distanceCalc(displayLoc, newStep.location);
      }
      distToNextAction = distToTarget;
    }

    // 🟢 NEW: 200m Final Approach TTS Trigger
    if (state.steps.isNotEmpty && nextStepIndex == state.steps.length - 1 && remainingKm * 1000 <= 200) {
      if (!_announcedSteps.contains(9999)) {
        _announcedSteps.add(9999);
        await _speakImmediate(state.steps.last.instruction); // Speaks the true arrival message exactly when needed!
      }
    }

    // 6. 📐 GPS COURSE HEADING
    double effectiveHeading = state.heading ?? 0.0;
    double targetHeading = effectiveHeading;

    if (position.speed > 1.5 && position.heading >= 0) {
      targetHeading = position.heading;
    } else if (newRemaining.length > 1) {
      targetHeading = _calculateBearing(displayLoc, newRemaining[1]);
    }

    // 🌟 SMOOTH HEADING INTERPOLATION
    double diff = targetHeading - effectiveHeading;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    effectiveHeading += diff * 0.18;
    effectiveHeading = (effectiveHeading + 360) % 360;

    // 7. UPDATE STATE
    state = state.copyWith(
      currentLocation: displayLoc,
      heading: effectiveHeading,
      remainingRoute: newRemaining,
      currentStepIndex: nextStepIndex,
      distanceMeters: distToNextAction,
      distanceKm: remainingKm,
      durationMin: remainingDurationMin,
    );
  }

  // 🧭 HELPER
  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * (math.pi / 180);
    final long1 = start.longitude * (math.pi / 180);
    final lat2 = end.latitude * (math.pi / 180);
    final long2 = end.longitude * (math.pi / 180);

    final dLon = long2 - long1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);

    return (brng * 180 / math.pi + 360) % 360;
  }

  String _getArrivalSide(
      LatLng current,
      LatLng destination,
      ) {

    final currentHeading =
        state.heading ?? 0.0;

    final bearingToDestination =
    _calculateBearing(
      current,
      destination,
    );

    double difference =
        bearingToDestination -
            currentHeading;

    while (difference > 180) {
      difference -= 360;
    }

    while (difference < -180) {
      difference += 360;
    }

    if (difference.abs() < 30) {
      return 'Your destination is ahead';
    }

    if (difference > 0) {
      return 'Your destination is on the right';
    }

    return 'Your destination is on the left';
  }

  /// --------------------------------------------------
  /// 🛑 STOP NAVIGATION
  /// --------------------------------------------------
  Future<void> stopNavigation() async {
    await _positionStream?.cancel();
    _positionStream = null;

    _originalRouteDistanceKm = null;
    _originalRouteDurationMin = null;

    await WakelockPlus.disable();
    await _tts.stop();

    state = const NavigationState();
  }

  /// --------------------------------------------------
  /// 📍 GET CURRENT LOCATION (One-off Helper)
  /// --------------------------------------------------
  Future<void> getCurrentLocation() async {
    try {
      final position = await _determinePosition();
      state = state.copyWith(
        currentLocation: LatLng(position.latitude, position.longitude),
        heading: position.heading,
      );
    } catch (e) {
      debugPrint("⚠️ Error getting single location: $e");
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw Exception('Location permission denied.');
    }
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.bestForNavigation);
  }

  Future<void> _speakImmediate(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

}

final navigationProvider = StateNotifierProvider<NavigationNotifier, NavigationState>(
      (ref) => NavigationNotifier(),
);