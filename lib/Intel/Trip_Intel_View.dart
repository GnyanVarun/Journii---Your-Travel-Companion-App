import 'package:flutter/material.dart';
import '../../services/ai_travel_service.dart';

class TripIntelView extends StatefulWidget {
  final String city;

  const TripIntelView({super.key, required this.city});

  @override
  State<TripIntelView> createState() => _TripIntelViewState();
}

class _TripIntelViewState extends State<TripIntelView> {
  Future<Map<String, dynamic>>? _intelFuture;

  @override
  void initState() {
    super.initState();
    _loadIntel();
  }

  void _loadIntel() {
    setState(() {
      _intelFuture = AITravelService.fetchTripIntel(widget.city);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF9F9FB);

    // 🟢 DYNAMIC THEME COLORS: Eradicating the purple!
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _intelFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 🟢 FIXED: Loading spinner dynamically matches the theme
                  CircularProgressIndicator(color: accentColor),
                  const SizedBox(height: 16),
                  Text("Gathering Intel...", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: ElevatedButton.icon(
                // 🟢 FIXED: Button background and foreground dynamically contrast
                style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: accentForeground),
                onPressed: _loadIntel,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry Connection"),
              ),
            );
          }

          final data = snapshot.data!;
          final laws = data['laws'] as List;
          final logistics = data['logistics'] as List? ?? [];
          final magicMoment = data['magic_moment'] as Map<String, dynamic>?;
          final hacks = data['hacks'] as List;
          final scams = data['scams'] as List? ?? [];
          final sos = data['sos']?.toString() ?? "112";

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 24,
              left: 24,
              right: 24,
              bottom: 60,
            ),
            children: [
              // 🟢 HERO SECTION
              Text("INTELLIGENCE", style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
              const SizedBox(height: 4),
              Text(widget.city, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -1.0, height: 1.1)),
              const SizedBox(height: 32),

              // 🌅 MAGIC MOMENT HERO
              if (magicMoment != null) ...[
                _FluidHeroCard(data: magicMoment, isDark: isDark, accentColor: accentColor),
                const SizedBox(height: 32),
              ],

              // 🟢 THE STACKED COMMAND CENTER
              Text("Operational Intel", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)),
              const SizedBox(height: 16),

              _ActionCard(
                title: "Safety & Laws",
                subtitle: "Know the red zones and local rules",
                icon: Icons.gavel_rounded,
                iconColor: const Color(0xFFFF5A5F),
                isDark: isDark,
                onTap: () => _showRedZoneSheet(context, laws, isDark),
              ),
              _ActionCard(
                title: "Emergency SOS",
                subtitle: "Dial $sos for immediate assistance",
                icon: Icons.sos_rounded,
                iconColor: const Color(0xFF9D4EDD),
                isDark: isDark,
                onTap: () => _showSimpleDialog(context, "Emergency", "Call $sos for Police, Fire, or Ambulance.", isDark),
              ),
              _ActionCard(
                title: "Local Hacks",
                subtitle: "Smart ways to save and explore",
                icon: Icons.lightbulb_outline_rounded,
                iconColor: const Color(0xFFFFB703),
                isDark: isDark,
                onTap: () => _showHacksSheet(context, hacks, isDark),
              ),
              _ActionCard(
                title: "Security & Scams",
                subtitle: "Avoid common tourist traps",
                icon: Icons.security_rounded,
                iconColor: const Color(0xFF06D6A0),
                isDark: isDark,
                onTap: () => _showScamsSheet(context, scams, isDark),
              ),

              const SizedBox(height: 36),

              if (logistics.isNotEmpty) ...[
                Text("Logistics Engine", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                _LogisticsCarousel(
                    logisticsData: logistics,
                    isDark: isDark,
                    accentColor: accentColor,
                    accentForeground: accentForeground,
                    onCardTap: (item) => _showLogisticsDetail(context, item, isDark)
                ),
              ]
            ],
          );
        },
      ),
    );
  }

  // --- Sheets & Dialogs ---
  void _showLogisticsDetail(BuildContext context, Map<String, dynamic> item, bool isDark) {
    IconData icon = Icons.info_outline_rounded; Color color = Colors.blue;
    if (item['type'] == 'alert') { icon = Icons.warning_amber_rounded; color = Colors.orange; }
    if (item['type'] == 'math') { icon = Icons.calculate_outlined; color = Colors.green; }
    if (item['type'] == 'position') { icon = Icons.train; color = Colors.purple; }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
        title: item['title'] ?? "Detail",
        icon: icon,
        color: color,
        isDark: isDark,
        children: [
          Text(item['subtitle'] ?? "", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16)
            ),
            child: Text(item['detail'] ?? "No details available.", style: TextStyle(fontSize: 16, height: 1.5, color: isDark ? Colors.white70 : Colors.black87)),
          ),
        ],
      ),
    );
  }

  void _showRedZoneSheet(BuildContext context, List laws, bool isDark) => showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => _DetailSheet(title: "Laws & Fines", icon: Icons.gavel_rounded, color: const Color(0xFFFF5A5F), isDark: isDark, children: [...laws.map((law) => _DetailRow(icon: "🚫", title: law['title'], desc: law['desc'], badge: "Fine: ${law['fine']}", isDark: isDark))]));
  void _showHacksSheet(BuildContext context, List hacks, bool isDark) => showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => _DetailSheet(title: "Local Hacks", icon: Icons.lightbulb_rounded, color: const Color(0xFFFFB703), isDark: isDark, children: [...hacks.map((hack) => _DetailRow(icon: "💡", title: "Tip", desc: hack, isDark: isDark))]));
  void _showScamsSheet(BuildContext context, List scams, bool isDark) => showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => _DetailSheet(title: "Common Scams", icon: Icons.security_rounded, color: const Color(0xFF06D6A0), isDark: isDark, children: [...scams.map((scam) => _DetailRow(icon: "⚠️", title: scam['title'], desc: scam['desc'], isDark: isDark))]));

  void _showSimpleDialog(BuildContext context, String title, String content, bool isDark) => showDialog(
      context: context,
      builder: (_) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          content: Text(content, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)))
          ]
      )
  );
}

// 🟢 FLUID HERO CARD
class _FluidHeroCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  final Color accentColor;
  const _FluidHeroCard({required this.data, required this.isDark, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor, // 🟢 FIXED: Fallback color matches theme
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))], // 🟢 FIXED: Dynamic glow
        image: const DecorationImage(
          image: NetworkImage("https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=1000"),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Keeping the dark overlay so the white text stays readable over the background image
            colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.8)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_twilight_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                // 🟢 THE FIX: Wrapped in Expanded to prevent right overflow!
                Expanded(
                  child: Text(
                    data['time']?.toString().toUpperCase() ?? "MAGIC MOMENT",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 11),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(data['title'] ?? "Hidden Gem", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Text(data['desc'] ?? "", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, height: 1.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// 🟢 ACTION STACK CARD
class _ActionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionCard({required this.title, required this.subtitle, required this.icon, required this.iconColor, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    shape: BoxShape.circle
                ),
                child: Icon(icon, color: iconColor, size: 22)
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.grey.shade600, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white24 : Colors.black12, size: 20)
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 🚀 LOGISTICS ENGINE
// ==========================================
class _LogisticsCarousel extends StatelessWidget {
  final List<dynamic> logisticsData;
  final bool isDark;
  final Color accentColor;
  final Color accentForeground;
  final Function(Map<String, dynamic>) onCardTap;

  const _LogisticsCarousel({required this.logisticsData, required this.isDark, required this.accentColor, required this.accentForeground, required this.onCardTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: logisticsData.length,
        itemBuilder: (context, index) {
          final item = logisticsData[index];
          final isAlert = item['type'] == 'alert';

          // 🟢 FIXED: Automatically switch text color based on if it's an alert card (Red) or theme card (Aqua/Navy)
          final contentColor = isAlert ? Colors.white : accentForeground;

          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => onCardTap(item),
              child: Container(
                width: 220,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isAlert
                        ? [const Color(0xFFE07A5F), const Color(0xFFD00000)]
                    // 🟢 FIXED: Matches the exact gradient styles from Explore Tab
                        : [accentColor, const Color(0xFF1BFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: (isAlert ? Colors.red : accentColor).withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: contentColor.withOpacity(0.2), shape: BoxShape.circle),
                      child: Icon(isAlert ? Icons.warning_rounded : Icons.insights_rounded, color: contentColor, size: 20),
                    ),
                    const Spacer(),
                    Text(item['title'] ?? "", style: TextStyle(color: contentColor, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text(item['subtitle'] ?? "", style: TextStyle(color: contentColor.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 🎨 SHEET COMPONENTS
// ==========================================
class _DetailSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isDark;
  final List<Widget> children;

  const _DetailSheet({required this.title, required this.icon, required this.color, required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32))
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SingleChildScrollView(
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
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                          child: Icon(icon, color: color, size: 24)
                      ),
                      const SizedBox(width: 16),
                      // 🟢 THE FIX: Wrapped in Expanded to prevent any crazy long titles from overflowing!
                      Expanded(
                          child: Text(
                            title,
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                      )
                    ]
                ),
                const SizedBox(height: 32),
                ...children
              ]
          )
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;
  final String? badge;
  final bool isDark;

  const _DetailRow({required this.icon, required this.title, required this.desc, this.badge, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                      const SizedBox(height: 6),
                      Text(desc, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade700, height: 1.5, fontSize: 14)),
                      if (badge != null)
                        Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(badge!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5))
                        )
                    ]
                )
            )
          ]
      ),
    );
  }
}