import '../entities/user.dart';

abstract class AuthRepository {
  Future<User> login(String email, String password);
  
  Future<void> logout({String? userId});
  
  Future<User?> getCurrentUser();
  Future<void> updateUserProfile(String userId, String name, String role);
  Future<bool> checkUserProfile(String userId);
  Future<User> createUserProfile({
    required String name,
    required String role,
  });
  
  Future<void> removePushToken(String userId);
}
