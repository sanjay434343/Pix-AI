import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../models/generated_image.dart';
import '../services/generated_image_db_service.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'home_screen.dart'; // <-- Add this import at the top if not present
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/download_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  String? uid;
  String? email;
  String? displayName;
  String? photoUrl;

  // Add: Track if loaded from cache
  bool _loadedFromCache = false;

  // Liked images state
  final GeneratedImageDbService _dbService = GeneratedImageDbService();
  List<GeneratedImage> _likedImages = [];
  bool _likedLoaded = false;
  List<AnimationController> _likedAnimControllers = [];
  List<Animation<double>> _likedAnims = [];

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // For ExpansionPanelList state
  List<bool> _settingsExpanded = List<bool>.filled(2, false);

  bool _isBackingUp = false;
  bool _hasBackup = false;
  DateTime? _lastBackupTime;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadLikedImages();
    _checkBackupExists();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUid = prefs.getString('uid');
    final cachedEmail = prefs.getString('profile_email');
    final cachedName = prefs.getString('profile_name');
    final cachedPhoto = prefs.getString('profile_photo');

    // If cached, show immediately
    if (cachedEmail != null || cachedName != null || cachedPhoto != null) {
      setState(() {
        email = cachedEmail;
        displayName = cachedName;
        photoUrl = cachedPhoto;
        _loadedFromCache = true;
        uid = storedUid;
      });
    } else {
      setState(() {
        uid = storedUid;
      });
    }

    // Try to get Google user info if available
    final googleSignIn = GoogleSignIn();
    final account = await googleSignIn.signInSilently();
    if (account != null) {
      // If info changed, update and cache
      if (account.email != email || account.displayName != displayName || account.photoUrl != photoUrl) {
        setState(() {
          email = account.email;
          displayName = account.displayName;
          photoUrl = account.photoUrl;
          _loadedFromCache = false;
        });
        // Save to cache
        await prefs.setString('profile_email', account.email ?? '');
        await prefs.setString('profile_name', account.displayName ?? '');
        await prefs.setString('profile_photo', account.photoUrl ?? '');
      }
    }
  }

  Future<void> _loadLikedImages() async {
    // Only load images where liked = 1
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'images',
      where: 'liked = ?',
      whereArgs: [1],
      orderBy: 'id DESC',
    );
    setState(() {
      _likedImages = List.generate(maps.length, (i) => GeneratedImage.fromMap(maps[i]));
      _likedLoaded = true;
    });
    _setupLikedAnimations();
    _triggerLikedStaggeredFadeIn();
  }

  void _setupLikedAnimations() {
    for (var c in _likedAnimControllers) {
      c.dispose();
    }
    _likedAnimControllers = List.generate(
      _likedImages.length,
      (i) => AnimationController(
        duration: Duration(milliseconds: 600 + (i * 50)),
        vsync: this,
      ),
    );
    _likedAnims = _likedAnimControllers.map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutCubic)).toList();
  }

  Future<void> _triggerLikedStaggeredFadeIn() async {
    for (int i = 0; i < _likedImages.length; i++) {
      if (mounted && i < _likedAnimControllers.length) {
        _likedAnimControllers[i].forward();
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  // Helper: get all liked images as maps
  Future<List<Map<String, dynamic>>> _getAllImagesAsMaps() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query('images');
    return maps;
  }

  // Helper: replace all images in local db
  Future<void> _replaceAllImagesFromMaps(List<Map<String, dynamic>> maps) async {
    final db = await _dbService.database;
    await db.delete('images');
    for (final map in maps) {
      // Only insert columns that exist in the local DB schema
      final insertMap = <String, dynamic>{
        'imageUrl': map['imageUrl'],
        'prompt': map['prompt'],
        'liked': map['liked'] is int
            ? map['liked']
            : (map['liked'] == true ? 1 : 0),
        // Do NOT include 'createdAt' if your table does not have this column
      };
      await db.insert('images', insertMap);
    }
    await _loadLikedImages();
  }

  Future<void> _deleteAllImages() async {
    final db = await _dbService.database;
    await db.delete('images');
    await _loadLikedImages();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All images deleted'),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _checkBackupExists() async {
    // Always get the latest UID from current user if not set
    if (uid == null || uid!.isEmpty) {
      final user = AuthService().currentUser;
      uid = user?.uid;
    }
    if (uid == null || uid!.isEmpty) {
      setState(() {
        _hasBackup = false;
        _lastBackupTime = null;
      });
      return;
    }
    final backupRef = _firestore
        .collection('pixai')
        .doc('main')
        .collection('backups')
        .doc(uid);
    final doc = await backupRef.get();
    final images = doc.data()?['images'];
    final lastBackupStr = doc.data()?['lastBackup'];
    DateTime? lastBackup;
    if (lastBackupStr is String) {
      try {
        lastBackup = DateTime.parse(lastBackupStr);
      } catch (_) {}
    }
    debugPrint('Checking backup exists for uid=$uid: exists=${doc.exists}');
    setState(() {
      _hasBackup = doc.exists && images is List && (images as List).isNotEmpty;
      _lastBackupTime = lastBackup;
    });
  }

  bool get _canBackup {
    if (_lastBackupTime == null) return true;
    final now = DateTime.now();
    return now.difference(_lastBackupTime!).inDays >= 7;
  }

  Future<void> _backupToFirestore() async {
    // Get UID from current logged-in user if not set
    if (uid == null || uid!.isEmpty) {
      final user = AuthService().currentUser;
      uid = user?.uid;
      debugPrint('Fetched UID from currentUser: $uid');
    }
    if (uid == null || uid!.isEmpty) {
      debugPrint('No UID found, cannot backup.');
      setState(() {
        _isBackingUp = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No user ID found. Please log in again.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    // Prevent backup if not allowed
    if (!_canBackup) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup allowed only once per week.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    setState(() {
      _isBackingUp = true;
    });
    final images = await _getAllImagesAsMaps();

    debugPrint('Backup button pressed. Images to backup: ${images.length}');
    // Store backup under /pixai/backups/{uid}
    final backupRef = _firestore
        .collection('pixai')
        .doc('main')
        .collection('backups')
        .doc(uid);

    debugPrint('Firestore backupRef path: ${backupRef.path}');

    try {
      final doc = await backupRef.get();
      List<dynamic> oldImages = [];
      if (doc.exists && doc.data()?['images'] is List) {
        oldImages = doc.data()!['images'];
      }

      debugPrint('Backing up for uid=$uid');
      debugPrint('Old images count: ${oldImages.length}');
      debugPrint('New images count: ${images.length}');

      // Merge by imageUrl (avoid duplicates, keep latest)
      final Map<String, Map<String, dynamic>> merged = {};
      for (final img in oldImages) {
        if (img is Map && img['imageUrl'] != null) {
          merged[img['imageUrl']] = Map<String, dynamic>.from(img);
        }
      }
      for (final img in images) {
        if (img['imageUrl'] != null) {
          merged[img['imageUrl']] = {
            'imageUrl': img['imageUrl'],
            'prompt': img['prompt'],
            'createdAt': img['createdAt'] ?? DateTime.now().toIso8601String(),
            'liked': img['liked'] ?? false,
          };
        }
      }

      final backupData = {
        'images': merged.values.toList(),
        'lastBackup': DateTime.now().toIso8601String(),
      };

      debugPrint('Uploading backup: ${(backupData['images'] is List) ? (backupData['images'] as List).length : 0} images');
      await backupRef.set(backupData);
      debugPrint('Backup set in Firestore at: ${backupRef.path}');

      setState(() {
        _isBackingUp = false;
        _hasBackup = true; // Ensure restore button is enabled after backup
        _lastBackupTime = DateTime.now();
      });

      debugPrint('Backup complete for uid=$uid');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup to cloud complete'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Error uploading backup: $e\n$st');
      setState(() {
        _isBackingUp = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _restoreFromFirestore() async {
    if (uid == null || uid!.isEmpty) {
      final user = AuthService().currentUser;
      uid = user?.uid;
    }
    if (uid == null || uid!.isEmpty) return;
    // Read backup from /pixai/backups/{uid}
    final backupRef = _firestore
        .collection('pixai')
        .doc('main')
        .collection('backups')
        .doc(uid);

    debugPrint('Firestore restoreRef path: ${backupRef.path}');

    final doc = await backupRef.get();
    debugPrint('Restoring backup for uid=$uid: exists=${doc.exists}');
    if (doc.exists && doc.data()?['images'] is List) {
      final List<dynamic> images = doc.data()!['images'];
      debugPrint('Restoring ${images.length} images');
      final List<Map<String, dynamic>> maps = images.cast<Map<String, dynamic>>();
      await _replaceAllImagesFromMaps(maps);
      setState(() {
        _hasBackup = true; // Keep restore enabled after restore
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restore from cloud complete'),
            duration: Duration(seconds: 5),
          ),
        );
        // Redirect to HomeScreen if user is still logged in (uid is valid)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && uid != null && uid!.isNotEmpty) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()), // <-- Use const HomeScreen()
              (route) => false,
            );
          }
        });
      }
    } else {
      setState(() {
        _hasBackup = false; // Disable restore if no backup found
      });
      debugPrint('No backup found for uid=$uid');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backup found in cloud'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _dbService.close();
    for (var c in _likedAnimControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show shimmer if not loaded from cache and no data yet
    final isLoading = !_loadedFromCache && photoUrl == null && displayName == null && email == null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white), // Make back button white
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              tooltip: 'Logout',
              onPressed: () async {
                // Logout logic (copied from home_screen.dart)
                // Import AuthService and LoginScreen if not already imported
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.only(top: 32.h, left: 24.w, right: 24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: isLoading
                    ? Skeletonizer(
                        enabled: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 48.r,
                              backgroundColor: Colors.grey[800],
                            ),
                            SizedBox(width: 24.w),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 10.h),
                                Container(
                                  width: 120.w,
                                  height: 24.h,
                                  color: Colors.grey[800],
                                ),
                                SizedBox(height: 8.h),
                                Container(
                                  width: 180.w,
                                  height: 18.h,
                                  color: Colors.grey[800],
                                ),
                                SizedBox(height: 8.h),
                                Container(
                                  width: 100.w,
                                  height: 14.h,
                                  color: Colors.grey[800],
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (photoUrl != null && photoUrl!.isNotEmpty)
                            CircleAvatar(
                              radius: 48.r,
                              backgroundImage: NetworkImage(photoUrl!),
                            ),
                          SizedBox(width: 24.w),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 10.h),
                              if (displayName != null && displayName!.isNotEmpty)
                                SizedBox(
                                  width: 180.w,
                                  child: AutoSizeText(
                                    displayName!,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 32.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    minFontSize: 18,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (email != null && email!.isNotEmpty) ...[
                                SizedBox(height: 8.h),
                                SizedBox(
                                  width: 180.w,
                                  child: AutoSizeText(
                                    email!,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16.sp,
                                    ),
                                    maxLines: 1,
                                    minFontSize: 10,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
              ),
              // Remove UID display entirely
              // if (!isLoading && uid != null) ...[
              //   SizedBox(height: 24.h),
              //   GestureDetector(
              //     onTap: () {
              //       // Optionally copy UID to clipboard or show a dialog if needed
              //     },
              //     child: AutoSizeText(
              //       'UID: •••••••••••••••••••••••••••••••••••••••••',
              //       style: TextStyle(
              //         color: Colors.white38,
              //         fontSize: 14.sp,
              //         letterSpacing: 2,
              //       ),
              //       maxLines: 1,
              //       minFontSize: 8,
              //       overflow: TextOverflow.ellipsis,
              //     ),
              //   ),
              // ],
              SizedBox(height: 32.h),
              TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Liked'),
                  Tab(text: 'Settings'),
                ],
              ),
              SizedBox(height: 16.h),
              Expanded(
                child: TabBarView(
                  children: [
                    // --- Liked Tab ---
                    _likedLoaded
                        ? _likedImages.isEmpty
                            ? Center(
                                child: Text(
                                  'No liked images yet',
                                  style: TextStyle(color: Colors.white70, fontSize: 16.sp),
                                ),
                              )
                            : MasonryGridView.count(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16.h,
                                crossAxisSpacing: 16.w,
                                itemCount: _likedImages.length,
                                itemBuilder: (context, index) {
                                  final img = _likedImages[index];
                                  final heights = [180.0, 240.0, 320.0, 140.0, 280.0, 200.0];
                                  final height = heights[index % heights.length].h;
                                  final anim = index < _likedAnims.length
                                      ? _likedAnims[index]
                                      : const AlwaysStoppedAnimation(1.0);

                                  return GestureDetector(
                                    onTap: () {
                                      final heroTag = 'profile-image-${img.imageUrl}';
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
                                    onLongPress: () async {
                                      // Download image and share as file
                                      try {
                                        final response = await http.get(Uri.parse(img.imageUrl));
                                        if (response.statusCode == 200) {
                                          final tempDir = await getTemporaryDirectory();
                                          final file = File('${tempDir.path}/shared_image.png');
                                          await file.writeAsBytes(response.bodyBytes);
                                          await Share.shareXFiles([XFile(file.path)], text: img.prompt);
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
                                    child: AnimatedBuilder(
                                      animation: anim,
                                      builder: (context, child) {
                                        return ClipRRect(
                                          borderRadius: BorderRadius.circular(40.r),
                                          child: Hero(
                                            tag: 'profile-image-${img.imageUrl}', // Unique tag for profile page
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
                                                  offset: Offset(0, 20 * (1 - anim.value)),
                                                  child: Opacity(
                                                    opacity: anim.value,
                                                    child: Transform.scale(
                                                      scale: 0.9 + (0.1 * anim.value),
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
                        : Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                    // --- Settings Tab ---
                    Padding(
                      padding: EdgeInsets.only(top: 32.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            icon: Icon(Icons.delete_forever, color: Colors.red),
                            label: Text('Delete All Images', style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.red),
                              foregroundColor: Colors.red,
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Colors.black,
                                  title: const Text('Delete All Images?', style: TextStyle(color: Colors.white)),
                                  content: const Text(
                                    'This will permanently delete all your images from this device.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _deleteAllImages(); // This deletes all generated images from the local database
                              }
                            },
                          ),
                          SizedBox(height: 24),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: Icon(Icons.cloud_upload, color: Colors.white),
                                  label: Text(
                                    _canBackup
                                        ? 'Backup to Cloud'
                                        : 'Backup available in ${(7 - DateTime.now().difference(_lastBackupTime ?? DateTime(2000)).inDays).clamp(1, 7)} day(s)',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.white),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    minimumSize: Size(double.infinity, 48),
                                  ),
                                  onPressed: (_isBackingUp || !_canBackup)
                                      ? null
                                      : () async {
                                          await _backupToFirestore();
                                        },
                                ),
                              ),
                              if (_isBackingUp)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.5),
                                    child: Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 16),
                          OutlinedButton.icon(
                            icon: Icon(Icons.cloud_download, color: Colors.white),
                            label: Text('Restore from Cloud', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              minimumSize: Size(double.infinity, 48),
                            ),
                            onPressed: _hasBackup ? _restoreFromFirestore : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
