import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'trip_model.dart';
import 'trip_provider.dart';
import 'trip_style.dart';
import '../../services/unsplash_service.dart';

class CreateTripSheet extends ConsumerStatefulWidget {
  const CreateTripSheet({super.key});

  @override
  ConsumerState<CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends ConsumerState<CreateTripSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isCreating = false;

  DateTime? _startDate;
  DateTime? _endDate;
  TripStyle _selectedStyle = TripStyle.adventure;

  int get _durationDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  Future<void> _pickDate({
    required bool isStart,
  }) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        // 🟢 FIXED: The Date Picker now perfectly respects Dark Mode and your Aqua theme
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
        final accentForeground = isDark ? Colors.black : Colors.white;

        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
              primary: accentColor,
              onPrimary: accentForeground,
              onSurface: Colors.white,
            )
                : ColorScheme.light(
              primary: accentColor,
              onPrimary: accentForeground,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  bool get _isValid {
    return _titleController.text.trim().isNotEmpty &&
        _startDate != null &&
        _endDate != null &&
        _durationDays > 0;
  }

  Future<void> _createTrip() async {
    if (!_isValid) return;

    // 1. Show loading spinner
    setState(() => _isCreating = true);

    try {
      final tripTitle = _titleController.text.trim();

      // 2. THE AUTOMATED DESIGNER KICKS IN
      final badgeImageUrl = await UnsplashService.getPhotoUrl(tripTitle);
      final badgeSlogan = UnsplashService.generateSlogan(tripTitle);

      // 3. Build the Trip object
      final trip = Trip(
        id: const Uuid().v4(),
        title: tripTitle,
        description: _descriptionController.text.trim(),
        createdAt: DateTime.now(),
        startDate: _startDate!,
        endDate: _endDate!,
        durationDays: _durationDays,
        style: _selectedStyle,
        badgeImageUrl: badgeImageUrl,
        badgeSlogan: badgeSlogan,
      );

      // 4. Save using your existing Riverpod architecture
      ref.read(tripProvider.notifier).addTrip(trip);

      // 5. Close the sheet
      if (mounted) Navigator.pop(context);
    } catch (e) {
      print("Error creating trip: $e");
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // 🟢 FIXED: Passed in the dynamic accentColor to theme the inputs
  InputDecoration _buildInputDecoration(String label, IconData icon, bool isDark, Color accentColor) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, color: accentColor),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    // 🟢 DYNAMIC THEME COLORS
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12, // Reduced top padding to make room for drag handle
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            /// 🟢 Drag Handle
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            /// Header
            Text(
              'Design your journey ✨',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),

            /// Title
            TextField(
              controller: _titleController,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              textCapitalization: TextCapitalization.words,
              decoration: _buildInputDecoration('Trip Title (e.g. Paris Getaway)', Icons.flight_takeoff_rounded, isDark, accentColor),
            ),
            const SizedBox(height: 16),

            /// Description
            TextField(
              controller: _descriptionController,
              style: TextStyle(color: textColor),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: _buildInputDecoration('Brief Description (Optional)', Icons.description_outlined, isDark, accentColor),
            ),
            const SizedBox(height: 24),

            /// Dates Label
            Text(
              'When are you going?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.8)),
            ),
            const SizedBox(height: 12),

            /// 🟢 Custom Date Cards
            Row(
              children: [
                Expanded(child: _buildDateCard(true, isDark, accentColor)),
                const SizedBox(width: 12),
                Expanded(child: _buildDateCard(false, isDark, accentColor)),
              ],
            ),

            /// Duration Badge
            if (_durationDays > 0) ...[
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: accentColor),
                      const SizedBox(width: 8),
                      Text(
                        '$_durationDays Days Total',
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            /// Trip Style Picker
            DropdownButtonFormField<TripStyle>(
              value: _selectedStyle,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
              decoration: _buildInputDecoration('Vibe / Style', Icons.travel_explore_rounded, isDark, accentColor),
              items: TripStyle.values.map((style) {
                return DropdownMenuItem(
                  value: style,
                  child: Text(
                      style.name.toUpperCase(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor)
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedStyle = value);
                }
              },
            ),

            const SizedBox(height: 32),

            /// Actions
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 56,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_isValid && !_isCreating) ? _createTrip : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: accentForeground, // 🟢 FIXED: Contrast dynamically checks
                        disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      child: _isCreating
                          ? SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accentForeground) // 🟢 FIXED: Spinner contrast
                      )
                          : Text('Create Trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: accentForeground)),
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

  /// 🟢 Custom Widget for the Start/End Date Pickers
  Widget _buildDateCard(bool isStart, bool isDark, Color accentColor) {
    final date = isStart ? _startDate : _endDate;
    final hasDate = date != null;
    final String label = isStart ? 'Start Date' : 'End Date';
    final String dateText = hasDate ? "${date.day}/${date.month}/${date.year}" : 'Select';

    return GestureDetector(
      onTap: () => _pickDate(isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: hasDate ? accentColor.withOpacity(0.08) : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasDate ? accentColor.withOpacity(0.3) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isStart ? Icons.flight_takeoff_rounded : Icons.flight_land_rounded,
              color: hasDate ? accentColor : (isDark ? Colors.white54 : Colors.black54),
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dateText,
              style: TextStyle(
                fontSize: 14,
                color: hasDate ? accentColor : (isDark ? Colors.white : Colors.black),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}