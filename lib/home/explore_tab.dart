import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../services/predicthq_service.dart';
import 'event_detail_page.dart';

class ExploreTab extends ConsumerStatefulWidget {
  const ExploreTab({super.key});

  @override
  ConsumerState<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<ExploreTab> {
  // 1. STATE & CONTROLLERS
  int _selectedFilterIndex = 0;
  final List<String> _filters = ["All", "Concerts 🎸", "Sports ⚽", "Festivals 🎪", "Theater 🎭"];
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  final PageController _pageController = PageController(viewportFraction: 0.85);

  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String _currentCity = "London";

  double _currentLat = 51.5074;
  double _currentLon = -0.1278;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // 🟢 SMART ZOOM: Snap to events or city center
  void _fitMapToMarkers() {
    if (_events.isEmpty) {
      _mapController.move(LatLng(_currentLat, _currentLon), 12.0);
      return;
    }

    final points = _events
        .where((e) => e['latitude'] != 0.0 && e['longitude'] != 0.0)
        .map((e) => LatLng(e['latitude'], e['longitude']))
        .toList();

    if (points.isEmpty) {
      _mapController.move(LatLng(_currentLat, _currentLon), 12.0);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(50, 150, 50, 180),
      ),
    );
  }

  Future<void> _handleSearch(String cityQuery) async {
    if (cityQuery.trim().isEmpty) return;

    setState(() => _isLoading = true);
    final geoKey = dotenv.env['GEOAPIFY_API_KEY'] ?? '';

    try {
      final geoUrl = Uri.parse(
          "https://api.geoapify.com/v1/geocode/search?text=${Uri.encodeComponent(cityQuery)}&apiKey=$geoKey"
      );
      final geoRes = await http.get(geoUrl);

      if (geoRes.statusCode == 200) {
        final geoData = json.decode(geoRes.body);
        if (geoData['features'].isNotEmpty) {
          final coords = geoData['features'][0]['geometry']['coordinates'];
          final lon = coords[0] as double;
          final lat = coords[1] as double;
          final formattedName = geoData['features'][0]['properties']['city'] ?? cityQuery;

          setState(() {
            _currentCity = formattedName;
            _searchController.text = formattedName;
            _currentLat = lat;
            _currentLon = lon;
          });

          await _loadEvents();
        }
      }
    } catch (e) {
      debugPrint("Search Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    final results = await PredictHQService.fetchGlobalEvents(
      category: _filters[_selectedFilterIndex],
      lat: _currentLat,
      lon: _currentLon,
    );

    if (mounted) {
      setState(() {
        _events = results;
        _isLoading = false;
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _fitMapToMarkers();
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final geoKey = dotenv.env['GEOAPIFY_API_KEY'] ?? '';
    final mapStyle = isDark ? "dark-matter" : "positron";

    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final textMuted = isDark ? Colors.white54 : Colors.black54;

    // 🟢 FIXED: Explicitly sets Aqua for Dark Mode and Navy for Light Mode
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    // 🟢 Ensures dark text on the bright Aqua background, and white text on Navy
    final accentForeground = isDark ? Colors.black : Colors.white;

    final bottomNavClearance = MediaQuery.of(context).padding.bottom + 96.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. THE MAP
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_currentLat, _currentLon),
              initialZoom: 12.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: "https://maps.geoapify.com/v1/tile/$mapStyle/{z}/{x}/{y}.png?apiKey=$geoKey",
                userAgentPackageName: 'com.journii.app',
              ),
              MarkerLayer(
                markers: _events
                    .where((event) => event['latitude'] != 0.0 && event['longitude'] != 0.0)
                    .map((event) {
                  return Marker(
                    key: ValueKey(event['id']),
                    point: LatLng(event['latitude'], event['longitude']),
                    width: 140,
                    height: 80,
                    child: _buildCustomMarker(event, isDark, accentColor),
                  );
                }).toList(),
              ),
            ],
          ),

          // 2. TOP FLOATING UI: SEARCH + FILTERS
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0, right: 0,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildGlassContainer(
                    isDark: isDark,
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: _handleSearch,
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: "Search destinations...",
                        hintStyle: TextStyle(color: textMuted, fontWeight: FontWeight.normal),
                        prefixIcon: Icon(Icons.search, color: isDark ? Colors.white70 : accentColor),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _filters.length,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedFilterIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _buildFilterPill(
                          label: _filters[index],
                          isSelected: isSelected,
                          isDark: isDark,
                          accentColor: accentColor,
                          accentForeground: accentForeground,
                          onTap: () {
                            setState(() => _selectedFilterIndex = index);
                            _loadEvents();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 3. MODERN HORIZONTAL CAROUSEL
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomNavClearance + 8,
            child: _isLoading
                ? const SizedBox.shrink()
                : _events.isEmpty
                ? _buildNoEventsCard(isDark, textMuted)
                : SizedBox(
              height: 140,
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  final event = _events[index];
                  if (event['latitude'] != 0.0 && event['longitude'] != 0.0) {
                    _mapController.move(
                      LatLng(event['latitude'], event['longitude']),
                      13.5,
                    );
                  }
                },
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: _buildCarouselEventTile(_events[index], isDark, accentColor),
                  );
                },
              ),
            ),
          ),

          // 4. MODERN FLOATING LOADER
          if (_isLoading)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(color: accentColor, strokeWidth: 2.5)
                        ),
                        const SizedBox(width: 16),
                        Text(
                            "Locating events...",
                            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET HELPERS
  // ===========================================================================

  Widget _buildGlassContainer({required Widget child, required bool isDark}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required bool isDark,
    required Color accentColor,
    required Color accentForeground,
    required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor
              : (isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9)),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected
                ? accentColor
                : (isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08)),
            width: 1.5,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? accentForeground : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomMarker(Map<String, dynamic> event, bool isDark, Color accentColor) {
    return GestureDetector(
      onTap: () {
        final index = _events.indexOf(event);
        if (index != -1 && _pageController.hasClients) {
          _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(Icons.location_on, color: accentColor, size: 38),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                ),
                child: Text(
                  event['name'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🟢 NEW: Dynamic Algorithmic Gradient Generator
  Widget _buildDynamicEventGraphic(Map<String, dynamic> event) {
    final String name = (event['name'] ?? '').toLowerCase();

    // Default Journii aesthetic
    List<Color> gradientColors = [const Color(0xFF2E3192), const Color(0xFF1BFFFF)];
    IconData categoryIcon = Icons.explore_rounded;

    // Smart Keyword Matching for Categories
    if (name.contains('concert') || name.contains('tour') || name.contains('live') || name.contains('music')) {
      gradientColors = [const Color(0xFF8A2387), const Color(0xFFE94057)]; // Neon Purple/Pink
      categoryIcon = Icons.music_note_rounded;
    } else if (name.contains('sport') || name.contains('match') || name.contains('cup') || name.contains('marathon')) {
      gradientColors = [const Color(0xFFFF416C), const Color(0xFFFF4B2B)]; // Energetic Orange/Red
      categoryIcon = Icons.sports_basketball_rounded;
    } else if (name.contains('festival') || name.contains('fest') || name.contains('party')) {
      gradientColors = [const Color(0xFFF2994A), const Color(0xFFF2C94C)]; // Sunset Yellow
      categoryIcon = Icons.celebration_rounded;
    } else if (name.contains('theater') || name.contains('play') || name.contains('show') || name.contains('comedy')) {
      gradientColors = [const Color(0xFF11998E), const Color(0xFF38EF7D)]; // Emerald Green
      categoryIcon = Icons.theater_comedy_rounded;
    }

    return Container(
      width: 100,
      height: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          categoryIcon,
          color: Colors.white.withOpacity(0.85),
          size: 42,
        ),
      ),
    );
  }

  Widget _buildCarouselEventTile(Map<String, dynamic> event, bool isDark, Color accentColor) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EventDetailPage(event: event))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E20) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8)
            )
          ],
        ),
        child: Row(
          children: [
            // 🟢 Swapped Image.network for our algorithmic gradient
            _buildDynamicEventGraphic(event),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        event['date'],
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      event['name'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.1,
                          letterSpacing: -0.3
                      )
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event['venue'],
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEventsCard(bool isDark, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E20) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.1), blurRadius: 20, offset: const Offset(0, 8))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined, size: 32, color: textMuted.withOpacity(0.5)),
            const SizedBox(width: 16),
            Text(
                "No upcoming events found\naround $_currentCity",
                style: TextStyle(color: textMuted, fontSize: 14, height: 1.4)
            ),
          ],
        ),
      ),
    );
  }
}