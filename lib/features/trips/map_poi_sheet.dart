import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/reverse_geocode_service.dart';
import 'place_live_data.dart';
import 'navigation_provider.dart';
import '../../shimmer/journii_shimmer.dart';

class MapPoiSheet extends ConsumerStatefulWidget {
  final String title;
  final String category;
  final double lat;
  final double lon;
  final String? tripId;

  const MapPoiSheet({
    super.key,
    required this.title,
    required this.category,
    required this.lat,
    required this.lon,
    this.tripId,
  });

  @override
  ConsumerState<MapPoiSheet> createState() => _MapPoiSheetState();
}

class _MapPoiSheetState extends ConsumerState<MapPoiSheet> {
  // 🟢 We only need ONE Future now!
  late Future<PlaceLiveData?> _richDataFuture;

  @override
  void initState() {
    super.initState();
    // Use Nominatim to get everything in one shot
    _richDataFuture = ReverseGeocodeService.getRichLocationDetails(
      lat: widget.lat,
      lon: widget.lon,
    );
  }

  Future<void> _launchUrl(String rawUrl) async {
    if (rawUrl.isEmpty) return;
    String cleanUrl = rawUrl.trim();
    if (!cleanUrl.startsWith('http')) cleanUrl = 'https://$cleanUrl';
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint("Could not launch url: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ref.watch(navigationProvider);

    // 🟢 DYNAMIC THEME VARIABLES
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 FIXED: Eradicated the hardcoded signatureBlue and applied Aqua/Navy logic
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🟢 PREMIUM DRAG HANDLE
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10)
              ),
            ),
          ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                    widget.title,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, color: textColor, letterSpacing: -0.5)
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withOpacity(0.3))
                ),
                child: Text(
                    widget.category.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: accentColor, letterSpacing: 0.5)
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 🟢 SINGLE FUTURE BUILDER WITH BENTO UI
          FutureBuilder<PlaceLiveData?>(
            future: _richDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 120,
                  child: JourniiShimmer(borderRadius: BorderRadius.all(Radius.circular(20))),
                );
              }

              final data = snapshot.data;

              return Column(
                children: [
                  // 🟢 UNIFIED INFO CARD
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
                    ),
                    child: Column(
                      children: [
                        // Address
                        if (data?.address != null)
                          _buildModernInfoRow(Icons.location_on_rounded, data!.address!, isDark, accentColor)
                        else
                          _buildModernInfoRow(Icons.location_on_rounded, "Location pinned on map", isDark, accentColor, isMissing: true),

                        // Hours
                        if (data?.openingHours != null && data!.openingHours!.trim().isNotEmpty) ...[
                          _buildDivider(isDark),
                          _buildModernInfoRow(Icons.schedule_rounded, data.openingHours!.replaceAll(';', '\n'), isDark, Colors.green),
                        ],

                        // Phone Number
                        if (data?.phone != null) ...[
                          _buildDivider(isDark),
                          _buildModernInfoRow(Icons.phone_rounded, data!.phone!, isDark, accentColor),
                        ],

                        // Cuisine Type
                        if (data?.cuisine != null) ...[
                          _buildDivider(isDark),
                          _buildModernInfoRow(Icons.restaurant_menu_rounded, "Cuisine: ${data!.cuisine!}", isDark, Colors.orange),
                        ],

                        // Wheelchair Accessibility
                        if (data?.wheelchair != null && data!.wheelchair != 'no') ...[
                          _buildDivider(isDark),
                          _buildModernInfoRow(Icons.accessible_rounded, "Wheelchair Accessible", isDark, Colors.blue),
                        ],
                      ],
                    ),
                  ),

                  // Website Button
                  if (data?.website != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () => _launchUrl(data!.website!),
                        icon: const Icon(Icons.public_rounded, size: 20),
                        label: const Text("Official Website", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        style: OutlinedButton.styleFrom(
                          // 🟢 FIXED: Beautifully uses dynamic accentColor
                          foregroundColor: accentColor,
                          side: BorderSide(color: accentColor.withOpacity(0.3), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                  ]
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // 🟢 NAVIGATION BUTTON
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              icon: navigation.isLoading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: accentForeground, strokeWidth: 2)) // 🟢 FIXED
                  : Icon(Icons.near_me_rounded, size: 20, color: accentForeground), // 🟢 FIXED
              label: Text(
                  navigation.isLoading ? 'Calculating Route...' : 'Navigate Here',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: accentForeground) // 🟢 FIXED
              ),
              style: ElevatedButton.styleFrom(
                // 🟢 FIXED: Follows dynamic theme logic for both background and text
                backgroundColor: accentColor,
                foregroundColor: accentForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              onPressed: navigation.isLoading ? null : () async {
                Navigator.pop(context);

                final navNotifier = ref.read(navigationProvider.notifier);
                await navNotifier.startNavigation(
                  tripId: widget.tripId ?? 'adhoc_navigation',
                  destLat: widget.lat,
                  destLng: widget.lon,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🟢 HELPER: Sleek dividers inside the info card
  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
      indent: 56, // Aligns with the text, skipping the icon
    );
  }

  // 🟢 HELPER: Modern list rows for the bento card
  Widget _buildModernInfoRow(IconData icon, String text, bool isDark, Color iconColor, {bool isMissing = false}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMissing ? (isDark ? Colors.white12 : Colors.black.withOpacity(0.05)) : iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
                icon,
                size: 16,
                color: isMissing ? (isDark ? Colors.white30 : Colors.black38) : iconColor
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isMissing ? (isDark ? Colors.white54 : Colors.grey.shade600) : (isDark ? Colors.white : Colors.black87),
                    fontStyle: isMissing ? FontStyle.italic : FontStyle.normal,
                    height: 1.4
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}