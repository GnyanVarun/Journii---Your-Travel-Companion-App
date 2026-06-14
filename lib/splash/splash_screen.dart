import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
//import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ensure you import your main layout and auth screens correctly
import '../home/main_page.dart';
import '../auth/auth_screen.dart';
import '../main.dart'; // Import main.dart to access our background boot function

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flightPathAnimation;
  late Animation<double> _pinDropAnimation;
  late Animation<double> _textFadeAnimation;

  // State variables for the smart loading text
  bool _isFirstLaunch = false;
  String _loadingStatus = "";

  @override
  void initState() {
    super.initState();

    // Hides the status bar entirely for a true cinematic full-screen experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 🟢 REVERTED: Back to the full, graceful 3.2 second duration
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    // 1. The spark travels across the screen (0.0 to 0.4)
    _flightPathAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeInOutSine),
    );

    // 2. The Memory Pin drops and bounces into place (0.4 to 0.65)
    _pinDropAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 0.65, curve: Curves.elasticOut),
    );

    // 3. The "Journii" text fades in smoothly (0.65 to 1.0)
    _textFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.65, 1.0, curve: Curves.easeIn),
    );

    // Trigger the new smart multi-tasking boot
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirst = prefs.getBool('is_first_launch') ?? true;

    if (mounted) {
      setState(() {
        _isFirstLaunch = isFirst;
        _loadingStatus = isFirst
            ? "Preparing system & encrypting vault..."
            : "Syncing coordinates...";
      });
    }

    // 🟢 1. INSTANTLY DROP NATIVE SPLASH
    //FlutterNativeSplash.remove();

    if (isFirst) {
      await prefs.setBool('is_first_launch', false);
    }

    // 🟢 2. MULTI-TASKING MAGIC
    // The Future.wait ensures we DO NOT move forward until BOTH the full 3.2s animation
    // finishes AND the background databases finish loading.
    await Future.wait([
      _controller.forward(),
      initializeHeavySystems(),
    ]);

    // 🟢 3. THE GRACE PERIOD (Fixes the "hurried" feeling)
    // Adds a 600ms pause after everything is done so the final logo sits proudly
    // on the screen before the crossfade begins.
    await Future.delayed(const Duration(milliseconds: 600));

    // 🟢 4. NAVIGATE safely
    if (mounted) {
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    // Restores normal edge-to-edge system UI before leaving the splash screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final session = Supabase.instance.client.auth.currentSession;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        session != null ? const MainPage() : const AuthScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // --- Reused Premium Memory Pin Logo ---
  Widget _buildJourniiLogo() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Color(0xFF1BFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Icon(Icons.location_on_rounded, size: 84, color: Colors.white),
          ),
          const Positioned(
            top: 14,
            child: Icon(Icons.auto_awesome_rounded, size: 24, color: Color(0xFF2E3192)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // --- THE ANIMATED SEQUENCE ---
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Calculate the traveling spark's position along an arc
                final pathX = -size.width * 0.2 + (size.width * 0.7 * _flightPathAnimation.value);
                final pathY = size.height * 0.5 - math.sin(_flightPathAnimation.value * math.pi) * 100;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. THE TRAVELING SPARK
                    if (_flightPathAnimation.value > 0 && _flightPathAnimation.value < 1.0)
                      Positioned(
                        left: pathX,
                        top: pathY,
                        child: Opacity(
                          opacity: 1.0 - _pinDropAnimation.value, // Fades out as the pin drops
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.8),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                )
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 2. THE MEMORY PIN DROP
                    if (_pinDropAnimation.value > 0)
                      Positioned(
                        top: size.height * 0.5 - 120 + (40 * (1.0 - _pinDropAnimation.value)),
                        child: Transform.scale(
                          scale: _pinDropAnimation.value,
                          child: _buildJourniiLogo(),
                        ),
                      ),

                    // 3. THE TYPOGRAPHY FADE
                    if (_textFadeAnimation.value > 0)
                      Positioned(
                        top: size.height * 0.5 + 40,
                        child: Opacity(
                          opacity: _textFadeAnimation.value,
                          child: Column(
                            children: [
                              Text(
                                "Journii",
                                style: GoogleFonts.outfit(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "YOUR TRAVEL COMPANION",
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white70,
                                  letterSpacing: 3.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            // THE SMART STATUS TEXT
            Positioned(
              bottom: 48,
              child: AnimatedOpacity(
                // Fades out gracefully as the main text starts to appear
                opacity: _textFadeAnimation.value > 0 ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 400),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 2,
                        )
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _loadingStatus,
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 13,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}