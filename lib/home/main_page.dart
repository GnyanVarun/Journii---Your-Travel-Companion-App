import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/trips/trip_list_page.dart';
import '../profile/profile_page.dart';
import '../home/home_screen.dart';
import 'explore_tab.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _currentIndex = 0;

  // ===========================================================================
  // ANDROID BACKGROUND CHANNEL
  // ===========================================================================
  // Replaces the old `move_to_background` package.
  //
  // The corresponding native Android implementation is required in
  // MainActivity.kt.
  static const MethodChannel _appChannel = MethodChannel('journii/app');

  Future<void> _moveTaskToBackground() async {
    try {
      await _appChannel.invokeMethod('moveTaskToBack');
    } on PlatformException catch (e) {
      debugPrint(
        'Failed to move Journii to background: ${e.message}',
      );
    } on MissingPluginException catch (e) {
      debugPrint(
        'Background method is not available: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // =========================================================================
    // SYSTEM BACK GESTURE / BUTTON INTERCEPTION
    // =========================================================================
    //
    // Instead of closing the application, pressing Android Back while on the
    // MainPage sends the application to the background.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;

        // Send the application to the Android background without terminating
        // the application or destroying its current state.
        _moveTaskToBackground();
      },
      child: Scaffold(
        // Allows the screen content to flow behind the floating navigation bar.
        extendBody: true,

        body: IndexedStack(
          index: _currentIndex,
          children: const [
            HomePage(),
            ExploreTab(),
            TripListPage(),
            ProfilePage(),
          ],
        ),

        bottomNavigationBar: _buildFloatingNavBar(isDark),
      ),
    );
  }

  // ===========================================================================
  // FLOATING GLASSMORPHIC NAVIGATION BAR
  // ===========================================================================
  Widget _buildFloatingNavBar(bool isDark) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: 24,
          top: 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 15,
              sigmaY: 15,
            ),
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withOpacity(0.65)
                    : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.05),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      isDark ? 0.3 : 0.08,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildFluidNavItem(
                    0,
                    Icons.home_rounded,
                    Icons.home_outlined,
                    'Home',
                    isDark,
                  ),
                  _buildFluidNavItem(
                    1,
                    Icons.explore_rounded,
                    Icons.explore_outlined,
                    'Explore',
                    isDark,
                  ),
                  _buildFluidNavItem(
                    2,
                    Icons.luggage_rounded,
                    Icons.luggage_outlined,
                    'My Trips',
                    isDark,
                  ),
                  _buildFluidNavItem(
                    3,
                    Icons.account_circle_rounded,
                    Icons.account_circle_outlined,
                    'Profile',
                    isDark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FLUID EXPANSION NAVIGATION ITEMS
  // ===========================================================================
  Widget _buildFluidNavItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    bool isDark,
  ) {
    final isSelected = _currentIndex == index;

    // Explicitly sets Aqua for Dark Mode and Navy for Light Mode.
    final activeColor = isDark
        ? const Color(0xFF00E5FF)
        : const Color(0xFF2E3192);

    final inactiveColor = isDark
        ? Colors.white60
        : Colors.black45;

    return GestureDetector(
      onTap: () {
        // Haptic feedback for tactile response.
        HapticFeedback.lightImpact();

        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16.0 : 12.0,
          vertical: 12.0,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon pulse animation on selection.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 1.0,
                end: isSelected ? 1.15 : 1.0,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    isSelected ? activeIcon : inactiveIcon,
                    color: isSelected
                        ? activeColor
                        : inactiveColor,
                    size: 26,
                  ),
                );
              },
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.elasticOut,
              child: SizedBox(
                width: isSelected ? null : 0,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isSelected ? 8.0 : 0,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: activeColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

