import 'package:flutter/material.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class UndoButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const UndoButton({Key? key, required this.onPressed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.undo, color: kbpBlue900),
      label: const Text(
        'Undo Last Point',
        style: TextStyle(
          color: kbpBlue900,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
