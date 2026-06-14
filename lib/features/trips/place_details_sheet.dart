import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/osm_place_service.dart';
import '../../services/reverse_geocode_service.dart';
import '../../services/unsplash_service.dart';
import '../../services/reviews_service.dart';
import '../../services/place_story_service.dart';

import 'navigation_provider.dart';
import 'itinerary_item_model.dart';
import 'place_live_data.dart';
import '../../services/osm_poi_service.dart';

import '../../shimmer/journii_shimmer.dart';

// ===========================================================================
// LOCAL IMAGE CACHE & BACKGROUND PRE-WARMER (UNCHANGED)
// ===========================================================================
class PlaceImageCache {
  static final Map<String, String> _cache = {};

  static String? getSync(String query) => _cache[query];

  static Future<String?> getAsync(String query) async {
    if (_cache.containsKey(query)) return _cache[query];
    try {
      final url = await UnsplashService.getPhotoUrl(query);
      if (url != null) _cache[query] = url;
      return url;
    } catch (e) {
      return null;
    }
  }

  static Future<void> prewarm(List<ItineraryItem> items) async {
    for (final item in items) {
      final query = "${item.title} ${item.category ?? 'travel'}";
      if (!_cache.containsKey(query)) {
        await getAsync(query);
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}

class PlaceDetailsSheet extends ConsumerStatefulWidget {
  final ItineraryItem item;

  const PlaceDetailsSheet({super.key, required this.item});

  @override
  ConsumerState<PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends ConsumerState<PlaceDetailsSheet> {
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  bool _isLoadingStory = false;
  String? _fullStoryScript;

  late Future<String?> _imageFuture;
  late Future<ReviewSummary?> _reviewsFuture;
  late Future<String?> _locationFuture;
  late Future<PlaceLiveData?> _liveDataFuture;
  late String _imageQuery;

  @override
  void initState() {
    super.initState();
    _initTts();

    _imageQuery = "${widget.item.title} ${widget.item.category ?? 'travel'}";
    _imageFuture = PlaceImageCache.getAsync(_imageQuery);

    _reviewsFuture = ReviewsService.fetchReviewSummary(
        widget.item.title, widget.item.latitude!, widget.item.longitude!);

    _locationFuture = ReverseGeocodeService.getFriendlyLocation(
        lat: widget.item.latitude!, lon: widget.item.longitude!);

    _liveDataFuture = OsmPlaceService.fetchPlaceData(
      lat: widget.item.latitude!, lon: widget.item.longitude!, placeName: widget.item.title,);
  }

  void _initTts() {
    _flutterTts = FlutterTts();

    _flutterTts.setLanguage("en-US");
    _flutterTts.setPitch(1.0);
    _flutterTts.setSpeechRate(0.5);

    _flutterTts.setStartHandler(() => setState(() => _isSpeaking = true));
    _flutterTts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _flutterTts.setCancelHandler(() => setState(() => _isSpeaking = false));
  }

  Future<void> _toggleAudioGuide() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      return;
    }

    if (_fullStoryScript == null) {
      setState(() => _isLoadingStory = true);

      final history = await PlaceStoryService.fetchPlaceHistory(widget.item.title);
      final content = history ?? widget.item.description;

      _fullStoryScript = "Hi, I'm Journii. Let me show you around ${widget.item.title}. $content";

      setState(() => _isLoadingStory = false);
    }

    if (_fullStoryScript != null) {
      await _flutterTts.speak(_fullStoryScript!);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _launchUrl(String rawUrl) async {
    if (rawUrl.isEmpty) return;
    String cleanUrl = rawUrl.trim();
    if (!cleanUrl.startsWith('http')) cleanUrl = 'https://$cleanUrl';
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (e) {
        debugPrint("Could not launch url: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ref.watch(navigationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 DYNAMIC THEME COLORS: Eradicating the purple!
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🟢 PREMIUM DRAG HANDLE
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(10)
                ),
              ),
            ),

            // --------------------------------------------------
            // 🖼️ IMAGE + SMART AUDIO BUTTON
            // --------------------------------------------------
            Stack(
              children: [
                FutureBuilder<String?>(
                  initialData: PlaceImageCache.getSync(_imageQuery),
                  future: _imageFuture,
                  builder: (context, snapshot) {
                    final imageUrl = snapshot.data;
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return _imageSkeleton();
                    }
                    return _placeImage(primaryUrl: imageUrl, isDark: isDark);
                  },
                ),

                // 🎧 AUDIO BUTTON
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoadingStory ? null : _toggleAudioGuide,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          // 🟢 FIXED: Uses dynamic accentColor when active
                            color: _isSpeaking ? accentColor : Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              if (_isSpeaking)
                                BoxShadow(color: accentColor.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
                            ]
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLoadingStory)
                              const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                              )
                            else
                              Icon(
                                  _isSpeaking ? Icons.stop_rounded : Icons.headphones_rounded,
                                  // 🟢 FIXED: Contrast dynamically updates based on state
                                  color: _isSpeaking ? accentForeground : Colors.white,
                                  size: 16
                              ),
                            const SizedBox(width: 8),
                            Text(
                                _isLoadingStory ? "Loading..." : (_isSpeaking ? "Stop" : "Audio Guide"),
                                // 🟢 FIXED: Contrast dynamically updates based on state
                                style: TextStyle(color: _isSpeaking ? accentForeground : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                            ),
                            if (_isSpeaking) ...[
                              const SizedBox(width: 6),
                              // 🟢 FIXED: Contrast dynamically updates based on state
                              Icon(Icons.graphic_eq_rounded, color: accentForeground, size: 14)
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 📍 HEADER SECTION
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5, height: 1.1),
                      ),
                      const SizedBox(height: 10),

                      // REVIEWS
                      FutureBuilder<ReviewSummary?>(
                        future: _reviewsFuture,
                        builder: (context, snapshot) {
                          final summary = snapshot.data;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (summary != null && summary.reviewCount > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${summary.rating} • ${summary.reviewCount} reviews",
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                                    ),
                                  ],
                                ),
                              _buildSmartBadge(summary, isDark),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 8),
                      FutureBuilder<String?>(
                        future: _locationFuture,
                        builder: (context, snap) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_rounded, size: 16, color: isDark ? Colors.white54 : Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  snap.data ?? 'Locating...',
                                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.grey.shade700, fontWeight: FontWeight.w500),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Day ${widget.item.day}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(height: 24),

            // 📝 DESCRIPTION
            Text(
              widget.item.description,
              style: TextStyle(fontSize: 15, color: isDark ? Colors.white70 : Colors.grey.shade800, height: 1.6),
            ),

            const SizedBox(height: 24),

            // ℹ️ INFO CARDS
            FutureBuilder<PlaceLiveData?>(
              future: _liveDataFuture,
              builder: (context, snapshot) {
                final live = snapshot.data;
                if (live == null) return const SizedBox.shrink();

                return Column(
                  children: [
                    if (live.openingHours != null)
                      _infoCard(Icons.schedule_rounded, "Hours", live.openingHours!, isDark, accentColor),
                    if (live.openingHours != null && live.address != null)
                      const SizedBox(height: 12),
                    if (live.address != null)
                      _infoCard(Icons.map_outlined, "Address", live.address!, isDark, accentColor),
                  ],
                );
              },
            ),

            // 🌐 WEB BUTTON
            FutureBuilder<PlaceLiveData?>(
              future: _liveDataFuture,
              builder: (context, snapshot) {
                final live = snapshot.data;
                if (live?.website != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.public_rounded, size: 18),
                        label: const Text("Official Website", style: TextStyle(fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accentColor, // 🟢 Automatically matches Aqua/Navy theme
                          side: BorderSide(color: accentColor.withOpacity(0.3), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _launchUrl(live!.website!),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            const SizedBox(height: 32),

            // 🚀 NAVIGATION BUTTON
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: navigation.isLoading
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: accentForeground, strokeWidth: 2)) // 🟢 FIXED
                    : Icon(Icons.near_me_rounded, size: 20, color: accentForeground), // 🟢 FIXED
                label: Text(
                    navigation.isLoading ? 'Calculating...' : 'Navigate Here',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: accentForeground) // 🟢 FIXED
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor, // 🟢 FIXED
                  foregroundColor: accentForeground, // 🟢 FIXED
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                onPressed: navigation.isLoading ? null : () {
                  _onNavigateTapped(
                    LatLng(widget.item.latitude!, widget.item.longitude!),
                    widget.item.tripId,
                    isDark,
                    bgColor,
                    textColor,
                    accentColor,
                    accentForeground,
                  );
                },
              ),
            ),

            if (navigation.distanceKm != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car_rounded, size: 16, color: isDark ? Colors.white54 : Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        "${navigation.distanceKm!.toStringAsFixed(1)} km • ${navigation.durationMin!.round()} min drive",
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade700, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // 🌳 WANDER ROUTING TRIGGER
  // --------------------------------------------------
  Future<void> _onNavigateTapped(LatLng destLoc, String tripId, bool isDark, Color bgColor, Color textColor, Color accentColor, Color accentForeground) async {
    final String? selectedTheme = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Choose Your Route", style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _routeOptionTile(ctx, "Fastest Route", "Direct to destination", Icons.flash_on_rounded, Colors.amber, 'fastest', isDark),
            const SizedBox(height: 8),
            _routeOptionTile(ctx, "Scenic Route", "Pass by parks & views", Icons.park_rounded, Colors.green, 'scenic', isDark),
            const SizedBox(height: 8),
            _routeOptionTile(ctx, "Foodie Route", "Pass by cafes & dining", Icons.restaurant_rounded, Colors.deepOrange, 'foodie', isDark),
            const SizedBox(height: 8),
            _routeOptionTile(ctx, "Culture Route", "Pass by monuments & museums", Icons.museum_rounded, Colors.purple, 'culture', isDark),
          ],
        ),
      ),
    );

    if (selectedTheme == null) return;

    if (mounted) Navigator.pop(context);

    final navNotifier = ref.read(navigationProvider.notifier);

    if (selectedTheme == 'fastest') {
      await navNotifier.startNavigation(
        tripId: tripId,
        destLat: destLoc.latitude,
        destLng: destLoc.longitude,
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: accentColor, // 🟢 FIXED: Matches theme
            content: Text("Calculating your $selectedTheme route... ⏳", style: TextStyle(fontWeight: FontWeight.bold, color: accentForeground)) // 🟢 FIXED
        ),
      );
    }

    LatLng? userLoc = ref.read(navigationProvider).currentLocation;
    if (userLoc == null) {
      await navNotifier.getCurrentLocation();
      userLoc = ref.read(navigationProvider).currentLocation;
    }

    List<LatLng>? wanderWaypoints;

    if (userLoc != null) {
      wanderWaypoints = await OsmPoiService.getWanderWaypoints(
        start: userLoc,
        end: destLoc,
        theme: selectedTheme,
      );

      if (wanderWaypoints == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                content: const Text("No perfect scenic stops found on the way. Taking the fastest route!")
            )
        );
      }
    }

    await navNotifier.startNavigation(
      tripId: tripId,
      destLat: destLoc.latitude,
      destLng: destLoc.longitude,
      waypoints: wanderWaypoints,
    );
  }

  Widget _routeOptionTile(BuildContext ctx, String title, String subtitle, IconData icon, Color color, String value, bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: isDark ? Colors.white : Colors.black)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  // --- UI HELPERS ---
  Widget _buildSmartBadge(ReviewSummary? summary, bool isDark) {
    if (summary == null) return const SizedBox.shrink();

    String? text;
    IconData? icon;
    Color? baseColor;

    if (summary.rating >= 4.5 && summary.reviewCount < 100 && summary.reviewCount > 5) {
      text = "Hidden Gem";
      icon = Icons.diamond_outlined;
      baseColor = Colors.teal;
    }
    else if (summary.rating >= 4.5 && summary.reviewCount >= 100) {
      text = "Local Favorite";
      icon = Icons.local_fire_department_outlined;
      baseColor = Colors.deepOrange;
    }
    else if (summary.reviewCount > 1000) {
      text = "Tourist Hotspot";
      icon = Icons.camera_alt_outlined;
      baseColor = Colors.purple;
    }

    final hour = DateTime.now().hour;
    if (text == null && hour >= 16 && hour <= 19) {
      final lowerTitle = widget.item.title.toLowerCase();
      if (lowerTitle.contains('park') || lowerTitle.contains('view') || lowerTitle.contains('fort')) {
        text = "Golden Hour Spot";
        icon = Icons.wb_twilight_rounded;
        baseColor = Colors.indigo;
      }
    }

    if (text == null || baseColor == null) return const SizedBox.shrink();

    // 🟢 FIXED: Using baseColor directly.
    // If it's dark mode, we use .withOpacity for a softer look instead of .shade200
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: baseColor.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: baseColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? baseColor.withOpacity(0.8) : baseColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: isDark ? baseColor.withOpacity(0.8) : baseColor,
                letterSpacing: 0.5
            ),
          ),
        ],
      ),
    );
  }

  // 🟢 FIXED: Passed in the dynamic accentColor to theme the icons
  Widget _infoCard(IconData icon, String title, String value, bool isDark, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accentColor), // 🟢 FIXED
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: isDark ? Colors.white54 : Colors.black54, letterSpacing: 1.0)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
          ])),
        ],
      ),
    );
  }

  Widget _placeImage({required String? primaryUrl, required bool isDark}) {
    if (primaryUrl != null && primaryUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            primaryUrl,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => _fallbackPlaceholder(isDark),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _fallbackPlaceholder(isDark),
      ),
    );
  }

  Widget _fallbackPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_rounded, size: 32, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 8),
          Text("No image available", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white30 : Colors.black38)),
        ],
      ),
    );
  }

  Widget _imageSkeleton() => Container(
    height: 200,
    margin: const EdgeInsets.only(bottom: 16),
    child: const JourniiShimmer(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    ),
  );
}