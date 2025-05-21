import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/component/colorUtils.dart';

import 'textStyle.dart';

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

// Tambahkan helper methods untuk timeliness di awal class _PatrolHistoryScreenState

// Helper untuk menentukan warna timeliness
Color getTimelinessColor(String? timeliness) {
  switch (timeliness?.toLowerCase()) {
    case 'ontime':
      return successG500;
    case 'late':
      return warningY500;
    case 'pastDue':
      return dangerR500;
    default:
      return neutral500;
  }
}

// Helper untuk menerjemahkan status timeliness
String getTimelinessText(String? timeliness) {
  switch (timeliness?.toLowerCase()) {
    case 'ontime':
      return 'Tepat Waktu';
    case 'late':
      return 'Terlambat';
    case 'pastDue':
      return 'Melewati Batas';
    default:
      return 'Tidak Diketahui';
  }
}

// Tambahkan widget untuk badge timeliness
Widget buildTimelinessIndicator(String? timeliness) {
  if (timeliness == null) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: getTimelinessColor(timeliness),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          timeliness.toLowerCase() == 'ontime'
              ? Icons.check_circle
              : timeliness.toLowerCase() == 'late'
                  ? Icons.access_time
                  : Icons.error,
          color: Colors.white,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          getTimelinessText(timeliness),
          style: mediumTextStyle(size: 12, color: neutralWhite),
        ),
      ],
    ),
  );
}

String getTimelinessDescription(String? timeliness) {
  switch (timeliness?.toLowerCase()) {
    case 'ontime':
      return 'Petugas memulai patroli tepat waktu';
    case 'late':
      return 'Petugas terlambat memulai patroli (>10 menit)';
    case 'pastDue':
      return 'Patroli melewati batas waktu yang ditentukan';
    default:
      return 'Status ketepatan tidak diketahui';
  }
}

// Helper untuk deskripsi detail timeliness
String getTimelinessDetailDescription(
    String? timeliness, DateTime? startTime, DateTime? assignedStartTime) {
  if (timeliness?.toLowerCase() == 'ontime') {
    if (startTime != null && assignedStartTime != null) {
      final difference = startTime.difference(assignedStartTime).inMinutes;
      if (difference < 0) {
        return 'Petugas memulai patroli ${-difference} menit lebih awal dari jadwal.';
      } else if (difference == 0) {
        return 'Petugas memulai patroli tepat pada waktu yang dijadwalkan.';
      } else {
        return 'Petugas memulai patroli $difference menit setelah jadwal, masih dalam batas waktu yang diterima.';
      }
    }
    return 'Patroli dimulai tepat waktu.';
  } else if (timeliness?.toLowerCase() == 'late') {
    if (startTime != null && assignedStartTime != null) {
      final difference = startTime.difference(assignedStartTime).inMinutes;
      return 'Petugas memulai patroli $difference menit terlambat dari waktu yang dijadwalkan (>10 menit).';
    }
    return 'Petugas terlambat memulai patroli lebih dari 10 menit dari jadwal.';
  } else if (timeliness?.toLowerCase() == 'pastDue') {
    return 'Patroli tidak diselesaikan dalam rentang waktu yang ditentukan.';
  }
  return 'Status ketepatan waktu tidak tersedia.';
}
