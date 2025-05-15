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
  AuthError(this.message);
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
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await repository.logout();
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
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
