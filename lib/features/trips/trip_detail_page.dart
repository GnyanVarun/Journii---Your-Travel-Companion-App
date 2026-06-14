import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journii/features/trips/route_preview_sheet.dart';
import 'package:journii/features/trips/trip_provider.dart';
import 'package:uuid/uuid.dart';
import '../../home/event_detail_page.dart';
import 'edit_trip_sheet.dart';
import 'trip_date_mapper.dart';
import 'package:latlong2/latlong.dart';

/// --------------------------------------------------
/// 🔌 SERVICES
/// --------------------------------------------------
import '../../services/geocoding_service.dart';

/// --------------------------------------------------
/// 🧠 MODELS
/// --------------------------------------------------
import 'trip_model.dart';
import 'itinerary_item_model.dart';
import 'place_idea_model.dart';
import 'ai_itinerary_model.dart';

/// --------------------------------------------------
/// 🧩 PROVIDERS
/// --------------------------------------------------
import 'itinerary_provider.dart';
import 'place_idea_provider.dart';
import 'navigation_provider.dart';

/// --------------------------------------------------
/// 🧱 UI / SHEETS
/// --------------------------------------------------
import 'ai_chat_sheet.dart';
import 'edit_place_idea_sheet.dart';
import 'itinerary_map_view.dart';
import '../../Intel/Trip_Intel_View.dart';
import '../../services/ai_travel_service.dart';

/// --------------------------------------------------
/// 🤖 AI + ENRICHMENT
/// --------------------------------------------------
import 'ai_prompt_builder.dart';
import 'visit_time_mapper.dart';
import 'geo_utils.dart';

/// --------------------------------------------------
/// 🔁 VIEW MODE
/// --------------------------------------------------
enum TripViewMode { list, map, intel }

/// ==================================================
/// 📄 TRIP DETAIL PAGE
/// ==================================================
class TripDetailPage extends ConsumerStatefulWidget {
  final Trip trip;
  final bool autoStartAI;

  const TripDetailPage({super.key, required this.trip, this.autoStartAI = false});

  @override
  ConsumerState<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends ConsumerState<TripDetailPage> {
  TripViewMode _viewMode = TripViewMode.list;
  String? _expandedItemId;
  bool _showTripInfo = false;

  OverlayEntry? _moveOverlayEntry;
  int? _hoveredDayIndex;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(itineraryProvider.notifier).syncFromCloud(widget.trip.id);
    });

    Future.microtask(() {
      ref.invalidate(savedEventsProvider(widget.trip.id));
    });

    if (widget.autoStartAI) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openAIChat(context);
      });
    }
  }

  /// ==================================================
  /// 🏗️ BUILD
  /// ==================================================
  @override
  Widget build(BuildContext context) {
    final itinerary = ref.watch(itineraryProvider).where((i) => i.tripId == widget.trip.id).toList();
    final placeIdeas = ref.watch(placeIdeaProvider).where((i) => i.tripId == widget.trip.id).toList();
    final trip = ref.watch(tripProvider).firstWhere((t) => t.id == widget.trip.id, orElse: () => widget.trip);

    final isPastTrip = _isPastTrip(trip);
    final hasItems = itinerary.isNotEmpty || placeIdeas.isNotEmpty;

    final Map<int, List<ItineraryItem>> grouped = {};
    for (final item in itinerary) {
      grouped.putIfAbsent(item.day, () => []).add(item);
    }
    final days = grouped.keys.toList()..sort();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F0);

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // 🟢 INLINE HERO HEADER
          _buildHeroHeader(trip, isPastTrip, isDark, accentColor),

          // 🟢 TIGHTER FLOATING TOGGLE
          _buildModernToggle(isDark, accentColor, accentForeground),

          // Body Content
          Expanded(
            child: _buildBodyContent(trip, grouped, days, placeIdeas, hasItems, isDark, accentColor, accentForeground),
          ),
        ],
      ),
      floatingActionButton: _buildFab(context, accentColor, accentForeground),
    );
  }

  // --------------------------------------------------
  // 🟢 INLINE HERO HEADER (MAXIMIZED VERTICAL SPACE)
  // --------------------------------------------------
  Widget _buildHeroHeader(Trip trip, bool isPastTrip, bool isDark, Color accentColor) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? Colors.white : Colors.black),
            ),
          ),
          const SizedBox(width: 16),

          // 🟢 TITLE & DATES INLINE
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trip.title,
                  style: TextStyle(
                    fontSize: 22, // Reduced to fit horizontally
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 12, color: accentColor.withOpacity(0.8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _formatTripDates(trip),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
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

          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                    Icons.edit_rounded,
                    size: 20,
                    color: isPastTrip
                        ? (isDark ? Colors.white30 : Colors.black26)
                        : (isDark ? Colors.white70 : Colors.black87)
                ),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: isPastTrip ? null : () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                    builder: (_) => EditTripSheet(trip: trip),
                  );
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () => _confirmDeleteTrip(context, trip),
              ),
            ],
          )
        ],
      ),
    );
  }

  // --------------------------------------------------
  // 🟢 FLOATING TOGGLE
  // --------------------------------------------------
  Widget _buildModernToggle(bool isDark, Color accentColor, Color accentForeground) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            _toggleBtn('Itinerary', Icons.list_alt_rounded, _viewMode == TripViewMode.list, () => setState(() => _viewMode = TripViewMode.list), isDark, accentColor, accentForeground),
            _toggleBtn('Map', Icons.map_rounded, _viewMode == TripViewMode.map, () {
              ref.read(navigationProvider.notifier).stopNavigation();
              setState(() => _viewMode = TripViewMode.map);
            }, isDark, accentColor, accentForeground),
            _toggleBtn('Intel', Icons.grid_view_rounded, _viewMode == TripViewMode.intel, () => setState(() => _viewMode = TripViewMode.intel), isDark, accentColor, accentForeground),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(String label, IconData icon, bool active, VoidCallback onTap, bool isDark, Color accentColor, Color accentForeground) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? accentForeground : (isDark ? Colors.white54 : Colors.black54)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: active ? accentForeground : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // 🔀 BODY CONTENT SWITCHER
  // --------------------------------------------------
  Widget _buildBodyContent(Trip trip, Map<int, List<ItineraryItem>> grouped, List<int> days, List<PlaceIdea> placeIdeas, bool hasItems, bool isDark, Color accentColor, Color accentForeground) {
    switch (_viewMode) {
      case TripViewMode.map:
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: ItineraryMapView(key: ValueKey(widget.trip.id), tripId: widget.trip.id),
        );
      case TripViewMode.intel:
        return TripIntelView(city: trip.destination ?? trip.title);
      case TripViewMode.list:
      default:
        return !hasItems
            ? _buildEmptyState(isDark, accentColor)
            : _buildListView(grouped, days, trip, placeIdeas, isDark, accentColor, accentForeground);
    }
  }

  // --------------------------------------------------
  // 📋 LIST VIEW (WITH TIMELINE UI)
  // --------------------------------------------------
  Widget _buildListView(Map<int, List<ItineraryItem>> grouped, List<int> days, Trip trip, List<PlaceIdea> placeIdeas, bool isDark, Color accentColor, Color accentForeground) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
      children: [
        _buildTripInfo(trip, isDark, accentColor),
        _buildPlaceIdeasList(placeIdeas, isDark),
        _buildSavedEventsSection(trip.id, isDark),

        if (days.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text('Your Schedule 🗓️', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
          ),
          ...days.map((day) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDayHeader(day, trip, isDark),
              Container(
                margin: const EdgeInsets.only(left: 12, top: 8, bottom: 24),
                decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: accentColor.withOpacity(0.2), width: 2))
                ),
                child: Column(
                  children: grouped[day]!.map((item) => _buildItineraryCard(item, isDark, accentColor, accentForeground)).toList(),
                ),
              ),
            ],
          )),
        ],
      ],
    );
  }

  // --------------------------------------------------
  // 🟢 SAVED EVENTS SECTION
  // --------------------------------------------------
  Widget _buildSavedEventsSection(String tripId, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardBorder = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Consumer(builder: (context, ref, _) {
      final savedEventsAsync = ref.watch(savedEventsProvider(tripId));

      return savedEventsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, stack) => const SizedBox.shrink(),
        data: (events) {
          if (events.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saved Events 🌟', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 16),
              ...events.map((e) => GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailPage(event: e['event_data'])));
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e['event_name'] ?? 'Saved Event', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: isDark ? Colors.white : Colors.black)),
                            const SizedBox(height: 4),
                            Text(e['event_date'] ?? '', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? Colors.white24 : Colors.black26),
                    ],
                  ),
                ),
              )),
              const SizedBox(height: 24),
            ],
          );
        },
      );
    });
  }

  // --------------------------------------------------
  // 🧠 ITINERARY CARD (SQUIRCLE UI)
  // --------------------------------------------------
  Widget _buildItineraryCard(ItineraryItem item, bool isDark, Color accentColor, Color accentForeground) {
    final isExpanded = _expandedItemId == item.id;
    final isSkipped = item.status == ItineraryStatus.skipped;
    final isCompleted = item.status == ItineraryStatus.completed;

    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardBorder = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Opacity(
      opacity: isCompleted ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(left: 20, bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cardBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(item, isExpanded, isSkipped, isCompleted, isDark, accentColor),
            const SizedBox(height: 8),
            Text(
              item.description,
              style: TextStyle(fontSize: 14, height: 1.5, color: isDark ? Colors.white70 : Colors.black87),
            ),
            _buildVisitTip(item, isDark),
            _buildFatigueSuggestion(item, accentColor),
            if (isExpanded && !isCompleted) _buildWorthItInline(item, isDark, accentColor, accentForeground),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(ItineraryItem item, bool isExpanded, bool isSkipped, bool isCompleted, bool isDark, Color accentColor) {
    return Row(
      children: [
        Expanded(
          child: Text(
            item.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              decorationColor: Colors.grey,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (!isCompleted) ...[
          IconButton(
            icon: Icon(Icons.alt_route_rounded, color: isDark ? Colors.white54 : Colors.blueGrey),
            tooltip: 'Preview route',
            onPressed: () {
              showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => RoutePreviewSheet(item: item));
            },
          ),
          IconButton(
            icon: Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.psychology_alt_rounded, color: accentColor),
            onPressed: () => setState(() => _expandedItemId = isExpanded ? null : item.id),
          ),
        ],
        if (isSkipped)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('⏸ Skipped', style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }

  Widget _buildVisitTip(ItineraryItem item, bool isDark) {
    if (item.visitTip == null || item.visitTip!.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.visitTip!,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.amber.shade200 : Colors.brown.shade800, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorthItInline(ItineraryItem item, bool isDark, Color accentColor, Color accentForeground) {
    final notifier = ref.read(itineraryProvider.notifier);
    final isSkipped = item.status == ItineraryStatus.skipped;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isSkipped)
            TextButton(
              onPressed: () {
                notifier.restoreItem(item.id);
                setState(() => _expandedItemId = item.id);
                ref.read(selectedDayProvider.notifier).state = item.day;
              },
              child: const Text('Restore', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (!isSkipped) ...[
            TextButton(
              onPressed: () {
                notifier.skipItem(item.id);
                setState(() => _expandedItemId = null);
              },
              child: Text('Skip', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.bold)),
            ),
            GestureDetector(
              onTap: () => _handleSingleTapMove(item),
              onLongPressStart: (details) => _handleMoveLongPressStart(details, item),
              onLongPressMoveUpdate: (details) => _handleMoveLongPressUpdate(details),
              onLongPressEnd: (details) => _handleMoveLongPressEnd(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text('Move', style: TextStyle(color: accentColor, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
          if (!isSkipped)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: accentForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                notifier.markCompleted(item.id);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final allItems = ref.read(itineraryProvider).where((i) => i.tripId == widget.trip.id).toList();
                  final nextItem = _findNextPlannedItem(current: item, allItems: allItems);
                  setState(() => _expandedItemId = nextItem?.id);
                  if (nextItem != null) ref.read(selectedDayProvider.notifier).state = nextItem.day;
                });
              },
              child: Text('Mark Done', style: TextStyle(fontWeight: FontWeight.bold, color: accentForeground)),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // 🧠 PLACE IDEAS & ABOUT SECTION
  // --------------------------------------------------
  Widget _buildPlaceIdeasList(List<PlaceIdea> ideas, bool isDark) {
    if (ideas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 12),
          child: Text('Brainstorm Board 🧠', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
        ),
        ...ideas.map((idea) => GestureDetector(
          onTap: () => _openEditSheet(context, idea),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(idea.name.isEmpty ? 'New Idea' : idea.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                      if (idea.notes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(idea.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
                      ]
                    ],
                  ),
                ),
                Icon(Icons.edit_rounded, size: 18, color: isDark ? Colors.white30 : Colors.black26),
              ],
            ),
          ),
        )),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTripInfo(Trip trip, bool isDark, Color accentColor) {
    if (!_showTripInfo) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24, top: 8),
        child: GestureDetector(
          onTap: () => setState(() => _showTripInfo = true),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: accentColor, size: 18),
              const SizedBox(width: 8),
              Text('Show trip details', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24, top: 8),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_rounded, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text('About this trip', style: TextStyle(fontWeight: FontWeight.w900, color: accentColor, fontSize: 16)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showTripInfo = false),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: accentColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(Icons.expand_less_rounded, color: accentColor, size: 18),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(trip.description, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.5, fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDayHeader(int day, Trip trip, bool isDark) {
    final date = TripDateMapper.dateForDay(trip: trip, day: day);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black87, borderRadius: BorderRadius.circular(20)),
            child: Text('Day $day${date != null ? ' • ${date.day}/${date.month}' : ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color accentColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: accentColor.withOpacity(0.05), shape: BoxShape.circle),
              child: Icon(Icons.map_outlined, size: 64, color: accentColor),
            ),
            const SizedBox(height: 24),
            Text('Blank Canvas', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Text('No itinerary yet. Tap the magic wand to let the AI build your perfect trip.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: isDark ? Colors.white60 : Colors.black54, height: 1.5)),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 👆 GESTURE LOGIC (UNCHANGED)
  // =========================================================
  void _handleSingleTapMove(ItineraryItem item) {
    final trip = ref.read(tripProvider).firstWhere((t) => t.id == widget.trip.id, orElse: () => widget.trip);
    final totalDays = trip.durationDays ?? 1;

    if (item.day >= totalDays) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This is the last day of the trip!"), behavior: SnackBarBehavior.floating));
      return;
    }

    final nextDay = item.day + 1;
    ref.read(itineraryProvider.notifier).moveItemToDay(itemId: item.id, newDay: nextDay);
    setState(() => _expandedItemId = null);
    ref.read(selectedDayProvider.notifier).state = nextDay;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Moved to Day $nextDay"), duration: const Duration(seconds: 1)));
  }

  void _handleMoveLongPressStart(LongPressStartDetails details, ItineraryItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    final trip = ref.read(tripProvider).firstWhere((t) => t.id == widget.trip.id, orElse: () => widget.trip);
    final totalDays = trip.durationDays ?? 1;
    _showLinkedInOverlay(context, details.globalPosition, totalDays, item.day, accentColor, accentForeground);
  }

  void _handleMoveLongPressUpdate(LongPressMoveUpdateDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    const padding = 24.0;
    final overlayWidth = screenWidth - (padding * 2);

    final trip = ref.read(tripProvider).firstWhere((t) => t.id == widget.trip.id, orElse: () => widget.trip);
    final totalDays = trip.durationDays ?? 1;
    final segmentWidth = overlayWidth / totalDays;

    final localDx = details.globalPosition.dx - padding;
    int hoveredIndex = (localDx / segmentWidth).floor() + 1;

    if (hoveredIndex < 1) hoveredIndex = 1;
    if (hoveredIndex > totalDays) hoveredIndex = totalDays;

    if (_hoveredDayIndex != hoveredIndex) {
      _hoveredDayIndex = hoveredIndex;
      _moveOverlayEntry?.markNeedsBuild();
    }
  }

  void _handleMoveLongPressEnd(ItineraryItem item) {
    if (_hoveredDayIndex != null && _hoveredDayIndex != item.day) {
      ref.read(itineraryProvider.notifier).moveItemToDay(itemId: item.id, newDay: _hoveredDayIndex!);
      setState(() => _expandedItemId = null);
      ref.read(selectedDayProvider.notifier).state = _hoveredDayIndex!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Moved to Day $_hoveredDayIndex"), duration: const Duration(milliseconds: 800)));
    }
    _removeMoveOverlay();
  }

  void _showLinkedInOverlay(BuildContext context, Offset touchPosition, int totalDays, int currentDay, Color accentColor, Color accentForeground) {
    _removeMoveOverlay();
    _hoveredDayIndex = currentDay;
    final overlayState = Overlay.of(context);
    final bool isCrowded = totalDays > 6;

    _moveOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: touchPosition.dy - 90,
          left: 24, right: 24,
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: 60,
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(totalDays, (index) {
                  final day = index + 1;
                  final isHovered = _hoveredDayIndex == day;
                  final isCurrent = currentDay == day;

                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutBack,
                      transform: isHovered ? Matrix4.diagonal3Values(isCrowded ? 1.1 : 1.2, isCrowded ? 1.1 : 1.2, 1.0) : Matrix4.identity(),
                      alignment: Alignment.center,
                      margin: EdgeInsets.symmetric(horizontal: isCrowded ? 1.0 : 2.0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: isHovered ? accentColor : Colors.transparent, borderRadius: BorderRadius.circular(20), border: isCurrent && !isHovered ? Border.all(color: Colors.white30, width: 1) : null),
                      child: Text(isCrowded ? '$day' : 'Day $day', maxLines: 1, style: TextStyle(color: isHovered ? accentForeground : Colors.white, fontWeight: isHovered ? FontWeight.bold : FontWeight.normal, fontSize: isHovered ? (isCrowded ? 14 : 14) : (isCrowded ? 11 : 12))),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
    overlayState.insert(_moveOverlayEntry!);
  }

  void _removeMoveOverlay() {
    _moveOverlayEntry?.remove();
    _moveOverlayEntry = null;
    _hoveredDayIndex = null;
  }

  // --------------------------------------------------
  // 🧠 FATIGUE SUGGESTION (UNCHANGED)
  // --------------------------------------------------
  Widget _buildFatigueSuggestion(ItineraryItem item, Color accentColor) {
    final trip = ref.read(tripProvider).firstWhere((t) => t.id == widget.trip.id, orElse: () => widget.trip);
    final allItems = ref.read(itineraryProvider).where((i) => i.tripId == widget.trip.id).toList();

    if (!_isDayFatiguing(day: item.day, allItems: allItems, trip: trip) || item.status != ItineraryStatus.planned) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💡 You’ve scheduled a lot today.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.orange.shade900)),
          const SizedBox(height: 4),
          Text('Move this to another day to avoid burnout?', style: TextStyle(fontSize: 13, color: Colors.orange.shade900)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _handleSingleTapMove(item),
              onLongPressStart: (d) => _handleMoveLongPressStart(d, item),
              onLongPressMoveUpdate: (d) => _handleMoveLongPressUpdate(d),
              onLongPressEnd: (d) => _handleMoveLongPressEnd(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: accentColor.withOpacity(0.3))),
                child: Text('Move', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ==================================================
  /// ➕ FAB (UNCHANGED)
  /// ==================================================
  Widget _buildFab(BuildContext context, Color accentColor, Color accentForeground) {
    if (_viewMode != TripViewMode.list) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'ai',
          backgroundColor: accentColor,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onPressed: () => _openAIChat(context),
          child: Icon(Icons.auto_awesome_rounded, color: accentForeground),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'add',
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onPressed: () => _addNewIdea(context),
          child: Icon(Icons.add_rounded, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
        ),
      ],
    );
  }

  void _addNewIdea(BuildContext context) {
    final idea = PlaceIdea(id: const Uuid().v4(), tripId: widget.trip.id, name: '', notes: '');
    _openEditSheet(context, idea);
  }

  void _openEditSheet(BuildContext context, PlaceIdea idea) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => EditPlaceIdeaSheet(idea: idea));
  }

  Future<void> _openAIChat(BuildContext context) async {
    final prompt = AIPromptBuilder.buildInitialPrompt(widget.trip);
    final result = await showModalBottomSheet<AIItineraryResponse>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => AIChatSheet(tripId: widget.trip.id, prompt: prompt));
    if (result == null) return;

    final notifier = ref.read(itineraryProvider.notifier);
    final newItems = result.places.map((p) {
      final cleanName = p.name.replaceAll(RegExp(r'\s*\(.*\)'), '').trim();
      final aiVisitTime = mapBestTime(p.bestTime);
      return ItineraryItem(id: const Uuid().v4(), tripId: widget.trip.id, day: p.day, title: cleanName, description: p.description, isAiGenerated: true, isLocked: false, status: ItineraryStatus.planned, latitude: null, longitude: null, visitTip: p.visitTip, preferredVisitTime: aiVisitTime);
    }).toList();

    await notifier.replaceUnlockedForTrip(tripId: widget.trip.id, newItems: newItems);

    print("🌍 STARTING GEOCODING for ${newItems.length} items...");
    String searchScope = widget.trip.destination ?? widget.trip.title;
    searchScope = searchScope.replaceAll(RegExp(r'(Trip|Tour|Vacation|Visit|Holiday|\d+)', caseSensitive: false), '').replaceAll(RegExp(r'[^\w\s]'), '').trim();

    LatLng? anchor;
    int successCount = 0;

    for (final item in newItems) {
      try {
        print("🔍 Searching for: ${item.title}...");
        LatLng? location = await _smartGeocode(item.title, searchScope);
        if (location == null) location = await _smartGeocode("${item.title} Landmark", searchScope);
        if (location == null) location = await _smartGeocode(item.title, "");
        if (location == null) continue;

        if (anchor == null) anchor = location;
        final distanceFromAnchor = distanceInKm(anchor.latitude, anchor.longitude, location.latitude, location.longitude);
        if (distanceFromAnchor > 2000) continue;

        successCount++;
        await notifier.updateItem(item.copyWith(latitude: location.latitude, longitude: location.longitude));
      } catch (e) {
        print("💥 ERROR processing ${item.title}: $e");
      }
    }
    print("🏁 GEOCODING COMPLETE. Successfully mapped $successCount / ${newItems.length} places.");
  }

  Future<LatLng?> _smartGeocode(String placeName, String cityContext) async {
    Future<LatLng?> search(String query) async {
      try {
        final res = await GeocodingService.geocode(query);
        if (res != null) return LatLng(res.latitude, res.longitude);
      } catch (_) {}
      return null;
    }
    var result = await search("$placeName, $cityContext");
    if (result != null) return result;
    final words = placeName.split(' ');
    if (words.length > 1) {
      result = await search("${words[0]}, $cityContext");
      if (result != null) return result;
      result = await search("${words[0]} ${words[1]}, $cityContext");
      if (result != null) return result;
    }
    final suffixes = ['Temple', 'Mandir', 'Fort', 'Ghat', 'Complex', 'Restaurant', 'Cafe', 'Street', 'Road', 'Museum', 'Park', 'Residency'];
    String strippedName = placeName;
    for (final suffix in suffixes) {
      if (strippedName.endsWith(suffix)) strippedName = strippedName.replaceAll(suffix, '').trim();
    }
    if (strippedName != placeName) {
      result = await search("$strippedName, $cityContext");
      if (result != null) return result;
    }
    result = await search(placeName);
    return result;
  }

  // --- Helpers ---
  List<DateTime> _tripDates(Trip trip) {
    if (trip.startDate == null || trip.durationDays == null) return [];
    return List.generate(trip.durationDays!, (index) => DateTime(trip.startDate!.year, trip.startDate!.month, trip.startDate!.day + index));
  }

  String _formatTripDates(Trip trip) {
    if (trip.startDate == null || trip.endDate == null) return 'Dates not set';
    final start = trip.startDate!;
    final end = trip.endDate!;
    final days = trip.durationDays ?? 0;
    String fmt(DateTime d) => '${d.day} ${_monthName(d.month)}';
    return '${fmt(start)} – ${fmt(end)} • $days days';
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Future<void> _confirmDeleteTrip(BuildContext context, Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Delete Trip', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to delete "${trip.title}"?\n\nThis will permanently remove the itinerary and saved places.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.white))),
          ],
        );
      },
    );
    if (confirmed == true) _deleteTrip(context, trip);
  }

  void _deleteTrip(BuildContext context, Trip trip) {
    ref.read(itineraryProvider.notifier).deleteForTrip(trip.id);
    ref.read(placeIdeaProvider.notifier).deleteForTrip(trip.id);
    ref.read(tripProvider.notifier).deleteTrip(trip.id);
    Navigator.of(context).pop();
  }

  bool _isPastTrip(Trip trip) {
    if (trip.endDate == null) return false;
    final today = DateTime.now();
    return DateTime(trip.endDate!.year, trip.endDate!.month, trip.endDate!.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  ItineraryItem? _findNextPlannedItem({required ItineraryItem current, required List<ItineraryItem> allItems}) {
    final sameDay = allItems.where((i) => i.day == current.day && i.status == ItineraryStatus.planned).toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final item in sameDay) {
      if (item.id != current.id) return item;
    }
    final future = allItems.where((i) => i.day > current.day && i.status == ItineraryStatus.planned).toList()..sort((a, b) => a.day.compareTo(b.day));
    return future.isNotEmpty ? future.first : null;
  }

  bool _isDayFatiguing({required int day, required List<ItineraryItem> allItems, required Trip trip}) {
    if (trip.startDate == null) return false;
    final itemDate = trip.startDate!.add(Duration(days: day - 1));
    final now = DateTime.now();
    final isToday = itemDate.year == now.year && itemDate.month == now.month && itemDate.day == now.day;
    if (!isToday) return false;
    final completedToday = allItems.where((i) => i.day == day && i.status == ItineraryStatus.completed).length;
    final currentHour = now.hour;
    return completedToday >= 3 || currentHour >= 23;
  }

  int? _nextAvailableDay({required int currentDay, required Trip trip}) {
    final totalDays = trip.durationDays;
    if (totalDays == null) return null;
    final nextDay = currentDay + 1;
    if (nextDay > totalDays) return null;
    return nextDay;
  }
}