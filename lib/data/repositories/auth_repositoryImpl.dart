import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_database/firebase_database.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  AuthRepositoryImpl({
    firebase_auth.FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  @override
  Future<User> login(String email, String password) async {
    try {
      print('Attempting login...');
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Firebase auth successful');
      print('User UID: ${credential.user?.uid}');

      if (credential.user == null) {
        throw Exception('Login failed: No user returned');
      }

      // final snapshot = await _database.child('users').child(credential.user!.uid).get();
      // final userData = Map<String, dynamic>.from(snapshot.value as Map);

      return User(
        id: credential.user!.uid,
        email: credential.user!.email!,
        // name: userData['name'] as String,
        // role: userData['role'] as String,
      );
    } catch (e) {
      print('Login error in repository: $e');
      throw Exception('Login failed: ${e.toString()}');
    }
  }

// Add method to update user profile
  @override
  Future<void> updateUserProfile(
      String userId, String name, String role) async {
    await _database.child('users').child(userId).update({
      'name': name,
      'role': role,
    });
  }

  @override
  Future<void> logout() async {
    await _firebaseAuth.signOut();
  }

  @override
  Future<User?> getCurrentUser() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) return null;

    // final snapshot =
    //     await _database.child('users').child(currentUser.uid).get();

    // if (!snapshot.exists) return null;

    // final userData = Map<String, dynamic>.from(snapshot.value as Map);

    return User(
      id: currentUser.uid,
      email: currentUser.email!,
      // name: userData['name'] as String,
      // role: userData['role'] as String,
    );
  }
}
