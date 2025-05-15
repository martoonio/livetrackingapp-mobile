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
      // Upload photo to Firebase Storage
      final photoRef =
          firebaseStorage.ref().child('reports/${report.id}/photo.jpg');
      final uploadTask = await photoRef.putFile(File(report.photoUrl));
      final photoUrl = await uploadTask.ref.getDownloadURL();

      // Save report to Firebase Realtime Database
      await databaseReference.child('reports').child(report.id).set({
        'title': report.title,
        'description': report.description,
        'photoUrl': photoUrl,
        'timestamp': report.timestamp.toIso8601String(),
        'latitude': report.latitude,
        'longitude': report.longitude,
        'taskId': report.taskId, // Tambahkan taskId
      });
      print('Report created successfully with ID: ${report.id}');
    } catch (e) {
      throw Exception('Failed to create report: $e');
    }
  }
}
