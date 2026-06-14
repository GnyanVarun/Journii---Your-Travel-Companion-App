import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:journii/profile/collection_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/hype_notification_service.dart';
import '../main.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();

  bool _isLoading = false;
  bool _isUploadingImage = false;

  String _displayName = "";
  String? _avatarUrl;

  // Settings State
  bool _notificationsEnabled = true;
  bool? _tempDarkMode; // 🟢 NEW: Local state for smooth switch animation

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final meta = user.userMetadata;
      if (meta != null) {
        final savedName = meta['username'] ?? meta['display_name'] ?? meta['name'] ?? '';

        if (savedName.toString().isNotEmpty) {
          setState(() {
            _nameController.text = savedName.toString();
            _displayName = savedName.toString();
          });
        }

        final savedAvatar = meta['avatar_url'] as String?;
        if (savedAvatar != null && savedAvatar.isNotEmpty) {
          setState(() {
            _avatarUrl = savedAvatar;
          });
        }
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);

    if (pickedFile == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final bytes = await pickedFile.readAsBytes();
      final fileExtension = pickedFile.path.split('.').last;
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = '${user.id}/$fileName';

      await _supabase.storage.from('avatars').uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl = _supabase.storage.from('avatars').getPublicUrl(filePath);

      await _supabase.auth.updateUser(
        UserAttributes(data: {'avatar_url': publicUrl}),
      );

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
        final accentForeground = isDark ? Colors.black : Colors.white;

        setState(() { _avatarUrl = publicUrl; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile picture updated!', style: TextStyle(fontWeight: FontWeight.bold, color: accentForeground)),
            backgroundColor: accentColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _updateProfile() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final newName = _nameController.text.trim();

      await _supabase.auth.updateUser(
        UserAttributes(data: {
          'username': newName,
          'display_name': newName,
          'name': newName,
        }),
      );

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
        final accentForeground = isDark ? Colors.black : Colors.white;

        setState(() { _displayName = newName; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: accentForeground),
                const SizedBox(width: 12),
                Expanded(child: Text('Profile updated successfully!', style: TextStyle(fontWeight: FontWeight.bold, color: accentForeground))),
              ],
            ),
            backgroundColor: accentColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await HypeNotificationService.cancelAll();
    await _supabase.auth.signOut();
  }

  Future<void> _executeAccountDeletion() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );

      await _supabase.rpc('delete_user_account');
      await _supabase.auth.signOut(scope: SignOutScope.local);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
      }

    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showDeleteAccountDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text("Delete Account?", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "This action cannot be undone. All of your saved trips, memories, and data will be permanently erased.",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _executeAccountDeletion();
            },
            child: const Text("Permanently Delete", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? 'Guest';
    final fallbackName = email.split('@')[0];
    final displayGreeting = _displayName.isNotEmpty ? _displayName : fallbackName;

    final themeMode = ref.watch(themeProvider);
    final isSystemDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final globalIsDark = themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && isSystemDark);

    // 🟢 FIXED: Use temp local state if it exists to allow the switch to glide freely
    final isDark = _tempDarkMode ?? globalIsDark;

    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF9F9FB);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtitleColor = isDark ? Colors.white60 : Colors.grey.shade600;
    final borderColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.05);

    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
    final accentForeground = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          children: [
            // --- 1. HEADER & AVATAR ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Profile", style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
                      const SizedBox(height: 6),
                      Text(displayGreeting, style: TextStyle(color: textColor, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _isUploadingImage ? null : _pickAndUploadImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 2)
                        ),
                        child: CircleAvatar(
                          radius: 38,
                          backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
                          backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                          child: _isUploadingImage
                              ? CircularProgressIndicator(color: accentColor)
                              : (_avatarUrl == null ? Icon(Icons.person_rounded, size: 40, color: isDark ? Colors.white30 : Colors.black38) : null),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [accentColor, const Color(0xFF1BFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            shape: BoxShape.circle,
                            border: Border.all(color: bgColor, width: 3)
                        ),
                        child: Icon(Icons.edit_rounded, color: accentForeground, size: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // --- 2. TRAVEL DEX BANNER ---
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CollectionPage())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(colors: [accentColor, const Color(0xFF1BFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: accentForeground.withOpacity(0.2), shape: BoxShape.circle),
                        child: Icon(Icons.auto_awesome_mosaic_rounded, color: accentForeground, size: 28)
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("My Travel Dex", style: TextStyle(color: accentForeground, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          const SizedBox(height: 4),
                          Text("View your saved memories & pins", style: TextStyle(color: accentForeground.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: accentForeground.withOpacity(0.2), shape: BoxShape.circle),
                      child: Icon(Icons.arrow_forward_ios_rounded, color: accentForeground, size: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // --- 3. ACCOUNT DETAILS ---
            Text("ACCOUNT DETAILS", style: TextStyle(color: subtitleColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: borderColor),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Row(
                      children: [
                        Icon(Icons.email_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 22),
                        const SizedBox(width: 16),
                        Text("Email", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 16),
                        Expanded(child: Text(email, style: TextStyle(color: subtitleColor, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade100, indent: 60),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.badge_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 22),
                        const SizedBox(width: 16),
                        Text("Name", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            textAlign: TextAlign.right,
                            style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                                hintText: "Enter name",
                                hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black26),
                                border: InputBorder.none,
                                isDense: true
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_rounded, color: isDark ? Colors.white24 : Colors.black26, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: accentForeground,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
                ),
                child: _isLoading
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: accentForeground, strokeWidth: 2))
                    : Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: accentForeground)),
              ),
            ),
            const SizedBox(height: 48),

            // --- 4. PREFERENCES ---
            Text("PREFERENCES", style: TextStyle(color: subtitleColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  // Dark Mode Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.dark_mode_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 22),
                        const SizedBox(width: 16),
                        Text("Dark Mode", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Switch(
                          value: isDark,
                          activeColor: accentColor,
                          onChanged: (val) {
                            // 🟢 FIXED: Update local state instantly so the switch glides freely
                            setState(() => _tempDarkMode = val);

                            // Defer the heavy global app rebuild by 250ms so the animation completes smoothly
                            Future.delayed(const Duration(milliseconds: 250), () {
                              ref.read(themeProvider.notifier).toggleTheme(val);
                              if (mounted) setState(() => _tempDarkMode = null);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade100, indent: 60),

                  // Notifications Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 22),
                        const SizedBox(width: 16),
                        Text("Push Notifications", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Switch(
                          value: _notificationsEnabled,
                          activeColor: accentColor,
                          onChanged: (val) async {
                            setState(() => _notificationsEnabled = val);

                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('notifications_enabled', val);

                            if (val == false) {
                              await HypeNotificationService.cancelAll();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text("All future trip alerts cancelled.", style: TextStyle(fontWeight: FontWeight.bold)),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                );
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text("Syncing trip alerts...", style: TextStyle(fontWeight: FontWeight.bold)),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                );
                              }

                              try {
                                final now = DateTime.now().toIso8601String();
                                final upcomingTrips = await _supabase
                                    .from('trips')
                                    .select('*')
                                    .gte('start_date', now);

                                for (var trip in upcomingTrips) {
                                  final rawId = trip['id'];
                                  final safeNotificationId = rawId is int
                                      ? rawId
                                      : rawId.toString().hashCode;

                                  await HypeNotificationService.scheduleTripNotifications(
                                    tripId: safeNotificationId,
                                    destination: trip['destination'] ?? 'your destination',
                                    startDate: DateTime.parse(trip['start_date']),
                                    endDate: DateTime.parse(trip['end_date']),
                                  );
                                }

                                if (mounted) {
                                  final isDark = Theme.of(context).brightness == Brightness.dark;
                                  final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
                                  final accentForeground = isDark ? Colors.black : Colors.white;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Trip alerts enabled and synced!", style: TextStyle(fontWeight: FontWeight.bold, color: accentForeground)),
                                      backgroundColor: accentColor,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  );
                                }
                              } catch (e) {
                                print("Error syncing trips: $e");
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // --- 5. DANGER ZONE ---
            Text("DANGER ZONE", style: TextStyle(color: isDark ? Colors.redAccent.withOpacity(0.8) : Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.redAccent.withOpacity(0.05) : Colors.red.shade50,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: isDark ? Colors.redAccent.withOpacity(0.15) : Colors.red.shade100),
              ),
              child: Column(
                children: [
                  // Sign Out
                  InkWell(
                    onTap: _signOut,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 22),
                          const SizedBox(width: 16),
                          Text("Sign Out", style: TextStyle(color: Colors.red.shade400, fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: isDark ? Colors.redAccent.withOpacity(0.1) : Colors.red.shade100, indent: 60),

                  // Delete Account
                  InkWell(
                    onTap: () => _showDeleteAccountDialog(isDark), // Pass isDark explicitly
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Row(
                        children: [
                          Icon(Icons.person_remove_rounded, color: Colors.red.shade400, size: 22),
                          const SizedBox(width: 16),
                          Text("Delete Account", style: TextStyle(color: Colors.red.shade400, fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}