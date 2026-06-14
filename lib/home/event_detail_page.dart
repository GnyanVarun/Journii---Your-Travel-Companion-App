import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import your new backend service
import '../../services/event_backend_service.dart';
import '../widgets/trip_selector_sheet.dart';

class EventDetailPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailPage({super.key, required this.event});

  @override
  ConsumerState<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends ConsumerState<EventDetailPage> {
  bool _isLoadingStatus = true;
  bool _isAddedToItinerary = false;

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
  }

  // 🟢 Checks Supabase when the page opens to see if the event is already in the itinerary
  Future<void> _checkSavedStatus() async {
    try {
      final service = ref.read(eventBackendProvider);

      final added = await service.isEventAddedToItinerary(widget.event['id'].toString());

      if (mounted) {
        setState(() {
          _isAddedToItinerary = added;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      debugPrint("Status check error: $e");
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  // 🟢 DYNAMIC GRADIENT ENGINE (Matches the Explore Tab)
  // FIXED: Now takes the dynamic baseAccent so it doesn't default to purple!
  Map<String, dynamic> _getEventIdentity(Color baseAccent) {
    final String name = (widget.event['name'] ?? '').toLowerCase();

    List<Color> gradientColors = [baseAccent, const Color(0xFF1BFFFF)];
    IconData categoryIcon = Icons.explore_rounded;

    if (name.contains('concert') || name.contains('tour') || name.contains('live') || name.contains('music')) {
      gradientColors = [const Color(0xFF8A2387), const Color(0xFFE94057)];
      categoryIcon = Icons.music_note_rounded;
    } else if (name.contains('sport') || name.contains('match') || name.contains('cup') || name.contains('marathon')) {
      gradientColors = [const Color(0xFFFF416C), const Color(0xFFFF4B2B)];
      categoryIcon = Icons.sports_basketball_rounded;
    } else if (name.contains('festival') || name.contains('fest') || name.contains('party')) {
      gradientColors = [const Color(0xFFF2994A), const Color(0xFFF2C94C)];
      categoryIcon = Icons.celebration_rounded;
    } else if (name.contains('theater') || name.contains('play') || name.contains('show') || name.contains('comedy')) {
      gradientColors = [const Color(0xFF11998E), const Color(0xFF38EF7D)];
      categoryIcon = Icons.theater_comedy_rounded;
    }

    return {
      'colors': gradientColors,
      'icon': categoryIcon,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardBorder = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF6B6B6B);

    // 🟢 DYNAMIC THEME COLORS: Replaces the hardcoded purple
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);

    final eventIdentity = _getEventIdentity(accentColor);
    final List<Color> bgGradient = eventIdentity['colors'];
    final IconData bgIcon = eventIdentity['icon'];

    // 🟢 SMART CONTRAST ENGINE: Calculates if the event color is bright or dark
    // and automatically switches the text color between Black and White to ensure perfect readability!
    final dynamicButtonTextColor = bgGradient.first.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    // 🟢 SMART DESCRIPTION ENGINE
    String description = "";
    String rawDesc = widget.event['description']?.toString() ?? "";

    if (rawDesc.toLowerCase().contains("sourced from predicthq") || rawDesc.trim().isEmpty) {
      final String name = widget.event['name'] ?? 'This event';
      final String venue = widget.event['venue'] ?? 'the venue';
      String cleanCategory = (widget.event['categoryTag'] ?? 'events').toString().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

      description = "Get ready to experience $name live at $venue! As one of the top upcoming $cleanCategory in the area, it is highly recommended to plan ahead and secure your spot early.";
    } else {
      description = rawDesc;
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 🟢 ALGORITHMIC PARALLAX HERO
              SliverAppBar(
                expandedHeight: 380.0,
                pinned: true,
                stretch: true,
                backgroundColor: bgColor,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: bgGradient,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            bgIcon,
                            size: 140,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [bgColor, bgColor.withOpacity(0.0)],
                            stops: const [0.0, 0.4],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 🟢 EVENT DETAILS
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 120), // Bottom padding for sticky bar
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Premium Category Tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: bgGradient.first.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: bgGradient.first.withOpacity(0.3)),
                        ),
                        child: Text(
                          widget.event['categoryTag']?.toUpperCase() ?? "EVENT",
                          style: TextStyle(
                              color: bgGradient.first,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Title
                      Text(
                        widget.event['name'] ?? 'Unknown Event',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -1.0
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Info Cards (Date & Venue)
                      _buildInfoRow(
                        icon: Icons.calendar_today_rounded,
                        title: "Date & Time",
                        subtitle: widget.event['date'] ?? 'TBA',
                        cardColor: cardColor,
                        cardBorder: cardBorder,
                        textColor: textColor,
                        textMuted: textMuted,
                        accentColor: bgGradient.first,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        icon: Icons.location_on_rounded,
                        title: "Venue",
                        subtitle: widget.event['venue'] ?? 'Location TBA',
                        cardColor: cardColor,
                        cardBorder: cardBorder,
                        textColor: textColor,
                        textMuted: textMuted,
                        accentColor: bgGradient.first,
                      ),

                      const SizedBox(height: 48),

                      // 🟢 ABOUT SECTION
                      Text(
                          "ABOUT THIS EVENT",
                          style: TextStyle(
                              color: textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5
                          )
                      ),
                      const SizedBox(height: 16),
                      Text(
                        description,
                        style: TextStyle(
                          color: textColor.withOpacity(0.85),
                          fontSize: 16,
                          height: 1.7,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 🟢 MODERN FLOATING STICKY ACTION BAR
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 20,
                      bottom: MediaQuery.of(context).padding.bottom + 20
                  ),
                  decoration: BoxDecoration(
                    color: bgColor.withOpacity(0.75),
                    border: Border(top: BorderSide(color: cardBorder, width: 1.5)),
                  ),
                  child: Row(
                    children: [
                      // 🟢 REFINED "ADD TO ITINERARY" BUTTON
                      Expanded(
                        child: SizedBox(
                          height: 56, // The button is 56px tall
                          child: ElevatedButton(
                            onPressed: _isAddedToItinerary
                                ? null
                                : () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) => TripSelectorSheet(
                                  event: widget.event,
                                  onAdded: () {
                                    setState(() => _isAddedToItinerary = true);
                                  },
                                ),
                              );
                            },
                            // 🟢 FIXED: The button now chameleons to match the Event's specific color!
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isAddedToItinerary ? Colors.grey : bgGradient.first,
                              foregroundColor: _isAddedToItinerary ? Colors.white : dynamicButtonTextColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            ),
                            child: _isLoadingStatus
                                ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: _isAddedToItinerary ? Colors.white : dynamicButtonTextColor, strokeWidth: 2)
                            )
                                : Text(
                              _isAddedToItinerary ? "Added to Trip" : "Add to Itinerary",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: _isAddedToItinerary ? Colors.white : dynamicButtonTextColor
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color cardColor,
    required Color cardBorder,
    required Color textColor,
    required Color textMuted,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16)
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    title,
                    style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}