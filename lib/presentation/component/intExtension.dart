import 'package:flutter/material.dart';

/// Model class for Size Configurations
class SizeConfig {
  static MediaQueryData? _mediaQueryData;
  static double? screenWidth;
  static double? screenHeight;
  static Orientation? orientation;

  void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData!.size.width;
    screenHeight = _mediaQueryData!.size.height;
    orientation = _mediaQueryData!.orientation;
  }
}

extension IntExtension on int? {
  /// Leaves given height of space
  Widget get height => SizedBox(height: this?.toDouble());

  double get dynamicHeight {
    double screenHeight = SizeConfig.screenHeight as double;
    // 812 is the layout height that designer use
    return (this! / 585) * screenHeight;
  }

  double get dynamicWidth {
    double screenWidth = SizeConfig.screenWidth as double;
    // 375 is the layout width that designer use
    return (this! / 270) * screenWidth;
  }

  /// Leaves given width of space
  Widget get width => SizedBox(width: this?.toDouble());
}