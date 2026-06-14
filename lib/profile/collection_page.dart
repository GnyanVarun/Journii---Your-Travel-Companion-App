import 'dart:ui'; // 🟢 REQUIRED FOR GLASSMORPHISM
import 'package:flutter/material.dart';
import '../../services/social_drop_service.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/unsplash_service.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late Future<List<SocialDrop>> _collectionFuture;

  @override
  void initState() {
    super.initState();
    _collectionFuture = SocialDropService.fetchMyCollection();
  }

  Future<void> _fixOldTrips() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upgrading old trips... Please wait.')),
    );

    try {
      // 🟢 FIX: Fetch all trips and filter in Dart to avoid Supabase version syntax errors!
      final List<dynamic> allTrips = await Supabase.instance.client
          .from('trips')
          .select();

      // Find only the trips that are missing an image
      final tripsToFix = allTrips.where((trip) => trip['badge_image_url'] == null).toList();

      if (tripsToFix.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ No old trips need upgrading!')),
          );
        }
        return;
      }

      for (var trip in tripsToFix) {
        final id = trip['id'];
        final destination = trip['destination'] ?? trip['title'] ?? 'Travel';

        final imageUrl = await UnsplashService.getPhotoUrl(destination);
        final slogan = UnsplashService.generateSlogan(destination);

        await Supabase.instance.client
            .from('trips')
            .update({
          'badge_image_url': imageUrl,
          'badge_slogan': slogan,
        })
            .eq('id', id);
      }

      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ All old trips have been upgraded!')),
        );
      }
    } catch (e) {
      print("Error fixing trips: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF9F9FB);

    // 🟢 DYNAMIC THEME COLORS: Replaces the hardcoded purple
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: Text("My Collection", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5, color: isDark ? Colors.white : Colors.black)),
          backgroundColor: bgColor,
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.auto_fix_high_rounded, color: isDark ? Colors.white : accentColor, size: 20),
                onPressed: _fixOldTrips,
                tooltip: "Upgrade Old Trips",
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(70),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
              ),
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                // 🟢 FIXED: The label text switches to Black to contrast against the Aqua tab in dark mode
                labelColor: accentForeground,
                unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.style_rounded, size: 18), SizedBox(width: 8), Text("Passport")])),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.diamond_rounded, size: 18), SizedBox(width: 8), Text("Travel Dex")])),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildPassportTab(isDark, accentColor),
            _buildTravelDexTab(isDark, accentColor),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // TAB 1: THE PASSPORT
  // ---------------------------------------------------------
  Widget _buildPassportTab(bool isDark, Color accentColor) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('trips')
          .select()
          .order('start_date', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 🟢 FIXED: Spinner dynamically glows
          return Center(child: CircularProgressIndicator(color: accentColor));
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error loading passport: ${snapshot.error}", style: TextStyle(color: isDark ? Colors.white : Colors.black)));
        }

        final trips = snapshot.data ?? [];

        if (trips.isEmpty) {
          return _buildEmptyState(
            icon: Icons.flight_takeoff_rounded,
            title: "Blank Passport",
            subtitle: "Create a trip to generate your first badge.",
            isDark: isDark,
            accentColor: accentColor,
          );
        }

        return GridView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            childAspectRatio: 0.72, // Taller, trading-card style
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: trips.length,
          itemBuilder: (context, index) {
            final trip = trips[index];
            final destination = trip['destination'] ?? trip['title'] ?? 'Unknown';

            final List<String> fallbackImages = [
              'https://images.unsplash.com/photo-1488085061387-422e29b40080?auto=format&fit=crop&w=500&q=60',
              'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?auto=format&fit=crop&w=500&q=60',
              'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?auto=format&fit=crop&w=500&q=60',
              'https://images.unsplash.com/photo-1499856871958-5b9627545d1a?auto=format&fit=crop&w=500&q=60',
              'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=500&q=60',
            ];

            final fallbackIndex = destination.length % fallbackImages.length;
            final dynamicFallbackUrl = fallbackImages[fallbackIndex];
            final imageUrl = trip['badge_image_url'] ?? dynamicFallbackUrl;
            final slogan = trip['badge_slogan'] ?? 'The adventure awaits.';

            final endDate = trip['end_date'] != null ? DateTime.parse(trip['end_date']) : DateTime.now();
            final isUnlocked = endDate.isBefore(DateTime.now());

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Base Image
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(color: isDark ? Colors.white12 : Colors.black12);
                      },
                    ),

                    // Locked Glass Overlay
                    if (!isUnlocked)
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          color: isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.3),
                        ),
                      ),

                    // Gradient for Text Readability
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            isUnlocked ? Colors.black.withOpacity(0.8) : Colors.transparent,
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isUnlocked)
                            Expanded(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                                  child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
                                ),
                              ),
                            ),

                          Text(
                            destination,
                            style: TextStyle(
                              color: isUnlocked ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              letterSpacing: -0.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          if (isUnlocked) ...[
                            const SizedBox(height: 6),
                            Text(
                              '"$slogan"',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ] else ...[
                            const SizedBox(height: 6),
                            Text(
                              "Unlocks after trip",
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------
  // TAB 2: THE TRAVEL DEX
  // ---------------------------------------------------------
  Widget _buildTravelDexTab(bool isDark, Color accentColor) {
    return FutureBuilder<List<SocialDrop>>(
      future: _collectionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 🟢 FIXED: Spinner dynamically glows
          return Center(child: CircularProgressIndicator(color: accentColor));
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}", style: TextStyle(color: isDark ? Colors.white : Colors.black)));
        }

        final drops = snapshot.data ?? [];

        if (drops.isEmpty) {
          return _buildEmptyState(
            icon: Icons.auto_awesome_outlined,
            title: "Your Dex is empty!",
            subtitle: "Explore the map to find hidden memories.",
            isDark: isDark,
            accentColor: accentColor,
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          itemCount: drops.length,
          itemBuilder: (context, index) {
            return _buildMemoryCard(drops[index], isDark, accentColor);
          },
        );
      },
    );
  }

  Widget _buildMemoryCard(SocialDrop drop, bool isDark, Color accentColor) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.05);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 6))],
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // 🟢 FIXED: Match dynamic theme
                    color: accentColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.diamond_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drop.userName,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            "${drop.location.latitude.toStringAsFixed(4)}, ${drop.location.longitude.toStringAsFixed(4)}",
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade100),
            ),
            Text(
              '"${drop.message}"',
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helpers ---
  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle, required bool isDark, required Color accentColor}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                // 🟢 FIXED: Match dynamic theme
                color: accentColor.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: accentColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54, height: 1.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}