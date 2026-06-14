import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'place_idea_model.dart';
import 'place_idea_provider.dart';

class EditPlaceIdeaSheet extends ConsumerStatefulWidget {
  final PlaceIdea idea;

  const EditPlaceIdeaSheet({super.key, required this.idea});

  @override
  ConsumerState<EditPlaceIdeaSheet> createState() =>
      _EditPlaceIdeaSheetState();
}

class _EditPlaceIdeaSheetState extends ConsumerState<EditPlaceIdeaSheet> {
  late TextEditingController nameController;
  late TextEditingController notesController;
  late int priority;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.idea.name);
    notesController = TextEditingController(text: widget.idea.notes);
    priority = widget.idea.priority;
  }

  @override
  void dispose() {
    nameController.dispose();
    notesController.dispose();
    super.dispose();
  }

  // 🟢 Helper for Premium Input Styling
  InputDecoration _buildInputDecoration(String label, IconData icon, bool isDark, Color accentColor) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: accentColor), // 🟢 FIXED: Follows dynamic theme logic
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: accentColor, width: 2), // 🟢 FIXED: Border matches theme
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    );
  }

  String _priorityLabel(int value) {
    switch (value) {
      case 1: return 'Optional';
      case 2: return 'Nice to have';
      case 3: return 'Important';
      case 4: return 'Very Important';
      case 5: return 'Must See';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 DYNAMIC THEME COLORS: Replaces the hardcoded purple
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Container(
      // 🟢 FIXED: Gave the sheet a solid background color and rounded corners
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🟢 Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            /// Header
            Row(
              children: [
                Text(
                  widget.idea.name.isEmpty ? 'Add New Place' : 'Edit Place',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.push_pin_rounded, color: Colors.amber, size: 24),
              ],
            ),
            const SizedBox(height: 28),

            /// Inputs
            TextField(
              controller: nameController,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              textCapitalization: TextCapitalization.words,
              decoration: _buildInputDecoration('Place name (e.g. Louvre Museum)', Icons.place_rounded, isDark, accentColor),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: notesController,
              style: TextStyle(color: textColor),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: _buildInputDecoration('Why this place? (Optional notes)', Icons.notes_rounded, isDark, accentColor),
            ),
            const SizedBox(height: 32),

            /// 🟢 PREMIUM SLIDER DASHBOARD
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star_rounded, color: accentColor),
                      const SizedBox(width: 8),
                      Text("Importance", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textColor)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _priorityLabel(priority),
                          style: TextStyle(color: accentColor, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accentColor,
                      inactiveTrackColor: accentColor.withOpacity(0.2),
                      thumbColor: accentColor,
                      trackHeight: 6.0,
                      tickMarkShape: const RoundSliderTickMarkShape(),
                      activeTickMarkColor: accentForeground, // 🟢 FIXED: Ensures contrast against Aqua/Navy track
                      inactiveTickMarkColor: accentColor.withOpacity(0.5),
                    ),
                    child: Slider(
                      value: priority.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      onChanged: (value) {
                        setState(() => priority = value.toInt());
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            /// Save Button
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        final notes = notesController.text.trim();
                        if (name.isEmpty) return;

                        ref.read(placeIdeaProvider.notifier).addOrUpdateIdea(
                          widget.idea.copyWith(
                            name: name,
                            notes: notes,
                            priority: priority,
                          ),
                        );

                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: accentForeground, // 🟢 FIXED: Text contrasts dynamically
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      child: Text('Save Idea', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: accentForeground)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}