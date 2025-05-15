import 'package:intl/intl.dart';

export 'intExtension.dart';
export 'colorUtils.dart';
export 'component.dart';
export 'radiusUtils.dart';
export 'paddingUtils.dart';
export 'textStyle.dart';
export 'customSnackBar.dart';

String formatDateFromString(String isoString) {
    final date = DateTime.parse(isoString);
    return DateFormat('d MMM yyyy', 'id_ID')
        .format(date); // Output: 13 May 2025
  }

  String formatTimeFromString(String isoString) {
    final date = DateTime.parse(isoString);
    return DateFormat('HH:mm').format(date); // Output: 11:42
  }