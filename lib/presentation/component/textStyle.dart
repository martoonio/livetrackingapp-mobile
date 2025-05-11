import 'package:flutter/material.dart';

import 'colorUtils.dart';

double displaySize = 40;
double h1 = 36;
double h2 = 32;
double h3 = 28;
double h4 = 24;
double h5 = 20;
double h6 = 18;
double h7 = 16;
double paragrafXL = 14;
double paragrafLG = 12;
double paragrafMD = 10;
double paragrafSM = 8;

double calculateLetterSpacing(double fontSize, double percentage) {
  return (percentage / 100) * fontSize;
}

String capitalizeWords(String str) {
  List<String> words = str.toLowerCase().split(' ');

  List<String> capitalizedWords = words.map((word) {
    if (word.isNotEmpty) {
      return word[0].toUpperCase() + word.substring(1);
    }
    return word;
  }).toList();

  return capitalizedWords.join(' ');
}

String capitalizeAll(String str) {
  return str.toUpperCase();
}

TextStyle boldTextStyle({
  double? size,
  Color? color,
  FontWeight? weight,
  String? fontFamily,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size != null ? size.toDouble() : paragrafXL,
    color: color ?? neutral900,
    fontWeight: weight ?? FontWeight.w700,
    fontFamily: fontFamily ?? 'Inter',
    letterSpacing: calculateLetterSpacing(size != null ? size.toDouble() : paragrafXL, -0.03),
  );
}

TextStyle semiBoldTextStyle({
  double? size,
  Color? color,
  FontWeight? weight,
  String? fontFamily,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size != null ? size.toDouble() : h6,
    color: color ?? neutral900,
    fontWeight: weight ?? FontWeight.w600,
    fontFamily: fontFamily ?? 'Inter',
    letterSpacing: calculateLetterSpacing(size != null ? size.toDouble() : h6, -0.03),
  );
}

TextStyle mediumTextStyle({
  double? size,
  Color? color,
  FontWeight? weight,
  String? fontFamily,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size != null ? size.toDouble() : paragrafXL,
    color: color ?? neutral900,
    fontWeight: weight ?? FontWeight.w500,
    fontFamily: fontFamily ?? 'Inter',
    letterSpacing: calculateLetterSpacing(size != null ? size.toDouble() : paragrafXL, -0.03),
  );
}

TextStyle regularTextStyle({
  double? size,
  Color? color,
  FontWeight? weight,
  String? fontFamily,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size != null ? size.toDouble() : paragrafLG,
    color: color ?? neutral900,
    fontWeight: weight ?? FontWeight.w400,
    fontFamily: fontFamily ?? 'Inter',
    letterSpacing: calculateLetterSpacing(size != null ? size.toDouble() : paragrafLG, -0.03),
  );
}