import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:ui';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pixai/main.dart';
import 'package:pixai/widgets/blocked_words.dart';

class FullScreenPromptInputPage extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onGenerate;
  final bool isLoading;

  const FullScreenPromptInputPage({
    Key? key,
    required this.controller,
    required this.onGenerate,
    required this.isLoading,
  }) : super(key: key);

  // Overlay presentation method
  static Future<dynamic> show(
    BuildContext context, {
    required TextEditingController controller,
    required Future<String> Function(String prompt, {int width, int height}) onGenerateImage,
    required bool isLoading,
  }) async {
    return await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black38,
        pageBuilder: (_, __, ___) => FullScreenPromptInputPageInternal(
          controller: controller,
          onGenerateImage: onGenerateImage,
          isLoading: isLoading,
        ),
      ),
    );
  }

  @override
  State<FullScreenPromptInputPage> createState() => _FullScreenPromptInputPageState();
}

class _FullScreenPromptInputPageState extends State<FullScreenPromptInputPage> {
  @override
  Widget build(BuildContext context) {
    // This widget is not used, see FullScreenPromptInputPageInternal below
    return const SizedBox.shrink();
  }
}

// Internal stateful widget to handle image generation and display
class FullScreenPromptInputPageInternal extends StatefulWidget {
  final TextEditingController controller;
  final Future<String> Function(String prompt, {int width, int height}) onGenerateImage;
  final bool isLoading;

  const FullScreenPromptInputPageInternal({
    Key? key,
    required this.controller,
    required this.onGenerateImage,
    required this.isLoading,
  }) : super(key: key);

  @override
  State<FullScreenPromptInputPageInternal> createState() => _FullScreenPromptInputPageInternalState();
}

class _FullScreenPromptInputPageInternalState extends State<FullScreenPromptInputPageInternal> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _imageUrl;
  String? _currentPrompt;

  late final AnimationController _borderController;

  // Add these for loading animation and caching
  bool _showPreparing = false;
  DateTime? _loadingStartTime;
  ImageProvider? _cachedProvider;

  // Ratio selection state
  String _selectedRatio = '1:1';
  final List<String> _ratioOrder = ['1:1', '9:16', '16:9'];
  final Map<String, Size> _ratioMap = {
    '1:1': Size(512, 512),
    '9:16': Size(576, 1024),
    '16:9': Size(1024, 576),
  };

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _borderController.dispose();
    super.dispose();
  }

  // Optimize the blocked words check to be more efficient
  Future<void> _handleGenerate() async {
    final prompt = widget.controller.text.trim();
    if (prompt.isEmpty) return;

    // Only allow English prompts
    if (!_isEnglish(prompt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only English prompts are allowed.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Optimize blocked words check - use a more efficient approach
    final lowerPrompt = prompt.toLowerCase();
    bool isAdultContent = false;
    
    // Check for whole word matches using regex to avoid false positives
    for (final word in blockedWords) {
      // Create a regex that matches the word as a whole word
      final RegExp wordRegex = RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false);
      if (wordRegex.hasMatch(lowerPrompt)) {
        isAdultContent = true;
        break;
      }
    }
    
    if (isAdultContent) {
      await _incrementAdultAttempt();
      if (mounted) {
        Navigator.of(context).pop();
        // Show warning after closing the input page
        Future.delayed(const Duration(milliseconds: 300), () {
          final parentContext = Navigator.of(context).overlay?.context ?? context;
          ScaffoldMessenger.of(parentContext).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Adult content is not allowed. Further attempts may result in a ban.',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 4),
            ),
          );
        });
      }
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _imageUrl = null;
      _currentPrompt = prompt;
      _showPreparing = true;
      _loadingStartTime = DateTime.now();
      _cachedProvider = null;
    });

    // Start a timer for 20 seconds to show the preparing animation
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isLoading && _showPreparing) {
        setState(() {
          _showPreparing = false;
        });
      }
    });

    try {
      // Pass width and height based on selected ratio
      final size = _ratioMap[_selectedRatio]!;
      final url = await widget.onGenerateImage(
        prompt,
        width: size.width.toInt(),
        height: size.height.toInt(),
      );

      // Try to cache the image (like home page)
      final provider = CachedNetworkImageProvider(url);
      await precacheImage(provider, context);

      setState(() {
        _isLoading = false;
        _imageUrl = url;
        _showPreparing = false;
        _cachedProvider = provider;
      });
    } catch (e) {
      // If the error is for adult content, handle accordingly
      if (e is Exception && e.toString().contains('prohibited content')) {
        await _incrementAdultAttempt();
        if (mounted) {
          Navigator.of(context).pop();
          // Show warning after closing the input page
          Future.delayed(const Duration(milliseconds: 300), () {
            final parentContext = Navigator.of(context).overlay?.context ?? context;
            ScaffoldMessenger.of(parentContext).showSnackBar(
              const SnackBar(
                content: Text(
                  '⚠️ Adult content is not allowed. Further attempts may result in a ban.',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.redAccent,
                duration: Duration(seconds: 4),
              ),
            );
          });
        }
        return;
      }
      setState(() {
        _isLoading = false;
        _showPreparing = false;
      });
      // Optionally show a generic error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  // Helper to detect if text is English
  bool _isEnglish(String text) {
    final asciiCount = text.runes.where((r) => r < 128).length;
    return asciiCount / text.length > 0.8;
  }

  // Updated adult attempt counter with 10 attempts max and session tracking
  Future<void> _incrementAdultAttempt() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
        
        // Use a transaction to ensure atomic operations
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(userDoc);
          final userData = snapshot.data() ?? {};
          
          // Get current attempts count and last attempt timestamp
          final int currentAttempts = userData['adult_attempts'] ?? 0;
          final Timestamp? lastAttemptTime = userData['last_adult_attempt'];
          final bool isBlocked = userData['blocked'] == true;
          
          // Check if this is a new session (more than 1 hour since last attempt)
          final bool isNewSession = lastAttemptTime == null || 
              DateTime.now().difference(lastAttemptTime.toDate()).inHours > 1;
              
          // Only increment if it's a new session or first attempt
          if (isNewSession) {
            final int newAttempts = currentAttempts + 1;
            
            // Update the attempts count and timestamp
            transaction.set(userDoc, {
              'adult_attempts': newAttempts,
              'last_adult_attempt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            
            // If attempts reach 10 and user is not already blocked, block them
            if (newAttempts >= 10 && !isBlocked) {
              transaction.set(userDoc, {'blocked': true}, SetOptions(merge: true));
              
              // Show more severe blocking message
              if (mounted) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '⚠️ Account blocked due to multiple adult content violations.',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 6),
                    ),
                  );
                });
              }
            }
          }
        });
      }
    } catch (e) {
      // Log error but don't crash
      debugPrint('Error incrementing adult attempt: $e');
    }
  }

  void _handleSave() {
    if (_imageUrl != null && _currentPrompt != null) {
      Navigator.of(context).pop({
        'prompt': _currentPrompt,
        'imageUrl': _imageUrl,
        'heroTag': _imageUrl,
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  void _cycleRatio() {
    final currentIdx = _ratioOrder.indexOf(_selectedRatio);
    final nextIdx = (currentIdx + 1) % _ratioOrder.length;
    setState(() {
      _selectedRatio = _ratioOrder[nextIdx];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const SizedBox.shrink(),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          color: Colors.white,
          iconSize: 30.w,
          onPressed: () {
            widget.controller.clear();
            setState(() {
              _imageUrl = null;
              _currentPrompt = null;
            });
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            icon: IconTheme(
              data: IconThemeData(
                color: Colors.white,
                size: 28.w,
                weight: 800,
              ),
              child: const Icon(Icons.check),
            ),
            color: Colors.white,
            iconSize: 38.w,
            onPressed: (_imageUrl != null && !_isLoading)
                ? _handleSave
                : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Always show the blurred background
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Colors.black.withOpacity(0.72), // Increased opacity for a darker background
              ),
            ),
          ),
          // (No overlay during loading; keep background transparent)
          IgnorePointer(
            ignoring: false,
            child: Container(
              color: Colors.transparent,
              child: Column(
                children: [
                  const Spacer(),
                  Center(
                    child: Builder(
                      builder: (context) {
                        // Calculate card size based on selected ratio, max 260.w/h, but increase for 9:16 and 16:9
                        final ratioSize = _ratioMap[_selectedRatio]!;
                        double maxCardWidth = 300.w;
                        double maxCardHeight = 300.w;
                        // Adjust for 9:16 and 16:9
                        if (_selectedRatio == '9:16') {
                          maxCardHeight = 320.w; // taller for portrait
                          maxCardWidth = 270.w;
                        } else if (_selectedRatio == '16:9') {
                          maxCardWidth = 320.w; // wider for landscape
                          maxCardHeight = 320.w;
                        }
                        double width, height;
                        double aspect = ratioSize.width / ratioSize.height;
                        if (aspect >= 1) {
                          width = maxCardWidth;
                          height = maxCardWidth / aspect;
                          if (height > maxCardHeight) {
                            height = maxCardHeight;
                            width = maxCardHeight * aspect;
                          }
                        } else {
                          height = maxCardHeight;
                          width = maxCardHeight * aspect;
                          if (width > maxCardWidth) {
                            width = maxCardWidth;
                            height = maxCardWidth / aspect;
                          }
                        }
                        return SizedBox(
                          width: width,
                          height: height,
                          child: Card(
                            color: Colors.black.withOpacity(0.18),
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32.r), // Reduced from 48.r to 32.r
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Animated mesh gradient overlay while loading or preparing
                                if (_isLoading || _showPreparing)
                                  AnimatedMeshGradient(
                                    colors: [
                                      Colors.red,
                                      Colors.blue,
                                      Colors.green,
                                      Colors.yellow,
                                    ],
                                    options: AnimatedMeshGradientOptions(
                                      speed: 1.2,
                                      frequency: 1.0,
                                      amplitude: 1.0,
                                      grain: 0.1,
                                    ),
                                  ),
                                // Preparing animation for up to 20 seconds or until image loads
                                if (_showPreparing)
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 60.w,
                                          height: 60.w,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 4,
                                          ),
                                        ),
                                        SizedBox(height: 18.h),
                                        AutoSizeText(
                                          'Preparing image...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18.sp,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                // Show the image if loaded and cached
                                if (_imageUrl != null && !_showPreparing && _cachedProvider != null)
                                  Hero(
                                    tag: _imageUrl!,
                                    flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                                      return AnimatedBuilder(
                                        animation: animation,
                                        builder: (context, child) {
                                          final curved = CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeInOutCubicEmphasized,
                                          );
                                          return Opacity(
                                            opacity: 0.85 + 0.15 * curved.value,
                                            child: Transform.scale(
                                              scale: 0.98 + 0.02 * curved.value,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(32.r), // Reduced from 48.r to 32.r
                                          child: Image(
                                            image: _cachedProvider!,
                                            fit: BoxFit.cover,
                                            width: width,
                                            height: height,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Icon(Icons.broken_image, size: 70),
                                          ),
                                        ),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(32.r), // Reduced from 48.r to 32.r
                                      child: Image(
                                        image: _cachedProvider!,
                                        fit: BoxFit.cover,
                                        width: width,
                                        height: height,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.broken_image, size: 70),
                                      ),
                                    ),
                                  ),
                                // Show current ratio and logo if no image is loaded and not loading/preparing
                                if (_imageUrl == null && !_isLoading && !_showPreparing)
                                  Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(36.0.w),
                                      child: Image.asset(
                                        'assets/images/logo.png',
                                        width: width * 0.4,
                                        height: height * 0.4,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.all(24.w),
                    child: AnimatedBuilder(
                      animation: _borderController,
                      builder: (context, child) {
                        // The border painter and its container should NOT affect the input row size.
                        // Use a fixed width for the input row, independent of the selected ratio.
                        return Center(
                          child: SizedBox(
                            width: 420.w, // Fixed width for the input row
                            child: CustomPaint(
                              painter: _AnimatedGradientBorderPainter(
                                animationValue: _borderController.value,
                                borderRadius: 40.r,
                                borderWidth: 3.5.w,
                              ),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(32.r),
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                                          child: TextField(
                                            controller: widget.controller,
                                            autofocus: true,
                                            maxLines: 1,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16.sp,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'e.g. A futuristic city at sunset',
                                              hintStyle: TextStyle(color: Colors.white70, fontSize: 16.sp),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(32.r),
                                                borderSide: BorderSide.none,
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(32.r),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(32.r),
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w),
                                              fillColor: Colors.transparent,
                                              filled: true,
                                            ),
                                            onSubmitted: (_) => _handleGenerate(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    // Ratio cycle button styled like the send button, no icon, same colors
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(_isLoading || _showPreparing ? 0.08 : 0.18), // Dim when disabled
                                        shape: BoxShape.circle,
                                      ),
                                      child: ClipOval(
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(999),
                                              onTap: (_isLoading || _showPreparing) ? null : _cycleRatio, // Disable while loading
                                              child: Container(
                                                width: 44.w,
                                                height: 44.w,
                                                alignment: Alignment.center,
                                                child: Text(
                                                  _selectedRatio,
                                                  style: TextStyle(
                                                    color: _isLoading || _showPreparing ? Colors.white38 : Colors.white, // Dim text when disabled
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16.sp,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    // Send button card
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        shape: BoxShape.circle,
                                      ),
                                      child: ClipOval(
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: IconButton(
                                              icon: const Icon(Icons.arrow_upward),
                                              color: Colors.white,
                                              onPressed: _isLoading ? null : _handleGenerate,
                                              tooltip: 'Send',
                                              iconSize: 28.w,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
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
