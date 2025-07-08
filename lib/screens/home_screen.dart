import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:pixai/widgets/full_screen_prompt_input_page.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import '../services/pix_service.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/generated_image.dart';
import '../services/generated_image_db_service.dart';
import '../widgets/prompt_input_card.dart';
import 'dart:ui';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../widgets/custom_app_bar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/home_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/download_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeBloc(GeneratedImageDbService())..add(LoadImagesEvent()),
      child: const HomeScreenView(),
    );
  }
}

class HomeScreenView extends StatefulWidget {
  const HomeScreenView({super.key});

  @override
  State<HomeScreenView> createState() => _HomeScreenViewState();
}

class _HomeScreenViewState extends State<HomeScreenView> with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _promptController = TextEditingController();
  final PixService _pixService = PixService();

  // Animation controllers
  late AnimationController _skeletonController;
  late AnimationController _imagesController;
  late Animation<double> _skeletonFadeAnimation;
  late Animation<double> _imagesFadeAnimation;

  // Track fade-in for each image
  List<bool> _imageVisible = [];
  List<AnimationController> _imageAnimationControllers = [];
  List<Animation<double>> _imageAnimations = [];

  String? uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _loadUidFromPrefs();

    // Only load images once when the widget is first created
    context.read<HomeBloc>().add(LoadImagesEvent());
  }

  Future<void> _loadUidFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      uid = prefs.getString('uid');
    });
  }

  void _initializeAnimations() {
    // Skeleton fade animation
    _skeletonController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _skeletonFadeAnimation = CurvedAnimation(
      parent: _skeletonController,
      curve: Curves.easeInOut,
    );

    // Images fade animation
    _imagesController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _imagesFadeAnimation = CurvedAnimation(
      parent: _imagesController,
      curve: Curves.easeInOut,
    );

    // Start skeleton animation
    _skeletonController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only reload images if the app is resumed from the background (not when overlays like notification panel are shown)
    if (state == AppLifecycleState.resumed) {
      // Check if the app was actually paused/inactive before (not just overlay change)
      if (_wasPausedOrInactive) {
        context.read<HomeBloc>().add(LoadImagesEvent());
      }
      _wasPausedOrInactive = false;
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _wasPausedOrInactive = true;
    }
    // Do NOT reload images on every navigation/pop or overlay open/close
  }

  // Track if the app was paused/inactive before resuming
  bool _wasPausedOrInactive = false;

  // Add missing logout method
  void _logout(BuildContext context) async {
    await AuthService().logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // Add missing saveImage method
  Future<void> _saveImage(String prompt, String imageUrl) async {
    // Instead of dispatching an event and waiting for Bloc to reload all images,
    // directly add the new image to the Bloc state so it appears instantly.
    final bloc = context.read<HomeBloc>();
    final currentState = bloc.state;
    if (currentState.imagesLoaded) {
      // Create a new GeneratedImage object (adjust fields as needed)
      final newImage = GeneratedImage(
        imageUrl: imageUrl,
        prompt: prompt,
        // Add other fields if needed
      );
      // Insert at the beginning for instant feedback
      final updatedImages = [newImage, ...currentState.images];
      bloc.emit(
        currentState.copyWith(
          images: updatedImages,
          imagesLoaded: true,
        ),
      );
      // Save to DB in background (optional, for persistence)
      await bloc.dbService.insertImage(newImage);
    } else {
      // Fallback: use the event (old way)
      bloc.add(SaveImageEvent(prompt, imageUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayOpen = ValueNotifier<bool>(false);

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: overlayOpen,
          builder: (context, isOverlayOpen, _) {
            return Scaffold(
              backgroundColor: Colors.black,
              appBar: CustomAppBar(
                title: 'PixAI',
                actions: [
                  // Removed logout button from here
                ],
              ),
              body: BlocListener<HomeBloc, HomeState>(
                listenWhen: (prev, curr) =>
                    prev.showSkeleton != curr.showSkeleton ||
                    prev.imagesLoaded != curr.imagesLoaded,
                listener: (context, state) {
                  // Animate skeleton fade out and images fade in
                  if (!state.showSkeleton) {
                    _skeletonController.reverse();
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (mounted) _imagesController.forward();
                    });
                  } else {
                    _skeletonController.forward();
                    _imagesController.reset();
                  }
                },
                child: BlocBuilder<HomeBloc, HomeState>(
                  builder: (context, state) {
                    return _buildMainContent(context, state);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMainContent(BuildContext context, HomeState state) {
    // This is the previous body: Stack(...
    return Stack(
      children: [
        // Images grid area (background)
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(20.w),
            child: Stack(
              children: [
                // Skeleton fade out with smooth animation
                FadeTransition(
                  opacity: _skeletonFadeAnimation,
                  child: state.showSkeleton
                      ? Skeletonizer(
                          enabled: true,
                          child: MasonryGridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16.h,
                            crossAxisSpacing: 16.w,
                            itemCount: 6,
                            padding: EdgeInsets.only(bottom: 100.h), // <-- Add bottom padding here
                            itemBuilder: (context, index) {
                              final heights = [180.0, 240.0, 320.0, 140.0, 280.0, 200.0];
                              final height = heights[index % heights.length].h;
                              return AnimatedContainer(
                                duration: Duration(milliseconds: 300 + (index * 100)),
                                curve: Curves.easeOutCubic,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(40.r),
                                  child: Container(
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      borderRadius: BorderRadius.circular(40.r),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                
                // Images fade in with smooth animation
                FadeTransition(
                  opacity: _imagesFadeAnimation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _imagesController,
                      curve: Curves.easeOutCubic,
                    )),
                    child: (state.imagesLoaded && state.images.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.easeOutBack,
                                  builder: (context, value, child) {
                                    return Transform.scale(
                                      scale: value,
                                      child: Icon(
                                        Icons.image_outlined,
                                        size: 100.w,
                                        color: Colors.grey[800],
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(height: 16.h),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 1000),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: AutoSizeText(
                                        'No images generated yet',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 18.sp,
                                        ),
                                        maxLines: 1,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          )
                        : (state.imagesLoaded
                            ? MasonryGridView.count(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16.h,
                                crossAxisSpacing: 16.w,
                                itemCount: state.images.length,
                                padding: EdgeInsets.only(bottom: 100.h), // <-- Add bottom padding here
                                itemBuilder: (context, index) {
                                  final img = state.images[index];
                                  final heights = [180.0, 240.0, 320.0, 140.0, 280.0, 200.0];
                                  final height = heights[index % heights.length].h;
                                  final heroTag = 'home-image-${img.imageUrl}';
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        PageRouteBuilder(
                                          transitionDuration: const Duration(milliseconds: 600),
                                          reverseTransitionDuration: const Duration(milliseconds: 400),
                                          pageBuilder: (context, animation, secondaryAnimation) {
                                            return FadeTransition(
                                              opacity: animation,
                                              child: ImageDetailScreen(
                                                imageUrl: img.imageUrl,
                                                prompt: img.prompt,
                                                heroTag: heroTag, // Pass the tag
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                    child: AnimatedBuilder(
                                      animation: index < _imageAnimations.length
                                          ? _imageAnimations[index]
                                          : const AlwaysStoppedAnimation(1.0),
                                      builder: (context, child) {
                                        final animation = index < _imageAnimations.length
                                            ? _imageAnimations[index]
                                            : const AlwaysStoppedAnimation(1.0);

                                        return ClipRRect(
                                          borderRadius: BorderRadius.circular(40.r),
                                          child: Hero(
                                            tag: heroTag, // Use unique tag
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(40.r),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.2),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(40.r),
                                                child: Transform.translate(
                                                  offset: Offset(0, 20 * (1 - animation.value)),
                                                  child: Opacity(
                                                    opacity: animation.value,
                                                    child: Transform.scale(
                                                      scale: 0.9 + (0.1 * animation.value),
                                                      child: CachedNetworkImage(
                                                        imageUrl: img.imageUrl,
                                                        height: height,
                                                        fit: BoxFit.cover,
                                                        placeholder: (context, url) => Container(
                                                          color: Colors.grey[900],
                                                        ),
                                                        errorWidget: (context, url, error) =>
                                                            Icon(Icons.broken_image, size: 80.w, color: Colors.white),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    );
                                  },
                              )
                            : const SizedBox.shrink()),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Bottom input field floating above images
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: GestureDetector(
                onTap: () async {
                  final result = await Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.black38,
                      transitionDuration: const Duration(milliseconds: 420),
                      reverseTransitionDuration: const Duration(milliseconds: 320),
                      pageBuilder: (_, __, ___) => FullScreenPromptInputPageInternal(
                        controller: _promptController,
                        onGenerateImage: (prompt, {int width = 512, int height = 512}) async {
                          final url = await _pixService.generateImage(prompt, width: width, height: height);
                          return url;
                        },
                        isLoading: state.isLoading, // Use state.isLoading
                      ),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOutCubic,
                          reverseCurve: Curves.easeInOutCubic,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(curved),
                            child: child,
                          ),
                        );
                      },
                    ),
                  );
                  _promptController.clear();
                  if (result != null && result is Map && result['prompt'] != null && result['imageUrl'] != null) {
                    await _saveImage(result['prompt'], result['imageUrl']);
                  }
                },
                child: AbsorbPointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([]),
                    builder: (context, child) {
                      return Center(
                        child: CustomPaint(
                          painter: _AnimatedGradientBorderPainter(
                            animationValue: DateTime.now().millisecondsSinceEpoch % 6000 / 6000,
                            borderRadius: 40,
                            borderWidth: 3.5,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.white10,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 18,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(32),
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                                          child: TextField(
                                            controller: _promptController,
                                            autofocus: false,
                                            maxLines: 1,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'e.g. A futuristic city at sunset',
                                              hintStyle: const TextStyle(color: Colors.white70),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(32),
                                                borderSide: BorderSide.none,
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(32),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(32),
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                              fillColor: const Color.fromARGB(0, 92, 92, 92),
                                              filled: true,
                                            ),
                                            onSubmitted: (_) {},
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Make send button card bg transparent and icon white with shine
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18), // Transparent bg
                                        shape: BoxShape.circle,
                                      ),
                                      child: ClipOval(
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.arrow_upward,
                                                color: Colors.white,
                                                size: 28,
                                               
                                              ),
                                              onPressed: null,
                                              tooltip: 'Send',
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
                        ),
                        );
                      },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedGradientBorderPainter extends CustomPainter {
  final double animationValue;
  final double borderRadius;
  final double borderWidth;

  _AnimatedGradientBorderPainter({
    required this.animationValue,
    required this.borderRadius,
    required this.borderWidth,
  }) : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.blue, Colors.purple],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 1.0],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(borderRadius),
      ));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

// Update ImageDetailScreen to accept a heroTag parameter and use it for the Hero widget
class ImageDetailScreen extends StatefulWidget {
  final String imageUrl;
  final String prompt;
  final String heroTag;

  const ImageDetailScreen({
    Key? key,
    required this.imageUrl,
    required this.prompt,
    required this.heroTag,
  }) : super(key: key);

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _showPrompt = true;

  // Add like state
  bool _liked = false;

  final GeneratedImageDbService _dbService = GeneratedImageDbService();

  @override
  void initState() {
    super.initState();
    // No image reloads or Bloc events here!
    // Set status bar to transparent
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    // Load liked status from DB
    _loadLikedStatus();
  }

  Future<void> _loadLikedStatus() async {
    final liked = await _dbService.isImageLiked(widget.imageUrl);
    if (mounted) {
      setState(() {
        _liked = liked;
      });
    }
  }

  Future<void> _toggleLike() async {
    final newLiked = !_liked;
    setState(() {
      _liked = newLiked;
    });
    await _dbService.setLikedStatus(widget.imageUrl, newLiked);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _togglePrompt() {
    setState(() {
      _showPrompt = !_showPrompt;
    });

    if (_showPrompt) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _togglePrompt,
        child: Stack(
          children: [
            // Background gradient for visual depth
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    Colors.grey.shade900.withOpacity(0.3),
                    Colors.black,
                  ],
                ),
              ),
            ),
            // Main image with hero animation
            Center(
              child: Hero(
                tag: widget.heroTag, // Use the tag passed from the grid
                transitionOnUserGestures: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _EnhancedCachedImage(
                      imageUrl: widget.imageUrl,
                    ),
                  ),
                ),
              ),
            ),
            // Top controls with glass morphism effect
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 120.h,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Row(
                      children: [
                        // Back button with glassmorphism
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12.r),
                              onTap: () => Navigator.of(context).pop(),
                              child: Padding(
                                padding: EdgeInsets.all(12.w),
                                child: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Colors.white,
                                  size: 20.w,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Like button
                        Container(
                          margin: EdgeInsets.only(right: 8.w),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12.r),
                              onTap: _toggleLike,
                              child: Padding(
                                padding: EdgeInsets.all(12.w),
                                child: Icon(
                                  _liked ? Icons.favorite : Icons.favorite_border,
                                  color: _liked ? Colors.pinkAccent : Colors.white,
                                  size: 22.w,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // More options button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12.r),
                              onTap: () {
                                _showOptionsBottomSheet(context);
                              },
                              child: Padding(
                                padding: EdgeInsets.all(12.w),
                                child: Icon(
                                  Icons.more_horiz,
                                  color: Colors.white,
                                  size: 20.w,
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
            ),
            // Bottom prompt with enhanced design
            Positioned(
              left: 0,
              right: 0,
              // Move it a bit above the bottom (e.g., 0 for bottom sheet style)
              bottom: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  // Remove margin for full width
                  margin: EdgeInsets.zero,
                  // No horizontal padding here, let the child handle it
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900.withOpacity(0.98),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 24.w,
                          right: 24.w,
                          top: 20.h,
                          bottom: MediaQuery.of(context).padding.bottom + 16.h,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40.w,
                              height: 4.h,
                              margin: EdgeInsets.only(bottom: 16.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2.r),
                              ),
                            ),
                            Text(
                              widget.prompt,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Tap anywhere to ${_showPrompt ? 'hide' : 'show'} prompt',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 20.h),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.white),
              title: const Text('Download', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final path = await DownloadService.downloadAndSaveImage(widget.imageUrl);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved to Downloads:\n$path')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Download failed: $e')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                // Download image and share as file
                try {
                  final response = await http.get(Uri.parse(widget.imageUrl));
                  if (response.statusCode == 200) {
                    final tempDir = await getTemporaryDirectory();
                    final file = File('${tempDir.path}/shared_image.png');
                    await file.writeAsBytes(response.bodyBytes);
                    await Share.shareXFiles([XFile(file.path)], text: widget.prompt);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to download image for sharing')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error sharing image: $e')),
                  );
                }
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16.h),
          ],
        ),
      ),
    );
  }
}

class _EnhancedCachedImage extends StatefulWidget {
  final String imageUrl;

  const _EnhancedCachedImage({
    required this.imageUrl,
  });

  @override
  State<_EnhancedCachedImage> createState() => _EnhancedCachedImageState();
}

class _EnhancedCachedImageState extends State<_EnhancedCachedImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;
  ImageProvider? _provider;
  bool _checkedCache = false;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOutSine,
    ));

    _checkCache();
  }

  void _checkCache() async {
    final provider = CachedNetworkImageProvider(widget.imageUrl);
    final config = ImageConfiguration();
    final key = await provider.obtainKey(config);
    final cache = PaintingBinding.instance.imageCache;
    final cached = cache?.containsKey(key) ?? false;
    if (cached) {
      setState(() {
        _provider = provider;
        _checkedCache = true;
      });
    } else {
      setState(() {
        _provider = null;
        _checkedCache = true;
      });
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedCache) {
      // While checking cache, show nothing (or a transparent container)
      return const SizedBox.shrink();
    }
    if (_provider != null) {
      // Use full screen and BoxFit.contain to match the Hero source and avoid zoom effect
      return Image(
        image: _provider!,
        fit: BoxFit.contain, // Use the same fit as the Hero source in the grid
        width: double.infinity,
        height: double.infinity,
      );
    }
    // Not in cache, show error
    return _buildErrorWidget();
  }

  Widget _buildShimmerPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: AnimatedBuilder(
        animation: _shimmerAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey.shade800,
                  Colors.grey.shade700,
                  Colors.grey.shade800,
                ],
                stops: [
                  (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                  _shimmerAnimation.value.clamp(0.0, 1.0),
                  (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image,
                    size: 48.w,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14.sp,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 64.w,
            color: Colors.red.shade400,
          ),
          SizedBox(height: 16.h),
          Text(
            'Image not in cache',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'This image is not available offline.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }
}