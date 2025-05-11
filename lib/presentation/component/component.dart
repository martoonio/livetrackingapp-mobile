import 'package:flutter/material.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

void backToPreviousScreen(BuildContext context) {
  Navigator.pop(context);
}

Widget leadingButton(BuildContext context, String text, Function? onPressed) {
  return ElevatedButton.icon(
    onPressed: () {
      if (onPressed != null) {
        onPressed(); // Panggil fungsi onPressed jika tidak null
      } else {
        backToPreviousScreen(context); // Gunakan fungsi default
      }
    },
    icon: const Icon(
      Icons.arrow_back, // Ikon untuk tombol "Back"
      color: Colors.white,
    ),
    label: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: kbpBlue900, // Warna latar belakang tombol
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // Radius untuk tombol
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );
}
