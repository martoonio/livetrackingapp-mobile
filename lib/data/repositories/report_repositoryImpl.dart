import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import '../../domain/entities/report.dart';
import '../../domain/repositories/report_repository.dart';

class ReportRepositoryImpl implements ReportRepository {
  final FirebaseStorage firebaseStorage;
  final DatabaseReference databaseReference;
  final Box<dynamic> _offlineReportsBox;

  ReportRepositoryImpl({
    required this.firebaseStorage,
    required this.databaseReference,
    required Box<dynamic> offlineReportsBox,
  }) : _offlineReportsBox = offlineReportsBox;

  // Cek koneksi internet
  Future<bool> _isConnected() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  @override
  Future<void> createReport(Report report) async {
    try {
      // Cek koneksi internet
      if (!await _isConnected()) {
        // Jika offline, simpan laporan ke penyimpanan lokal
        await saveOfflineReport(report);
        return;
      }

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
        'officerName': report.officerName,
        'clusterName': report.clusterName,
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

  @override
  Future<void> saveOfflineReport(Report report) async {
    try {
      print('Saving offline report: ${report.id}');

      // Simpan report ke box Hive
      await _offlineReportsBox.put(
        'report_${report.id}',
        {
          'id': report.id,
          'data': json.encode(report.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      print('Report saved to offline storage: ${report.id}');
    } catch (e) {
      print('Error saving offline report: $e');
      throw Exception('Failed to save offline report: $e');
    }
  }

  @override
  Future<List<Report>> getOfflineReports() async {
    try {
      final List<Report> reports = [];

      // Filter key yang dimulai dengan 'report_'
      final reportKeys = _offlineReportsBox.keys
          .where((key) => key.toString().startsWith('report_'))
          .toList();

      for (final key in reportKeys) {
        final data = _offlineReportsBox.get(key);
        if (data != null && data is Map) {
          final reportId = data['id'] as String;
          final reportJson = json.decode(data['data'] as String)
              as Map<String, dynamic>;

          // Buat objek Report
          final report = Report.fromJson(reportId, reportJson);
          reports.add(report.copyWith(isSynced: false));
        }
      }

      return reports;
    } catch (e) {
      print('Error getting offline reports: $e');
      return [];
    }
  }

  @override
  Future<void> syncOfflineReports() async {
    try {
      if (!await _isConnected()) {
        print('Cannot sync reports: Device is offline');
        return;
      }

      final reports = await getOfflineReports();
      if (reports.isEmpty) {
        print('No offline reports to sync');
        return;
      }

      print('Found ${reports.length} offline reports to sync');

      for (final report in reports) {
        try {
          // Panggil createReport dengan report dari offline storage
          // tapi dengan flag isSynced diubah jadi true
          await createReport(report.copyWith(isSynced: true));

          // Hapus dari penyimpanan offline setelah berhasil disinkronkan
          await deleteOfflineReport(report.id);

          print('Synced and deleted offline report: ${report.id}');
        } catch (e) {
          print('Error syncing report ${report.id}: $e');
          // Lanjutkan ke report berikutnya jika gagal
        }
      }

      print('Finished syncing offline reports');
    } catch (e) {
      print('Error syncing offline reports: $e');
      throw Exception('Failed to sync offline reports: $e');
    }
  }

  @override
  Future<void> deleteOfflineReport(String id) async {
    try {
      await _offlineReportsBox.delete('report_$id');
      print('Deleted offline report: $id');
    } catch (e) {
      print('Error deleting offline report: $e');
      throw Exception('Failed to delete offline report: $e');
    }
  }
}
