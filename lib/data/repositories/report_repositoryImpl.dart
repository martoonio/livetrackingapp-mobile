import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:io';
import '../../domain/entities/report.dart';
import '../../domain/repositories/report_repository.dart';

class ReportRepositoryImpl implements ReportRepository {
  final FirebaseStorage firebaseStorage;
  final DatabaseReference databaseReference;

  ReportRepositoryImpl({
    required this.firebaseStorage,
    required this.databaseReference,
  });

  @override
  Future<void> createReport(Report report) async {
    try {
      print('Starting report creation: ${report.id}');

      // Buat daftar untuk menyimpan URL foto yang diupload
      final List<String> uploadedPhotoUrls = [];

      // Cek apakah ada beberapa foto (dipisahkan oleh koma)
      final photoPaths = report.photoUrl.split(',');

      print('Found ${photoPaths.length} photos to upload');

      // Upload setiap foto ke Firebase Storage
      for (int i = 0; i < photoPaths.length; i++) {
        final photoPath = photoPaths[i].trim();
        if (photoPath.isNotEmpty) {
          final photoFile = File(photoPath);

          // Cek apakah file ada sebelum upload
          if (!await photoFile.exists()) {
            print('File not found: $photoPath');
            continue;
          }

          final photoRef =
              firebaseStorage.ref().child('reports/${report.id}/photo_$i.jpg');

          // Tampilkan log untuk membantu debug
          print('Uploading file: $photoPath');

          // Upload foto dengan tracking progress
          try {
            final uploadTask = photoRef.putFile(
              photoFile,
              SettableMetadata(contentType: 'image/jpeg'),
            );

            // Tambahkan listener untuk memantau progress
            uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
              final progress = snapshot.bytesTransferred / snapshot.totalBytes;
              print(
                  'Upload progress for photo $i: ${(progress * 100).toStringAsFixed(1)}%');
            });

            // Tunggu hingga upload selesai
            await uploadTask;

            // Dapatkan URL download
            final downloadUrl = await photoRef.getDownloadURL();
            uploadedPhotoUrls.add(downloadUrl);
            print('Photo $i uploaded successfully: $downloadUrl');
          } catch (uploadError) {
            print('Error uploading photo $i: $uploadError');
            // Lanjutkan ke foto berikutnya daripada menggagalkan seluruh proses
          }
        }
      }

      // Gunakan URL pertama sebagai thumbnail atau gabungkan semua URL
      final finalPhotoUrl =
          uploadedPhotoUrls.isNotEmpty ? uploadedPhotoUrls.join(',') : '';

      print('Final photo URL: $finalPhotoUrl');
      print('All photos uploaded successfully, saving report data to database');

      // Format timestamp dengan benar
      final formattedTimestamp = report.timestamp.toIso8601String();

      // Data untuk disimpan ke database
      final reportData = {
        'title': report.title,
        'description': report.description,
        'photoUrl': finalPhotoUrl,
        'timestamp': formattedTimestamp,
        'latitude': report.latitude,
        'longitude': report.longitude,
        'taskId': report.taskId,
        'createdAt': ServerValue.timestamp, // Tambahkan timestamp server
        'userId': report.userId ?? '', // Pastikan userId selalu ada
        'clusterId': report.clusterId ?? '', // Tambahkan clusterId jika ada
      };

      // Hapus nilai null sebelum menulis ke database
      reportData.removeWhere((key, value) => value == null);

      // Gunakan transaction untuk memastikan penulisan berhasil
      await databaseReference.child('reports').child(report.id).set(reportData);

      print('Report created successfully with ID: ${report.id}');

      // Verifikasi report sudah tersimpan
      final snapshot =
          await databaseReference.child('reports').child(report.id).get();
      if (snapshot.exists) {
        print('Report verification successful - data exists in database');
      } else {
        throw Exception(
            'Report verification failed - data not found in database');
      }
    } catch (e) {
      print('Error in createReport: $e');
      throw Exception('Failed to create report: $e');
    }
  }
}
