import 'package:intl/intl.dart';

export 'intExtension.dart';
export 'colorUtils.dart';
export 'component.dart';
export 'radiusUtils.dart';
export 'paddingUtils.dart';
export 'textStyle.dart';
export 'customSnackBar.dart';

String formatDateFromString(String? isoString) {
  if (isoString == null || isoString.isEmpty) {
    return 'N/A';
  }

  try {
    // Menangani berbagai format tanggal termasuk dengan mikrodetik
    DateTime date;
    if (isoString.contains('.')) {
      // Format dengan mikrodetik
      final parts = isoString.split('.');
      final mainPart = parts[0];
      final microPart = parts[1];

      // Batasi mikrodetik menjadi 6 digit untuk mencegah overflow
      final cleanMicroPart =
          microPart.length > 6 ? microPart.substring(0, 6) : microPart;

      date = DateTime.parse('$mainPart.$cleanMicroPart');
    } else {
      date = DateTime.parse(isoString);
    }

    return DateFormat('d MMM yyyy', 'id_ID').format(date);
  } catch (e) {
    print('Error parsing date: $isoString, error: $e');
    return 'N/A';
  }
}

String formatTimeFromString(String? isoString) {
  if (isoString == null || isoString.isEmpty) {
    return 'N/A';
  }

  try {
    // Menangani berbagai format tanggal termasuk dengan mikrodetik
    DateTime date;
    if (isoString.contains('.')) {
      // Format dengan mikrodetik
      final parts = isoString.split('.');
      final mainPart = parts[0];
      final microPart = parts[1];

      // Batasi mikrodetik menjadi 6 digit untuk mencegah overflow
      final cleanMicroPart =
          microPart.length > 6 ? microPart.substring(0, 6) : microPart;

      date = DateTime.parse('$mainPart.$cleanMicroPart');
    } else {
      date = DateTime.parse(isoString);
    }

    return DateFormat('HH:mm').format(date);
  } catch (e) {
    print('Error parsing time: $isoString, error: $e');
    return 'N/A';
  }
}

// Tambahkan fungsi helper untuk durasi patroli yang aman
String getDurasiPatroli(DateTime? endTime, {DateTime? startTime}) {
  if (endTime == null) return 'N/A';

  final end = endTime;
  final start = startTime ?? DateTime.now();

  final difference = end.difference(start);

  final hours = difference.inHours;
  final minutes = difference.inMinutes.remainder(60);

  return '$hours jam $minutes menit';
}

List<List<double>> parseRouteCoordinates(dynamic routeData) {
    if (routeData is! List) return [];

    try {
      return (routeData as List).map((route) {
        if (route is! List) return <double>[];
        return (route as List).map((coord) {
          if (coord is double) return coord;
          if (coord is int) return coord.toDouble();
          return 0.0;
        }).toList();
      }).toList();
    } catch (e) {
      print('Error parsing route coordinates: $e');
      return [];
    }
  }
