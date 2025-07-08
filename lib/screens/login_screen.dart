import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui'; // Import for ImageFilter
import '../main.dart'; // For LogoWithGlow

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  bool _logoVisible = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final userCredential = await AuthService().signInWithGoogle();
      // Store UID in SharedPreferences if login is successful
      if (userCredential != null &&
          userCredential.user != null &&
          userCredential.user!.uid.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('uid', userCredential.user!.uid);
      }
      if (userCredential != null && mounted) {
        // Success: Navigate to HomeScreen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        setState(() => _loading = false);
        debugPrint('Google sign-in failed: UID is null');
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign-in Failed'),
            content: const Text('Google sign-in failed. Please try again.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google sign-in failed. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e, stack) {
      setState(() => _loading = false);
      debugPrint('Sign-in error: $e');
      debugPrintStack(stackTrace: stack);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign-in Error'),
          content: Text('Sign-in error: ${e.toString()}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign-in error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Fade in the logo after build
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _logoVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black, // Use solid black, remove gradient
          ),
          // Centered logo
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  opacity: _logoVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeInOut,
                  child: const LogoWithGlow(
                    size: 140,
                    borderRadius: 32,
                    fadeIn: false, // Already handled by AnimatedOpacity
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'Describe. Design. Delight.',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // Google login button at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 48.h,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: _loading
                  ? Center(child: CircularProgressIndicator())
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(32.r), // rounder corners
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Blur background with a bit more white
                          BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              height: 52.h,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12), // a bit more white
                                borderRadius: BorderRadius.circular(32.r),
                                // Remove static border, handled by CustomPaint below
                              ),
                            ),
                          ),
                          // Animated gradient border (same as FullScreenPromptInputPage)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _AnimatedGradientBorderPainter(
                                animationValue: DateTime.now().millisecondsSinceEpoch / 6000 % 1,
                                borderRadius: 32.r,
                                borderWidth: 2.5.w,
                              ),
                            ),
                          ),
                          // Button
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, 52.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32.r),
                                side: BorderSide.none, // border handled by CustomPaint
                              ),
                              elevation: 0,
                              textStyle: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Image.asset(
                              'assets/images/google.png',
                              height: 32.h,
                            ),
                            onPressed: _signInWithGoogle,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// Add this class at the end of the file (outside any widget/class)
class _AnimatedGradientBorderPainter extends CustomPainter {
  final double animationValue;
  final double borderRadius;
  final double borderWidth;

  _AnimatedGradientBorderPainter({
    required this.animationValue,
    required this.borderRadius,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(borderWidth / 2),
      Radius.circular(borderRadius),
    );
    final gradient = SweepGradient(
      startAngle: 0.0,
      endAngle: 6.28319,
      colors: const [
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.yellow,
        Colors.red,
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(animationValue * 6.28319),
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _AnimatedGradientBorderPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}
