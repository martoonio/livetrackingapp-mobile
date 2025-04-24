import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
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

      // Check if user profile exists
      final snapshot = await _database.child('users').child(credential.user!.uid).get();
      
      if (!snapshot.exists) {
        // Return basic user info if profile doesn't exist
        return User(
          id: credential.user!.uid,
          email: credential.user!.email!,
          name: '',
          role: '',
        );
      }

      // Convert and return full user profile
      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      return User(
        id: credential.user!.uid,
        email: credential.user!.email!,
        name: userData['name'] as String? ?? '',
        role: userData['role'] as String? ?? '',
      );
    } catch (e) {
      print('Login error in repository: $e');
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  @override
  Future<bool> checkUserProfile(String userId) async {
    try {
      final snapshot = await _database.child('users').child(userId).get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking user profile: $e');
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
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _database.child('users').child(currentUser.uid).set(userData);

      return User(
        id: currentUser.uid,
        email: currentUser.email!,
        name: name,
        role: role,
      );
    } catch (e) {
      print('Error creating user profile: $e');
      throw Exception('Failed to create profile: $e');
    }
  }

  @override
  Future<void> updateUserProfile(String userId, String name, String role) async {
    try {
      await _database.child('users').child(userId).update({
        'name': name,
        'role': role,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error updating user profile: $e');
      throw Exception('Failed to update profile: $e');
    }
  }

  @override
  Future<void> logout() async {
    await _firebaseAuth.signOut();
    User user = User(
      id: '',
      email: '',
      name: '',
      role: '',
    );
  }

  @override
  Future<User?> getCurrentUser() async {
    try {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) return null;

      final snapshot = await _database.child('users').child(currentUser.uid).get();

      if (!snapshot.exists) {
        return User(
          id: currentUser.uid,
          email: currentUser.email!,
          name: '',
          role: '',
        );
      }

      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      return User(
        id: currentUser.uid,
        email: currentUser.email!,
        name: userData['name'] as String? ?? '',
        role: userData['role'] as String? ?? '',
      );
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }
}