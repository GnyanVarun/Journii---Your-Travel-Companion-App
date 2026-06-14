import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'dart:ui'; // For Glassmorphism

import 'ai_chat_notifier.dart';
import 'ai_chat_state.dart';
import 'chat_message_model.dart';
import 'ai_itinerary_model.dart';

// Database models
import 'itinerary_item_model.dart';
import 'itinerary_provider.dart';

class AIChatSheet extends ConsumerStatefulWidget {
  final String tripId;
  final String prompt; // This is the "Trigger Command" (Generate 5 days...)

  const AIChatSheet({
    super.key,
    required this.tripId,
    required this.prompt,
  });

  @override
  ConsumerState<AIChatSheet> createState() => _AIChatSheetState();
}

class _AIChatSheetState extends ConsumerState<AIChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (mounted) {
        final notifier = ref.read(aiChatProvider(widget.tripId).notifier);
        notifier.loadHistoryOrStart(widget.prompt);
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutQuart,
      );
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(aiChatProvider(widget.tripId).notifier).sendMessage(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiChatProvider(widget.tripId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF9F9FB);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 40)],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 🟢 PREMIUM MINIMAL HEADER
                _buildHeader(isDark, textColor, accentColor, accentForeground),

                // 🟢 EDITORIAL CHAT CANVAS
                Expanded(
                  child: state.messages.isEmpty && state.isLoading
                      ? _buildInitialLoading(isDark, accentColor)
                      : ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 120), // Extra bottom padding for floating input
                    itemCount: state.messages.length + (state.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.messages.length) {
                        return _buildTypingIndicator(isDark, accentColor);
                      }
                      return _buildMessageBubble(state.messages[index], isDark, accentColor, accentForeground);
                    },
                  ),
                ),
              ],
            ),

            // 🟢 FLOATING COMMAND PILL
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: _buildFloatingInput(state.isLoading, isDark, textColor, accentColor, accentForeground),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // 🎛️ UI COMPONENTS
  // --------------------------------------------------

  Widget _buildHeader(bool isDark, Color textColor, Color accentColor, Color accentForeground) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 48,
          height: 5,
          decoration: BoxDecoration(
            color: isDark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor, const Color(0xFF1BFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_rounded, color: accentForeground, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Journii Intelligence',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingInput(bool isLoading, bool isDark, Color textColor, Color accentColor, Color accentForeground) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E).withOpacity(0.8) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
                  onSubmitted: (_) => _handleSend(),
                  decoration: InputDecoration(
                    hintText: 'Adjust the itinerary...',
                    hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
              GestureDetector(
                onTap: isLoading ? null : _handleSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isLoading ? null : LinearGradient(
                      colors: [accentColor, const Color(0xFF1BFFFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    color: isLoading ? (isDark ? Colors.white24 : Colors.black12) : null,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_upward_rounded, color: isLoading ? (isDark ? Colors.white30 : Colors.black38) : accentForeground, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // 💬 MESSAGE BUBBLES (EDITORIAL STYLE)
  // --------------------------------------------------
  Widget _buildMessageBubble(ChatMessage msg, bool isDark, Color accentColor, Color accentForeground) {
    final isUser = msg.role == ChatRole.user;

    if (isUser) {
      // 🟢 USER COMMAND (Right-aligned, distinct pill)
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 24, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } else {
      // 🟢 AI RESPONSE (Editorial, full-width, seamless)
      return Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: accentColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.85),
                      fontSize: 16,
                      height: 1.6, // Taller line height for editorial feel
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (msg.hasItinerary)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: _buildTimeTable(msg.itineraryPlaces!, msg.text, isDark, accentColor, accentForeground),
              ),
          ],
        ),
      );
    }
  }

  // --------------------------------------------------
  // 🎟️ THE "BOARDING PASS" ITINERARY
  // --------------------------------------------------
  Widget _buildTimeTable(List<AIPlace> places, String summary, bool isDark, Color accentColor, Color accentForeground) {
    final Map<int, List<AIPlace>> byDay = {};
    for (var p in places) {
      byDay.putIfAbsent(p.day, () => []).add(p);
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 15))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🟢 TICKET HEADER (Gradient)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor, accentColor.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: isDark ? Colors.black.withOpacity(0.1) : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12)
                  ),
                  child: Icon(Icons.flight_takeoff_rounded, color: accentForeground, size: 24),
                ),
                const SizedBox(width: 16),
                Text(
                  "Curated Journey",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: accentForeground, letterSpacing: -0.5),
                ),
              ],
            ),
          ),

          // 🟢 VERTICAL TIMELINE
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: byDay.entries.map((entry) {
                final dayNum = entry.key;
                final dayPlaces = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Day Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          "DAY $dayNum",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontSize: 11,
                              letterSpacing: 1.5
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Places Timeline
                      Container(
                        margin: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: isDark ? Colors.white12 : Colors.black12, width: 2))
                        ),
                        child: Column(
                          children: dayPlaces.map((place) => Padding(
                            padding: const EdgeInsets.only(bottom: 20, left: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Timeline Node
                                Transform.translate(
                                  offset: const Offset(-21, 4),
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                      border: Border.all(color: accentColor, width: 2.5),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                // Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        place.name,
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isDark ? Colors.white : Colors.black87),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        place.description,
                                        style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54, height: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // 🟢 THE ACCEPT BUTTON
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    AIItineraryResponse(summary: summary, places: places),
                  );
                },
                icon: const Icon(Icons.check_circle_rounded, size: 22),
                label: const Text(
                    "Accept Itinerary",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: accentForeground, // 🟢 Contrasts automatically
                  elevation: 8,
                  shadowColor: accentColor.withOpacity(0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // ⏳ LOADING STATES
  // --------------------------------------------------
  Widget _buildInitialLoading(bool isDark, Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withOpacity(0.1), const Color(0xFF1BFFFF).withOpacity(0.1)],
              ),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(strokeWidth: 3, color: accentColor),
          ),
          const SizedBox(height: 24),
          Text(
            "Designing your perfect trip...",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            "Analyzing locations, logic, and travel times.",
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w500),
          )
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_rounded, color: accentColor.withOpacity(0.5), size: 20),
          const SizedBox(width: 12),
          Text(
              "Journii is thinking...",
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, fontSize: 15)
          ),
        ],
      ),
    );
  }
}