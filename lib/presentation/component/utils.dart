import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/user.dart';

export 'intExtension.dart';
export 'colorUtils.dart';
export 'component.dart';
export 'radiusUtils.dart';
export 'paddingUtils.dart';
export 'textStyle.dart';
export 'customSnackBar.dart';
export 'empty_state.dart';

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

String getShortShiftText(ShiftType shift) {
  switch (shift) {
    case ShiftType.pagi:
      return 'Pagi (07-15)';
    case ShiftType.sore:
      return 'Sore (15-23)';
    case ShiftType.malam:
      return 'Malam (23-07)';
    case ShiftType.siang:
      return 'Siang (07-19)';
    case ShiftType.malamPanjang:
      return 'Malam (19-07)';
  }
}