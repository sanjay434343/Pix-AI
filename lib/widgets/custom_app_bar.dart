import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:pixai/screens/profile_page.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final Color backgroundColor;
  final double elevation;

  const CustomAppBar({
    Key? key,
    required this.title,
    this.actions,
    this.leading,
    this.backgroundColor = Colors.black,
    this.elevation = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: elevation,
      backgroundColor: backgroundColor,
      leading: leading,
      titleSpacing: 0, // Remove default title padding
      title: Row(
        mainAxisSize: MainAxisSize.min, // Make row as tight as possible
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: 50,
            height: 50,
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22.sp,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedUser,
            color: Colors.white,
            size: 22.0,
          ),
          tooltip: 'Profile',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfilePage()),
            );
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

// To use this CustomAppBar in your home page, add the following in your Scaffold:

// import 'package:pixai/widgets/custom_app_bar.dart';

// Scaffold(
//   appBar: CustomAppBar(
//     title: 'Home',
//     // actions: [ ... ], // Optional: pass additional actions if needed
//   ),
//   body: ...,
// );
