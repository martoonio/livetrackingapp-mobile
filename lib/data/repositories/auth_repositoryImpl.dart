import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:livetrackingapp/notification_utils.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  AuthRepositoryImpl({
    firebase_auth.FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  @override
  Future<User> login(String email, String password) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Login failed: No user returned');
      }

      // Check if user profile exists
      final docSnapshot =
          await _firestore.collection('users').doc(credential.user!.uid).get();

      User user;
      if (!docSnapshot.exists) {
        // Return basic user info if profile doesn't exist
        user = User(
          id: credential.user!.uid,
          email: credential.user!.email!,
          name: '',
          role: '',
        );
      } else {
        // Convert and return full user profile
        final userData = docSnapshot.data()!;
        user = User(
          id: credential.user!.uid,
          email: credential.user!.email!,
          name: userData['name'] as String? ?? '',
          role: userData['role'] as String? ?? '',
        );
      }

      // Execute getFirebaseMessagingToken to save push token
      await getFirebaseMessagingToken(user);

      return user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      // Melempar exception dengan kode error dari Firebase agar bisa digunakan oleh bloc
      throw Exception('${e.code}: ${e.message}');
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  @override
  Future<bool> checkUserProfile(String userId) async {
    try {
      final docSnapshot =
          await _firestore.collection('users').doc(userId).get();

      if (!docSnapshot.exists) return false;

      final userData = docSnapshot.data();
      final isNameExist =
          userData?['name'] != null && (userData!['name'] as String).isNotEmpty;
      return isNameExist;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<User> createUserProfile({
    required String name,
    required String role,
  }) async {
    try {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      final userData = {
        'name': name,
        'role': role,
        'email': currentUser.email,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(currentUser.uid).set(userData);

      return User(
        id: currentUser.uid,
        email: currentUser.email!,
        name: name,
        role: role,
      );
    } catch (e) {
      throw Exception('Failed to create profile: $e');
    }
  }

  @override
  Future<void> updateUserProfile(
      String userId, String name, String role) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'name': name,
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  @override
  Future<void> removePushToken(String userId) async {
    try {
      // Cek apakah user ada di database
      final docSnapshot =
          await _firestore.collection('users').doc(userId).get();

      if (!docSnapshot.exists) {
        return;
      }

      // Hapus push_token dari database
      await _firestore.collection('users').doc(userId).update({
        'push_token': FieldValue.delete(),
      });

      // Unsubscribe dari FCM topic untuk user ini
      await _firebaseMessaging.unsubscribeFromTopic('user_$userId');
    } catch (e) {
      // Tidak throw exception karena ini tidak boleh mengganggu proses logout
    }
  }

  @override
  Future<void> logout({String? userId}) async {
    try {
      // Dapatkan userId saat ini jika tidak diberikan
      final currentUserId = userId ?? _firebaseAuth.currentUser?.uid;

      // Hapus push token jika userId tersedia
      if (currentUserId != null) {
        try {
          await removePushToken(currentUserId);
        } catch (tokenError) {
          // Log error tapi jangan gagalkan proses logout
        }
      }

      // Lakukan logout dari Firebase Auth
      await _firebaseAuth.signOut();
    } catch (e) {
      // Masih throw exception agar bisa ditangani di bloc
      throw Exception('Logout failed: $e');
    }
  }

  @override
  Future<User?> getCurrentUser() async {
    try {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) return null;

      final docSnapshot =
          await _firestore.collection('users').doc(currentUser.uid).get();

      if (!docSnapshot.exists) {
        return User(
          id: currentUser.uid,
          email: currentUser.email!,
          name: '',
          role: '',
        );
      }

      final userData = docSnapshot.data()!;
      return User(
        id: currentUser.uid,
        email: currentUser.email!,
        name: userData['name'] as String? ?? '',
        role: userData['role'] as String? ?? '',
      );
    } catch (e) {
      return null;
    }
  }
}
