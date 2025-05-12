import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
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

Widget rowInfo(String title, String? value) {
  return Row(
    children: [
      if (value != null)
        SvgPicture.asset(
          'assets/vehicle/$value.svg',
          width: 27,
          height: 27,
        ),
      if (value != null) 8.width,
      Text(
        title,
        style: (value != null)
            ? boldTextStyle(
                size: h7,
              )
            : regularTextStyle(
                size: h7,
              ),
      ),
    ],
  );
}

InputDecoration inputDecoration(String hintText) {
  return InputDecoration(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(
        color: kbpBlue900,
        width: 2,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(
        color: neutral900,
        width: 1,
      ),
    ),
    hintText: hintText,
    hintStyle: regularTextStyle(
      color: neutral700,
      size: h7,
    ).copyWith(
      fontStyle: FontStyle.italic,
    ),
  );
}
