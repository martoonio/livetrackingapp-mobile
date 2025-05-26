import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/entities/user.dart';

// Events
abstract class AuthEvent {}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;

  LoginRequested({required this.email, required this.password});
}

class CompleteProfile extends AuthEvent {
  final String name;
  final String role;

  CompleteProfile({
    required this.name,
    required this.role,
  });
}

class LogoutRequested extends AuthEvent {}

class CheckAuthStatus extends AuthEvent {}

// States
abstract class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;
  AuthAuthenticated(this.user);
}

class AuthNeedsProfile extends AuthState {
  final String email;
  
  AuthNeedsProfile(this.email);
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  final String code;
  
  AuthError(this.message, {this.code = 'unknown_error'});
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository repository;

  AuthBloc({required this.repository}) : super(AuthInitial()) {
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<CompleteProfile>(_onCompleteProfile);
  }
  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    print('Login event received');
    emit(AuthLoading());

    try {
      final user = await repository.login(event.email, event.password);
      print('Repository returned user: ${user.email}');

      // Check if user profile exists in Firestore
      final hasProfile = await repository.checkUserProfile(user.id);
      
      if (!hasProfile) {
        print('User needs to complete profile');
        emit(AuthNeedsProfile(user.email));
        return;
      }

      print('Emitting AuthAuthenticated state');
      emit(AuthAuthenticated(user));
    } catch (e) {
      print('Login error in bloc: $e');
      
      // Parse error message to identify specific error types
      final errorString = e.toString().toLowerCase();
      String errorMessage;
      String errorCode;
      
      if (errorString.contains('user-not-found') || 
          errorString.contains('no user record')) {
        errorMessage = 'Email tidak terdaftar dalam sistem. Silakan hubungi admin untuk pendaftaran.';
        errorCode = 'user-not-found';
      } 
      else if (errorString.contains('wrong-password') || 
               errorString.contains('invalid-credential')) {
        errorMessage = 'Password yang Anda masukkan salah. Silakan coba lagi.';
        errorCode = 'wrong-password';
      }
      else if (errorString.contains('invalid-email')) {
        errorMessage = 'Format email tidak valid. Harap periksa kembali.';
        errorCode = 'invalid-email';
      }
      else if (errorString.contains('user-disabled')) {
        errorMessage = 'Akun Anda telah dinonaktifkan. Silakan hubungi admin.';
        errorCode = 'user-disabled';
      }
      else if (errorString.contains('too-many-requests')) {
        errorMessage = 'Terlalu banyak percobaan login yang gagal. Silakan coba lagi nanti.';
        errorCode = 'too-many-requests';
      }
      else if (errorString.contains('network-request-failed') || 
               errorString.contains('network error')) {
        errorMessage = 'Gagal terhubung ke server. Periksa koneksi internet Anda.';
        errorCode = 'network-error';
      }
      else {
        errorMessage = 'Terjadi kesalahan saat login. Silakan coba lagi.';
        errorCode = 'unknown-error';
      }
      
      emit(AuthError(errorMessage, code: errorCode));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      // Ambil user ID dari state saat ini
      String? userId;
      if (state is AuthAuthenticated) {
        userId = (state as AuthAuthenticated).user.id;
        print('Logging out user with ID: $userId');
      } else {
        print('No authenticated user found in state');
      }
      
      // Panggil logout dengan userId
      await repository.logout(userId: userId);
      
      // Penting: Selalu emit state ini, bahkan jika terjadi error
      emit(AuthUnauthenticated());
    } catch (e) {
      print('Error during logout in bloc: $e');
      
      // Jangan sampai error mengganggu proses logout
      // Tetap emit AuthUnauthenticated meskipun gagal menghapus token
      print('Proceeding with logout despite error');
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    // Don't emit loading for initial check
    try {
      final user = await repository.getCurrentUser();
      print('Check auth status result: ${user?.email}'); // Debug print
      if (user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      print('Check auth status error: $e'); // Debug print
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onCompleteProfile(
    CompleteProfile event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(AuthLoading());
      
      final user = await repository.createUserProfile(
        name: event.name,
        role: event.role,
      );

      emit(AuthAuthenticated(user));
    } catch (e) {
      print('Error completing profile: $e');
      emit(AuthError('Failed to complete profile: $e'));
    }
  }
}
