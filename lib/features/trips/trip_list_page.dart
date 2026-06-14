import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'trip_provider.dart';
import 'trip_model.dart';
import 'trip_detail_page.dart';
import 'create_trip_sheet.dart';
import 'edit_trip_sheet.dart';
import '../../services/sync_service.dart';

// 🔄 CHANGED to ConsumerStatefulWidget for Auto-Sync
class TripListPage extends ConsumerStatefulWidget {
  const TripListPage({super.key});

  @override
  ConsumerState<TripListPage> createState() => _TripListPageState();
}

class _TripListPageState extends ConsumerState<TripListPage> {
  @override
  void initState() {
    super.initState();
    // 🚀 AUTO-SYNC ON LAUNCH
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAutoSync();
    });
  }

  Future<void> _runAutoSync() async {
    // Only auto-sync if we have NO trips loaded (Cold Start)
    if (ref.read(tripProvider).isEmpty) {
      try {
        await SyncService.syncAll(ref);
      } catch (e) {
        print("Auto-sync silent fail: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(tripProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F0);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Your Journeys',
          style: TextStyle(
            color: textColor,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.cloud_sync_rounded, color: isDark ? Colors.white70 : Colors.black87),
                tooltip: "Sync Data",
                onPressed: () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Syncing Trips & Itineraries... ☁️"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );

                    // 🛠️ CALL THE MASTER SYNC
                    await SyncService.syncAll(ref);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text("✅ Sync Complete!"),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    }
                  } catch (e) {
                    print("SYNC ERROR: $e");
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text("Sync Failed", style: TextStyle(fontWeight: FontWeight.bold)),
                          content: Text(e.toString()),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))
                          ],
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: trips.isEmpty
          ? _EmptyState(onCreate: () => _openCreateTripSheet(context))
          : ListView.builder(
        physics: const BouncingScrollPhysics(),
        // Padding ensures the last item scrolls past the FAB & Nav Bar
        padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 180),
        itemCount: trips.length,
        itemBuilder: (context, index) {
          final trip = trips[index];
          return _TripTile(trip: trip);
        },
      ),
      // 🟢 FIX 1: Pushed the FAB up by 110 pixels to sit completely above your custom Nav Bar
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 110.0),
        child: FloatingActionButton.extended(
          elevation: 4,
          highlightElevation: 8,
          // 🟢 FIXED: Themed Background Color
          backgroundColor: accentColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          onPressed: () => _openCreateTripSheet(context),
          // 🟢 FIXED: Themed Foreground Color for high contrast
          icon: Icon(Icons.add_rounded, color: accentForeground),
          label: Text(
            "New Trip",
            style: TextStyle(color: accentForeground, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }

  void _openCreateTripSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 🟢 FIX 2: Replaced 'Colors.transparent' with a solid background color
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      // 🟢 FIX 3: Forced the rounded corners onto the solid background
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const CreateTripSheet(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF6B6B6B);

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.flight_takeoff_rounded, size: 64, color: accentColor),
            ),
            const SizedBox(height: 32),
            Text(
              'Plan your first journey',
              style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Create a trip with dates and let Journii handle the rest of your itinerary.',
              style: TextStyle(color: textMuted, fontSize: 16, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: accentForeground, // 🟢 FIXED: Contrast dynamically checks
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(
                  'Create Trip',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: accentForeground),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  final Trip trip;
  const _TripTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardBorder = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF6B6B6B);

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);

    final subtitle = _buildSubtitle();
    final status = _tripStatus();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            // Icon Container
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08), // 🟢 FIXED
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.map_rounded, color: accentColor, size: 28), // 🟢 FIXED
            ),
            const SizedBox(width: 20),
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  _StatusChip(status: status),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Caret
            Icon(Icons.arrow_forward_ios_rounded, color: textMuted.withOpacity(0.3), size: 16),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    if (trip.startDate == null || trip.endDate == null) {
      return 'Dates not set';
    }
    final start = _formatDate(trip.startDate!);
    final end = _formatDate(trip.endDate!);
    final days = trip.durationDays ?? 0;
    return '$start – $end • $days days';
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }

  TripStatus _tripStatus() {
    if (trip.startDate == null || trip.endDate == null) {
      return TripStatus.unknown;
    }
    final today = DateTime.now();
    final start = _dateOnly(trip.startDate!);
    final end = _dateOnly(trip.endDate!);
    final now = _dateOnly(today);

    if (now.isBefore(start)) return TripStatus.upcoming;
    if (now.isAfter(end)) return TripStatus.past;
    return TripStatus.ongoing;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

enum TripStatus { upcoming, ongoing, past, unknown }

class _StatusChip extends StatelessWidget {
  final TripStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);

    late final String label;
    late final Color color;

    switch (status) {
      case TripStatus.upcoming:
        label = 'UPCOMING';
        color = const Color(0xFFE94057); // Vibrant Pink/Orange
        break;
      case TripStatus.ongoing:
        label = 'ONGOING';
        color = const Color(0xFF11998E); // Vibrant Teal/Green
        break;
      case TripStatus.past:
        label = 'PAST';
        color = Colors.grey.shade600;
        break;
      default:
        label = 'PLANNING';
        color = accentColor; // 🟢 FIXED: Follows dynamic theme logic
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}