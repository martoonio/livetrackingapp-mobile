import '/presentation/component/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'textStyle.dart';

enum SnackbarType { success, warning, danger }

enum SnackbarEntryDirection { fromTop, fromBottom }

class CustomSnackbar extends StatelessWidget {
  final String title;
  final TextStyle? titleTextStyle;
  final String subtitle;
  final TextStyle? subtitleTextStyle;
  final SnackbarType type;

  const CustomSnackbar({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.type,
    this.titleTextStyle,
    this.subtitleTextStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final backgroundColor = neutralWhite;
    final icon = _getIcon(type);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            offset: const Offset(0, 16), // Adjust offset if needed
            blurRadius: 24,
            spreadRadius: -4, // To extend shadow to the sides
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      (titleTextStyle ?? semiBoldTextStyle(size: h7)).copyWith(
                    decoration: TextDecoration.none, // Ensures no underline
                  ),
                ),
                Text(
                  subtitle,
                  style: (subtitleTextStyle ??
                          mediumTextStyle(
                            size: paragrafLG,
                            color: neutral800,
                          ))
                      .copyWith(
                    decoration: TextDecoration.none, // Ensures no underline
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Function to get icon based on type
  Widget _getIcon(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return SvgPicture.asset(
          'assets/state/successIcon.svg',
          width: 27,
          height: 27,
        );
      case SnackbarType.warning:
        return SvgPicture.asset(
          'assets/state/warningIcon.svg',
          width: 27,
          height: 27,
        );
      case SnackbarType.danger:
        return SvgPicture.asset(
          'assets/state/dangerIcon.svg',
          width: 27,
          height: 27,
        );
    }
  }
}

// Function to show the custom snackbar with animations
void showCustomSnackbar({
  required BuildContext context,
  required String title,
  required String subtitle,
  required SnackbarType type,
  SnackbarEntryDirection entryDirection = SnackbarEntryDirection.fromBottom,
  TextStyle? titleTextStyle,
  TextStyle? subtitleTextStyle,
}) {
  final overlay = Overlay.of(context);
  final animationController = AnimationController(
    duration: const Duration(milliseconds: 250),
    vsync: ScaffoldMessenger.of(context),
  );

  // Offset animation
  final offsetBegin = entryDirection == SnackbarEntryDirection.fromBottom
      ? Offset(0.0, 1.0)
      : Offset(0.0, -1.0);
  final offsetAnimation = Tween<Offset>(
    begin: offsetBegin,
    end: Offset(0.0, 0.0),
  ).animate(CurvedAnimation(
    parent: animationController,
    curve: Curves.easeOut,
  ));
  final fadeAnimation = Tween<double>(
    begin: 0.0,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: animationController,
    curve: Curves.easeIn,
  ));

  // Placeholder for the entry to allow reference in GestureDetector
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => Positioned(
      bottom: entryDirection == SnackbarEntryDirection.fromBottom ? 65 : null,
      top: entryDirection == SnackbarEntryDirection.fromTop ? 40 : null,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: GestureDetector(
          onVerticalDragUpdate: (details) {
            if (entryDirection == SnackbarEntryDirection.fromBottom &&
                details.primaryDelta! > 5) {
              // Swipe down
              animationController.reverse().whenComplete(() {
                entry.remove();
              });
            } else if (entryDirection == SnackbarEntryDirection.fromTop &&
                details.primaryDelta! < -5) {
              // Swipe up
              animationController.reverse().whenComplete(() {
                entry.remove();
              });
            }
          },
          child: SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(
              opacity: fadeAnimation,
              child: CustomSnackbar(
                title: title,
                subtitle: subtitle,
                type: type,
                titleTextStyle: titleTextStyle,
                subtitleTextStyle: subtitleTextStyle,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  animationController.forward();

  // Auto-dismiss the snackbar after 3 seconds
  Future.delayed(const Duration(seconds: 3), () {
    animationController.reverse().whenComplete(() {
      entry.remove();
    });
  });
}
