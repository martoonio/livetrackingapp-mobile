import 'package:flutter/material.dart';

void backToPreviousScreen(BuildContext context) {
  Navigator.pop(context);
}

Widget leadingButton(BuildContext context, String text, Function? onPressed) {
  return TextButton(
    onPressed: () => onPressed ?? backToPreviousScreen(context),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 16,
      ),
    ),
  );
}