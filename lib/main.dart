import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_page.dart'; // <-- Add this import
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/auth_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:math'; // <-- Add this import

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestAllPermissions();
  await Firebase.initializeApp(options: firebaseOptions);

  // Ensure plugins are registered before runApp
  // This is needed for share_plus and other plugins to work after hot reload/restart
  // (No explicit call needed in most cases, but for hot reload issues, a full restart is required)

  runApp(const MyApp());
}

// Request all needed permissions at startup
Future<void> _requestAllPermissions() async {
  await [
    Permission.storage,
    Permission.manageExternalStorage, // Android 11+
  ].request();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // Adjust to your design's base size
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'PollinAI',
          // Show SplashScreen first, then navigate to MainScreen/LoginScreen
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            fontFamily: GoogleFonts.getFont('Roboto').fontFamily,
            textTheme: GoogleFonts.quicksandTextTheme(ThemeData(brightness: Brightness.dark).textTheme).apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            primaryTextTheme: GoogleFonts.quicksandTextTheme(ThemeData(brightness: Brightness.dark).textTheme).apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            scaffoldBackgroundColor: Colors.black,
            canvasColor: Colors.black,
            cardColor: Colors.black,
            dialogBackgroundColor: Colors.black,
            dividerColor: Colors.white24,
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.black,
              titleTextStyle: GoogleFonts.getFont(
                'Roboto',
                textStyle: Theme.of(context).textTheme.titleLarge,
                color: Colors.white,
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              elevation: 0,
            ),
            colorScheme: ColorScheme.fromSwatch(
              primarySwatch: Colors.blue,
              brightness: Brightness.dark,
              backgroundColor: Colors.black,
              cardColor: Colors.black,
              accentColor: Colors.blueAccent,
            ).copyWith(
              background: Colors.black,
              surface: Colors.black,
              onBackground: Colors.white,
              onSurface: Colors.white,
              secondary: Colors.blueAccent,
              onSecondary: Colors.white,
              primary: Colors.blue,
              onPrimary: Colors.white,
              error: Colors.redAccent,
              onError: Colors.white,
            ),
            // ...existing code...
          ), // <-- Move this brace up to close ThemeData
          routes: {
            '/login': (context) => const LoginScreen(), // <-- Add this line
            // ...other routes...
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static final List<Widget> _pages = <Widget>[
    HomeScreen(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Ensure main screen is totally black
      extendBody: true,
      body: _pages[_selectedIndex],
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  // For sequential image reveal
  final int _imageCount = 10;
  int _currentImage = 0;
  final List<Offset> _positions = [];
  bool _showLogo = false;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _startSequentialImages();
    // _handleStartup(); // Remove this line
  }

  void _startSequentialImages() async {
    final size = WidgetsBinding.instance.window.physicalSize /
        WidgetsBinding.instance.window.devicePixelRatio;
    final width = size.width;
    final height = size.height;

    // First 5 positions: 4 corners and center
    _positions.add(const Offset(20, 60)); // Top-left
    _positions.add(Offset(width - 84, 60)); // Top-right
    _positions.add(Offset(20, height - 124)); // Bottom-left
    _positions.add(Offset(width - 84, height - 124)); // Bottom-right
    _positions.add(Offset((width - 64) / 2, (height - 64) / 2)); // Center

    // Remaining positions: random
    for (int i = 5; i < _imageCount; i++) {
      final dx = _random.nextDouble() * (width - 80) + 20;
      final dy = _random.nextDouble() * (height - 180) + 60;
      _positions.add(Offset(dx, dy));
    }

    for (int i = 0; i < _imageCount; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      setState(() {
        _currentImage = i + 1;
      });
    }
    setState(() {
      _showLogo = true;
    });
    _controller.forward();

    // Wait for 3 seconds after logo appears, then navigate
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('user_uid') ?? prefs.getString('uid');
      if (uid != null && uid.startsWith('uid-')) {
        uid = uid.substring(4);
      }
      if (uid != null && uid.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final data = doc.data();
          final blocked = data?['blocked'] == true;
          final attempts = data?['adult_attempts'] ?? 0;
          if ((attempts is int && attempts >= 3) || blocked == true) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AccountBlockedScreen()),
            );
            return;
          }
        } catch (_) {
          // If error, fallback to HomeScreen
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    });
  }

  Future<void> _handleStartup() async {
    // Remove navigation logic from here, now handled after logo appears
    await Future.delayed(const Duration(milliseconds: 1800));
    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('user_uid') ?? prefs.getString('uid');
    // Remove 'uid-' prefix if present
    if (uid != null && uid.startsWith('uid-')) {
      uid = uid.substring(4);
    }
    if (mounted) {
      if (uid != null && uid.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final data = doc.data();
          final blocked = data?['blocked'] == true;
          final attempts = data?['adult_attempts'] ?? 0;

          // REMOVE: Do not set blocked=false if already true, and do not change true to false.
          // REMOVE: Do not set blocked=true here if already true, just check and show blocked screen.

          if ((attempts is int && attempts >= 3) || blocked == true) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AccountBlockedScreen()),
            );
            return;
          }
        } catch (_) {
          // If error, fallback to HomeScreen
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          // Images grid animation with improved fade/appear effect
          AnimatedOpacity(
            opacity: _showLogo ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 1400), // even slower fade out
            curve: Curves.easeInOut,
            child: Stack(
              children: [
                ...List.generate(_currentImage, (i) {
                  if (i >= 12) return const SizedBox.shrink();
                  final screenWidth = MediaQuery.of(context).size.width;
                  final screenHeight = MediaQuery.of(context).size.height;
                  final cols = 3;
                  final rows = 4;
                  final imgW = screenWidth / cols;
                  final imgH = screenHeight / rows;
                  final row = i ~/ cols;
                  final col = i % cols;
                  final left = col * imgW;
                  final top = row * imgH;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600), // slower appear
                    curve: Curves.easeInOutCubic,
                    builder: (context, value, child) {
                      final double safeOpacity = value.clamp(0.0, 1.0);
                      final Offset startOffset = Offset(
                        screenWidth / 2 - imgW / 2,
                        screenHeight / 2 - imgH / 2,
                      );
                      final Offset targetOffset = Offset(left, top);
                      final Offset animatedOffset = Offset(
                        startOffset.dx + (targetOffset.dx - startOffset.dx) * value,
                        startOffset.dy + (targetOffset.dy - startOffset.dy) * value,
                      );
                      final double scale = 0.2 + 0.8 * value;
                      if (i > _currentImage - 1) return const SizedBox.shrink();
                      return Positioned(
                        left: animatedOffset.dx,
                        top: animatedOffset.dy,
                        child: AnimatedOpacity(
                          opacity: safeOpacity,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeIn,
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8), // changed from 24 to 8
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8), // changed from 24 to 8
                                child: Image.asset(
                                  'assets/images/${(i % 12) + 1}.png',
                                  width: imgW + 2,
                                  height: imgH + 2,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
          // Logo appears after all images, with a smooth fade-in and scale
          if (_showLogo)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeInOut,
              child: Center(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                  ),
                  child: const LogoWithGlow(
                    size: 140,
                    borderRadius: 32,
                    fadeIn: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LogoScreen extends StatefulWidget {
  const LogoScreen({super.key});

  @override
  State<LogoScreen> createState() => _LogoScreenState();
}

class _LogoScreenState extends State<LogoScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Totally black
      body: Center(
        child: CustomPaint(
          size: const Size(200, 200),
          painter: LogoPainter(),
        ),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Example: Draw a simple circle as a placeholder for the logo
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      paint,
    );
    // Add more drawing logic here to match your actual logo
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Replace AccountDisabledScreen with AccountBlockedScreen ---
class AccountBlockedScreen extends StatelessWidget {
  const AccountBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Ensure status bar icons are visible (light content)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black, // Totally black
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, color: Colors.redAccent, size: 80),
                const SizedBox(height: 32),
                Text(
                  'Account Blocked',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Text(
                  'Your account has been blocked due to repeated attempts to generate adult content. If you believe this is a mistake, please contact support.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(180, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text('Close App'),
                  onPressed: () {
                    SystemNavigator.pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Add this reusable logo widget with glow ---
class LogoWithGlow extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool fadeIn;
  final Duration fadeDuration;

  const LogoWithGlow({
    Key? key,
    this.size = 140,
    this.borderRadius = 32,
    this.fadeIn = false,
    this.fadeDuration = const Duration(milliseconds: 1200),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget logo = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.45),
            blurRadius: 64,
            spreadRadius: 12,
            offset: Offset(0, 0),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          'assets/images/logo.png',
          height: size,
          width: size,
          fit: BoxFit.contain,
        ),
      ),
    );

    logo = Hero(
      tag: 'appLogo',
      transitionOnUserGestures: true,
      flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            // Use a curve for smoothness and slow down the animation
            final curvedValue = Curves.easeInOut.transform(animation.value);
            return Opacity(
              opacity: curvedValue,
              child: Transform.scale(
                scale: 0.95 + 0.05 * curvedValue, // subtle scale effect
                child: child,
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.45),
                  blurRadius: 64,
                  spreadRadius: 12,
                  offset: Offset(0, 0),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Image.asset(
                'assets/images/logo.png',
                height: size,
                width: size,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
      // Set a longer animation duration for the Hero transition
      // This is controlled by the closest MaterialPageRoute's transitionDuration,
      // but we can recommend to set it in the LoginScreen route if needed.
      child: logo,
    );

    if (fadeIn) {
      logo = AnimatedOpacity(
        opacity: 1.0,
        duration: fadeDuration,
        curve: Curves.easeInOut,
        child: logo,
      );
    }

    return logo;
  }
}
