import 'package:flutter/material.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final Widget? customAction;
  final double? iconSize;

  const EmptyState({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonText,
    this.onButtonPressed,
    this.customAction,
    this.iconSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSize ?? 64,
              color: neutral400,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: boldTextStyle(size: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: neutral600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (customAction != null) customAction!,
            if (buttonText != null && onButtonPressed != null)
              ElevatedButton.icon(
                onPressed: onButtonPressed,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: Text(
                  buttonText!,
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}