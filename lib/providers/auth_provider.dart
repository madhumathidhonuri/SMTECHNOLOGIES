import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/crashlytics/crash_reporter.dart';
import '../core/network/api_exception.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';
import 'core_providers.dart';
import 'fleet_provider.dart';

enum AuthStage { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.stage = AuthStage.unknown,
    this.user,
    this.isBusy = false,
    this.error,
    this.fieldErrors = const <String, String>{},
  });

  final AuthStage stage;
  final AppUser? user;
  final bool isBusy;
  final String? error;
  final Map<String, String> fieldErrors;

  bool get isAuthenticated => stage == AuthStage.authenticated && user != null;

  AuthState copyWith({
    AuthStage? stage,
    AppUser? user,
    bool? isBusy,
    String? error,
    Map<String, String>? fieldErrors,
    bool clearError = false,
    bool clearUser = false,
  }) =>
      AuthState(
        stage: stage ?? this.stage,
        user: clearUser ? null : (user ?? this.user),
        isBusy: isBusy ?? this.isBusy,
        error: clearError ? null : (error ?? this.error),
        fieldErrors: fieldErrors ?? (clearError ? const <String, String>{} : this.fieldErrors),
      );
}

final NotifierProvider<AuthController, AuthState> authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Any hard 401 anywhere in the app lands here.
    ref.listen<int>(sessionExpiredTickProvider, (int? _, int __) {
      if (state.stage != AuthStage.unauthenticated) {
        state = const AuthState(stage: AuthStage.unauthenticated);
      }
    });
    return const AuthState();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Cold-boot resolution: cached user renders instantly, then `/auth/me`
  /// confirms the token is still valid.
  Future<void> bootstrap() async {
    final bool hasToken = await _repo.hasToken();
    if (!hasToken) {
      state = const AuthState(stage: AuthStage.unauthenticated);
      return;
    }

    final AppUser? cached = await _repo.cachedUser();
    if (cached != null) {
      state = AuthState(stage: AuthStage.authenticated, user: cached);
    }

    try {
      final AppUser fresh = await _repo.me();
      state = AuthState(stage: AuthStage.authenticated, user: fresh);
      unawaited(_afterLogin(fresh));
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isForbidden) {
        await _repo.logout();
        state = AuthState(
          stage: AuthStage.unauthenticated,
          error: e.isForbidden ? e.message : null,
        );
      } else if (cached == null) {
        // Offline cold start with no cache — cannot verify, so stay out.
        state = AuthState(stage: AuthStage.unauthenticated, error: e.message);
      }
      // Offline *with* cache: keep the optimistic authenticated state.
    }
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final AppUser user =
          await _repo.login(identifier: identifier, password: password);
      state = AuthState(stage: AuthStage.authenticated, user: user);
      unawaited(_afterLogin(user));
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        error: e.message,
        fieldErrors: e.fieldErrors,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        error: 'An unexpected error occurred during login. Please try again.',
      );
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repo.forgotPassword(email);
      state = state.copyWith(isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    }
  }

  Future<bool> resetPassword({
    required String token,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repo.resetPassword(token: token, password: password);
      state = state.copyWith(isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    }
  }

  Future<bool> updateProfile({
    String? name,
    String? phone,
    String? timezone,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final AppUser u = await _repo.updateProfile(
        name: name,
        phone: phone,
        timezone: timezone,
      );
      state = state.copyWith(isBusy: false, user: u);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repo.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    }
  }

  Future<bool> requestAccountDeletion(String reason) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repo.requestAccountDeletion(reason: reason);
      state = state.copyWith(isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    }
  }

  Future<void> logout() async {
    // Tear down real-time + push before dropping the token.
    ref.read(socketServiceProvider).disconnect();
    
    // Clear fleet data to prevent data leak to next user
    ref.read(fleetProvider.notifier).clear();

    final String? orgId = state.user?.orgId;
    if (orgId != null && orgId.isNotEmpty) {
      // Push topic cleanup is best-effort and must not block logout.
      unawaited(Future<void>(() async {
        try {
          await ref.read(authRepositoryProvider).unregisterDevice(
                await ref.read(secureStoreProvider).readFcmToken() ?? '',
              );
          final FirebaseMessaging fcm = FirebaseMessaging.instance;
          await fcm.unsubscribeFromTopic('org_$orgId');
          await fcm.deleteToken();
        } catch (_) {}
      }));
    }

    await _repo.logout();
    // Clear user context so reports after logout are fully anonymous.
    unawaited(CrashReporter.clearUserContext());
    state = const AuthState(stage: AuthStage.unauthenticated);
  }

  /// Registers this device for push once a session exists.
  Future<void> _afterLogin(AppUser user) async {
    // Associate all subsequent Crashlytics reports with this user's internal ID.
    // We send only id + role — never name, email, or phone.
    unawaited(CrashReporter.setUserContext(user));
    try {
      final String? fcm = await ref.read(secureStoreProvider).readFcmToken();
      if (fcm != null && fcm.isNotEmpty) {
        await _repo.registerDevice(
          fcmToken: fcm,
          platform: defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        );
      }
    } catch (_) {/* never block the session on this */}
  }

  void clearError() => state = state.copyWith(clearError: true);
}
