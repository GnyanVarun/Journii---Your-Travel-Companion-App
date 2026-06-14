import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui'; // Required for Glassmorphism

import 'itinerary_item_model.dart';
import 'route_preview_map_view.dart';
import 'navigation_provider.dart';

// ✅ IMPORT YOUR SERVICE
import '../../services/live_data_service.dart';

// ✅ HELPER CLASS
class _RouteStats {
  final String durationText;
  final String distanceText;
  final String caloriesText;
  final String contextLabel;
  final Color contextColor;

  _RouteStats({
    required this.durationText,
    required this.distanceText,
    required this.caloriesText,
    required this.contextLabel,
    required this.contextColor,
  });
}

class RoutePreviewSheet extends ConsumerStatefulWidget {
  final ItineraryItem item;

  const RoutePreviewSheet({
    super.key,
    required this.item,
  });

  @override
  ConsumerState<RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends ConsumerState<RoutePreviewSheet> {
  int _selectedModeIndex = 0; // 0=Drive, 1=Walk, 2=Transit

  // 🔌 SERVICE INSTANCE
  final _dataService = LiveDataService();

  // 🧮 MATH CONSTANTS
  final Distance _distanceCalculator = const Distance();
  final double _speedWalk = 4.5;
  final double _speedDrive = 24.0;
  final double _speedTransit = 18.0;

  // ⚡ LIVE DATA STATE
  String _weatherText = "Checking weather...";
  String _transitText = "Locating stop...";
  Map<String, dynamic>? _realOsrmData;

  @override
  void initState() {
    super.initState();

    // 1. Wake up GPS
    Future.microtask(() {
      ref.read(navigationProvider.notifier).getCurrentLocation();
    });

    // 2. Fetch Live Data
    if (widget.item.latitude != null) {
      _fetchWeather();
      _fetchTransitData();
    }
  }

  void _fetchWeather() async {
    try {
      final w = await _dataService.getWeatherContext(
          widget.item.latitude!, widget.item.longitude!
      );
      if (w != "Weather unavailable" && mounted) {
        setState(() => _weatherText = w);
      }
    } catch (_) {}
  }

  void _fetchTransitData() async {
    try {
      final t = await _dataService.getTransitDeparture(
          widget.item.latitude!, widget.item.longitude!
      );
      if (mounted) setState(() => _transitText = t);
    } catch (_) {
      if (mounted) setState(() => _transitText = "Stop info unavailable");
    }
  }

  void _fetchOsrmData(LatLng userLoc) async {
    if (_realOsrmData != null) return;

    try {
      final data = await _dataService.getOsrmRouteStats(
          userLoc,
          LatLng(widget.item.latitude!, widget.item.longitude!)
      );

      if (mounted && data != null) {
        setState(() => _realOsrmData = data);
      }
    } catch (_) {}
  }

  /// 🧠 HYBRID CALCULATION ENGINE
  _RouteStats _getStats(LatLng? userLoc, int modeIndex) {
    if (userLoc == null || widget.item.latitude == null) {
      return _RouteStats(
          durationText: "--", distanceText: "--", caloriesText: "--",
          contextLabel: "Locating...", contextColor: Colors.grey
      );
    }

    final dest = LatLng(widget.item.latitude!, widget.item.longitude!);

    // 1. Calculate Distance
    final double straightDistKm = _distanceCalculator.as(LengthUnit.Kilometer, userLoc, dest);
    // Safety check: if distance is effectively 0, default to small number to avoid 0 min issues
    final double roadDistKm = (straightDistKm < 0.01 ? 0.01 : straightDistKm) * 1.3;

    // --- CASE 0: DRIVING ---
    if (modeIndex == 0) {
      if (_realOsrmData != null) {
        final int realMin = _realOsrmData!['duration'];
        final double realDist = double.parse(_realOsrmData!['distance']);
        final int mathMin = ((realDist / _speedDrive) * 60).round();

        String label = "Standard Traffic";
        Color color = Colors.green;

        if (realMin > mathMin * 1.2) {
          label = "Slower Route";
          color = Colors.orange;
        } else if (realMin < mathMin * 0.9) {
          label = "Good Traffic";
          color = Colors.green.shade700;
        }

        return _RouteStats(
          durationText: "$realMin min",
          distanceText: "$realDist km",
          caloriesText: "-",
          contextLabel: label,
          contextColor: color,
        );
      } else {
        // Fallback Math
        final int minutes = ((roadDistKm / _speedDrive) * 60).round();
        // Force at least 1 min
        final int displayMin = minutes < 1 ? 1 : minutes;

        return _RouteStats(
          durationText: displayMin > 60 ? "${(displayMin / 60).toStringAsFixed(1)} hr" : "$displayMin min",
          distanceText: "${roadDistKm.toStringAsFixed(1)} km",
          caloriesText: "-",
          contextLabel: "Traffic Est.",
          contextColor: Colors.grey,
        );
      }
    }

    // --- CASE 1: WALKING ---
    if (modeIndex == 1) {
      final int minutes = ((roadDistKm / _speedWalk) * 60).round();
      final int displayMin = minutes < 1 ? 1 : minutes;
      final int calories = (roadDistKm * 50).round();

      return _RouteStats(
        durationText: displayMin > 60 ? "${(displayMin / 60).toStringAsFixed(1)} hr" : "$displayMin min",
        distanceText: "${roadDistKm.toStringAsFixed(1)} km",
        caloriesText: "~$calories kcal",
        contextLabel: "~$calories kcal",
        contextColor: Colors.orange,
      );
    }

    // --- CASE 2: TRANSIT ---
    final int minutes = ((roadDistKm / _speedTransit) * 60).round() + 5;
    final int displayMin = minutes < 1 ? 1 : minutes;

    return _RouteStats(
      durationText: displayMin > 60 ? "${(displayMin / 60).toStringAsFixed(1)} hr" : "$displayMin min",
      distanceText: "${roadDistKm.toStringAsFixed(1)} km",
      caloriesText: "-",
      contextLabel: _transitText,
      contextColor: Colors.blue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ref.watch(navigationProvider);
    final LatLng? currentLocation = navigation.currentLocation;

    if (currentLocation != null && widget.item.latitude != null && _realOsrmData == null) {
      _fetchOsrmData(currentLocation);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 DYNAMIC THEME COLORS: Eradicating the purple!
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75, // Slightly taller for a better map view
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // 🟢 PREMIUM DRAG HANDLE
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10)
              ),
            ),
          ),

          // 🟢 PREMIUM HEADER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.wb_sunny_rounded, size: 16, color: Colors.amber),
                          const SizedBox(width: 6),
                          Text(
                            _weatherText,
                            style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontWeight: FontWeight.w600
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 🟢 MAP STACK
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: Stack(
                children: [
                  currentLocation == null
                      ? _buildLoadingState(isDark, accentColor)
                      : RoutePreviewMapView(item: widget.item, currentLocation: currentLocation),

                  Positioned(
                    top: 16, left: 0, right: 0,
                    child: Center(child: _buildTransportSelector(currentLocation, isDark, accentColor, accentForeground)),
                  ),

                  Positioned(
                    bottom: 24, left: 24, right: 24,
                    child: _buildGlassInfoCard(currentLocation, isDark),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportSelector(LatLng? userLoc, bool isDark, Color accentColor, Color accentForeground) {
    final driveStats = _getStats(userLoc, 0);
    final walkStats = _getStats(userLoc, 1);
    final transitStats = _getStats(userLoc, 2);

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8),
            border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeBtn(Icons.directions_car_rounded, driveStats.durationText, 0, isDark: isDark, accentColor: accentColor, accentForeground: accentForeground),
              _modeBtn(Icons.directions_walk_rounded, walkStats.durationText, 1, isEco: true, isDark: isDark, accentColor: accentColor, accentForeground: accentForeground),
              _modeBtn(Icons.directions_bus_rounded, transitStats.durationText, 2, isDark: isDark, accentColor: accentColor, accentForeground: accentForeground),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeBtn(IconData icon, String label, int index, {bool isEco = false, required bool isDark, required Color accentColor, required Color accentForeground}) {
    final isSelected = _selectedModeIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedModeIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          // 🟢 Dynamic Active background
          color: isSelected ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(
                icon,
                size: 18,
                // 🟢 High Contrast on bright aqua
                color: isSelected ? accentForeground : (isDark ? Colors.white60 : Colors.black54)
            ),
            if (isSelected || isEco) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: isSelected ? accentForeground : (isDark ? Colors.white : Colors.black87)
                ),
              ),
            ],
            if (isEco && !isSelected)
              const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.eco_rounded, size: 12, color: Colors.green)
              )
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // 🟢 REFINED & SCALED DASHBOARD CARD UI
  // --------------------------------------------------
  Widget _buildGlassInfoCard(LatLng? userLoc, bool isDark) {
    if (userLoc == null) return const SizedBox.shrink();

    final stats = _getStats(userLoc, _selectedModeIndex);

    final parts = stats.durationText.split(' ');
    final timeValue = parts.isNotEmpty ? parts[0] : '--';
    final timeUnit = parts.length > 1 ? parts[1] : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(28), // 🟢 Scaled radius
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20), // 🟢 Tighter padding
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E).withOpacity(0.85) : Colors.white.withOpacity(0.95),
            border: Border.all(color: isDark ? Colors.white24 : Colors.white),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 15))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔝 TOP ROW: TIME & DISTANCE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "ESTIMATED TIME",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white54 : Colors.black45,
                            letterSpacing: 1.2 // 🟢 Reduced tracking
                        ),
                      ),
                      const SizedBox(height: 2), // 🟢 Tighter gap
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            timeValue,
                            style: TextStyle(
                                fontSize: 28, // 🟢 MUCH smaller, elegant size
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87,
                                letterSpacing: -0.5,
                                height: 1.0
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeUnit,
                            style: TextStyle(
                                fontSize: 14, // 🟢 Scaled down
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white70 : Colors.black54
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // 🟢 Tighter pill
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10), // 🟢 Slightly sharper pill
                    ),
                    child: Text(
                      "${stats.distanceText} away",
                      style: TextStyle(
                          fontSize: 12, // 🟢 Reduced font
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white70 : Colors.black87
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16), // 🟢 Scaled gap
              Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
              const SizedBox(height: 16), // 🟢 Scaled gap

              // ⬇️ BOTTOM ROW: CONTEXTUAL INSIGHT BLOCK
              _buildContextualInsight(stats, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextualInsight(_RouteStats stats, bool isDark) {
    IconData icon;
    String title;

    switch (_selectedModeIndex) {
      case 1:
        icon = Icons.local_fire_department_rounded;
        title = "HEALTH IMPACT";
        break;
      case 2:
        icon = Icons.directions_bus_filled_rounded;
        title = "TRANSIT INFO";
        break;
      default:
        icon = Icons.traffic_rounded;
        title = "LIVE TRAFFIC";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // 🟢 Scaled padding
      decoration: BoxDecoration(
        color: stats.contextColor.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16), // 🟢 Refined radius
        border: Border.all(color: stats.contextColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10), // 🟢 Scaled circle
            decoration: BoxDecoration(
              color: stats.contextColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: stats.contextColor), // 🟢 Scaled icon
          ),
          const SizedBox(width: 12), // 🟢 Scaled gap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10, // 🟢 Scaled font
                    fontWeight: FontWeight.w900,
                    color: stats.contextColor.withOpacity(isDark ? 0.8 : 1.0),
                    letterSpacing: 0.5, // 🟢 Tighter tracking
                  ),
                ),
                const SizedBox(height: 2), // 🟢 Scaled gap
                Text(
                  stats.contextLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 14, // 🟢 Scaled font
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark, Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 3, color: accentColor),
          const SizedBox(height: 20),
          Text(
              'Locating you...',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w600)
          ),
        ],
      ),
    );
  }
}