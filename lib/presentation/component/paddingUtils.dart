import 'package:flutter/material.dart';
import 'radiusUtils.dart';

extension WidgetExtension on Widget? {
  /// return padding top
  Padding paddingTop(double top) {
    return Padding(padding: EdgeInsets.only(top: top), child: this);
  }

  /// return padding left
  Padding paddingLeft(double left) {
    return Padding(padding: EdgeInsets.only(left: left), child: this);
  }

  /// return padding right
  Padding paddingRight(double right) {
    return Padding(padding: EdgeInsets.only(right: right), child: this);
  }

  /// return padding bottom
  Padding paddingBottom(double bottom) {
    return Padding(padding: EdgeInsets.only(bottom: bottom), child: this);
  }

  /// return padding all
  Padding paddingAll(double padding) {
    return Padding(padding: EdgeInsets.all(padding), child: this);
  }

  /// return custom padding from each side
  Padding paddingOnly({
    double top = 0.0,
    double left = 0.0,
    double bottom = 0.0,
    double right = 0.0,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(left, top, right, bottom),
      child: this,
    );
  }

  /// return padding symmetric
  Padding paddingSymmetric({double vertical = 0.0, double horizontal = 0.0}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical, horizontal: horizontal),
      child: this,
    );
  }

  /// set parent widget in center
  Widget center({double? heightFactor, double? widthFactor}) {
    return Center(
      heightFactor: heightFactor,
      widthFactor: widthFactor,
      child: this,
    );
  }

  static Color? defaultInkWellSplashColor;
  static Color? defaultInkWellHoverColor;
  static Color? defaultInkWellHighlightColor;
  static double? defaultInkWellRadius;
  static double defaultRadius = 8.0;

  Widget onTap(
    VoidCallback? function, {
    // Use VoidCallback for the function type
    BorderRadius? borderRadius,
    Color? splashColor,
    Color? hoverColor,
    Color? highlightColor,
    Color? focusColor,
    MaterialStateProperty<Color?>?
        overlayColor, // Fix the type for overlayColor
  }) {
    return InkWell(
      onTap: function, // Pass the function directly
      borderRadius: borderRadius ??
          (defaultInkWellRadius != null ? radius(defaultInkWellRadius) : null),
      child: this,
      splashColor: splashColor ?? defaultInkWellSplashColor,
      hoverColor: hoverColor ?? defaultInkWellHoverColor,
      highlightColor: highlightColor ?? defaultInkWellHighlightColor,
      focusColor: focusColor,
      overlayColor: overlayColor,
    );
  }
}
