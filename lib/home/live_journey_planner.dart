import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/unsplash_service.dart';
import '../features/trips/trip_model.dart';
import '../features/trips/trip_provider.dart';
import '../features/trips/trip_detail_page.dart';

// 🟢 NEW: Import your home screen so we can access the ImageUrlCache!
// (Adjust this path if your home_screen.dart is in a different folder)
import 'home_screen.dart';

class LiveJourneyPlanner extends ConsumerStatefulWidget {
  final String destination;

  const LiveJourneyPlanner({super.key, required this.destination});

  @override
  ConsumerState<LiveJourneyPlanner> createState() => _LiveJourneyPlannerState();
}

class _LiveJourneyPlannerState extends ConsumerState<LiveJourneyPlanner> {
  final TextEditingController _promptController = TextEditingController();
  int _selectedDays = 3;
  late String _dynamicHint;

  bool _isGenerating = false;
  DateTime _startDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dynamicHint = _generateRandomHint(widget.destination);
  }

  String _generateRandomHint(String dest) {
    final city = dest == "Anywhere" ? "the mountains" : dest;

    final List<String> prompts = [
      "E.g., A relaxing weekend in $city focusing on cozy cafes and hidden art galleries.",
      "E.g., I want an action-packed itinerary exploring the best street food in $city.",
      "E.g., Keep it chill. Just looking for scenic views and peaceful nature spots near $city.",
      "E.g., A romantic getaway in $city with fine dining and historic landmarks.",
      "E.g., Show me the vibrant local markets and underground nightlife in $city.",
      "E.g., A budget-friendly backpacking trip through $city prioritizing local experiences.",
      "E.g., Luxury and comfort. Best spas and high-end shopping in $city."
    ];

    final random = Random();
    return prompts[random.nextInt(prompts.length)];
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF1C1C1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _handleGenerateTrip() async {
    FocusScope.of(context).unfocus();
    setState(() => _isGenerating = true);

    try {
      final promptText = _promptController.text.trim();
      final finalDescription = promptText.isNotEmpty
          ? promptText
          : "Show me the highlights and best experiences in ${widget.destination}.";

      final newTrip = Trip(
        id: const Uuid().v4(),
        title: "${widget.destination} trip",
        description: finalDescription,
        destination: widget.destination,
        createdAt: DateTime.now(),
        startDate: _startDate,
        endDate: _startDate.add(Duration(days: _selectedDays)),
        durationDays: _selectedDays,
      );

      await ref.read(tripProvider.notifier).addTrip(newTrip);

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripDetailPage(
              trip: newTrip,
              autoStartAI: true,
            ),
          ),
        );
      }

    } catch (e) {
      print("Error creating trip: $e");
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 UNIFIED QUERY: Exactly matches the string from the Home Screen cache!
    final String query = "${widget.destination} travel";

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. CINEMATIC BACKGROUND
          Positioned.fill(
            child: FutureBuilder<String?>(
              initialData: ImageUrlCache.getSync(query),
              future: ImageUrlCache.getAsync(query),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.network(snapshot.data!, fit: BoxFit.cover);
                }
                return Container(color: Colors.grey.shade900);
              },
            ),
          ),

          // 2. GRADIENT OVERLAY
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.95),
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.8)
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // 3. UI CONTENT
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 🟢 GLASSMORPHIC BACK BUTTON
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ),

                            const Spacer(),

                            // 🟢 PREMIUM BADGE
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_rounded, color: Colors.white, size: 12),
                                      const SizedBox(width: 6),
                                      const Text(
                                        "DESTINATION SECURED",
                                        style: TextStyle(color: Colors.white, letterSpacing: 1.5, fontSize: 10, fontWeight: FontWeight.w900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 🟢 SHADOWED TITLE (Always readable)
                            Text(
                              widget.destination,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 52,
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
                                  letterSpacing: -1.5,
                                  shadows: [
                                    Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
                                  ]
                              ),
                            ),
                            const SizedBox(height: 32),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Duration: $_selectedDays Days", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),

                                // 🟢 GLASSMORPHIC CALENDAR BUTTON
                                GestureDetector(
                                  onTap: () => _pickStartDate(context),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white30),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 14),
                                            const SizedBox(width: 8),
                                            Text(
                                                _startDate.day == DateTime.now().day && _startDate.month == DateTime.now().month
                                                    ? "Starts Today"
                                                    : "Starts ${_formatDate(_startDate)}",
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white.withOpacity(0.2),
                                thumbColor: Colors.white,
                                overlayColor: Colors.white.withOpacity(0.1),
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                              ),
                              child: Slider(
                                value: _selectedDays.toDouble(),
                                min: 1,
                                max: 14,
                                divisions: 13,
                                onChanged: (val) => setState(() => _selectedDays = val.toInt()),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 🟢 GLASSMORPHIC AI PROMPT INPUT
                            ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                                          SizedBox(width: 12),
                                          Text("Shape your journey", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _promptController,
                                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          hintText: _dynamicHint,
                                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14, height: 1.4),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // 🟢 PREMIUM GENERATE BUTTON
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: _isGenerating ? null : _handleGenerateTrip,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                ),
                                icon: _isGenerating
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                    : const Icon(Icons.flight_takeoff_rounded, size: 20),
                                label: Text(
                                    _isGenerating ? "Crafting Magic..." : "Generate Itinerary",
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}