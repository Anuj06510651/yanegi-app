import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'user_service.dart';
import '../utils/error_handler.dart';

class GoogleSignInFlowResult {
  const GoogleSignInFlowResult({
    required this.user,
    required this.hasExistingProfile,
  });

  final User user;
  final bool hasExistingProfile;
}

class EmailOtpVerificationResult {
  const EmailOtpVerificationResult({
    required this.credential,
    required this.isNewUser,
  });

  final UserCredential credential;
  final bool isNewUser;
}

class EmailOtpFailure implements Exception {
  EmailOtpFailure(this.message, {required this.code, this.lockedUntil});

  final String message;
  final String code;
  final int? lockedUntil;

  @override
  String toString() => message;
}

class AuthFlowService {
  AuthFlowService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuthService? authService,
  })  : _authOverride = auth,
        _firestoreOverride = firestore,
        _authServiceOverride = authService;

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;
  AuthService? _authServiceOverride;
  UserService? _userServiceOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  AuthService get _authService => _authServiceOverride ??= AuthService();
  UserService get _userService => _userServiceOverride ??= UserService(
        firestore: _firestore,
        auth: _auth,
      );

  static Future<GoogleSignInFlowResult?>? _activeGoogleSignInFlow;
  static Future<void>? _activeEmailOtpSend;

  static const String _functionsBaseUrl = String.fromEnvironment(
    'YANEGI_FUNCTIONS_BASE_URL',
    defaultValue: 'https://us-central1-yanegi-684f9.cloudfunctions.net',
  );
  static const Duration _otpVerifyTimeout = Duration(seconds: 60);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  Future<GoogleSignInFlowResult?> continueWithGoogle() {
    final activeFlow = _activeGoogleSignInFlow;
    if (activeFlow != null) {
      // ignore: avoid_print
      print('Google sign-in already in progress; reusing active flow.');
      return activeFlow;
    }

    final flow = _continueWithGoogleInternal();
    _activeGoogleSignInFlow = flow;
    return flow.whenComplete(() {
      if (identical(_activeGoogleSignInFlow, flow)) {
        _activeGoogleSignInFlow = null;
      }
    });
  }

  Future<GoogleSignInFlowResult?> _continueWithGoogleInternal() async {
    debugPrint('AUTH FLOW STEP 7: Google sign-in starting');
    final credential = await _authService.signInWithGoogle();
    final user = credential?.user ?? _auth.currentUser;
    debugPrint('AUTH FLOW STEP 8: Firebase Auth result — uid=${user?.uid}');
    if (user == null) return null;

    final uid = user.uid;
    final email = _normalizeEmail(user.email);
    bool hasExistingProfile = false;

    // Firestore setup is best-effort. If it fails, Firebase Auth has already
    // succeeded — bootstrap will create the user doc on the next rebootstrap().
    // Never throw here after a successful Auth sign-in; doing so prevents
    // rebootstrap() from being called and leaves the user stuck.
    try {
      debugPrint('AUTH FLOW STEP 9: setting up Firestore profile uid=$uid');
      await _userService.createOrGetUser(
        uid: uid,
        email: email,
        authProvider: 'google',
      );

      final userDoc = await _users.doc(uid).get();
      final data = userDoc.data();
      hasExistingProfile = userDoc.exists && data?['hasCompletedProfile'] == true;
      debugPrint('AUTH FLOW STEP 9: hasExistingProfile=$hasExistingProfile');

      // Identity isolation: never seed the user doc from the Google profile.
      // The avatar/banner MUST come from Yanegi storage uploads done in
      // onboarding or settings. Reading user.photoURL or user.displayName
      // here would leak the user's Google account identity into other
      // users' chats / activity / profile views.
      final payload = <String, dynamic>{
        'email': email,
        'authProvider': 'google',
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await _users.doc(uid).set(payload, SetOptions(merge: true));
      await _userService.syncAuthContactFields();
      await _userService.refreshCurrentUserProfile();
      debugPrint('AUTH FLOW STEP 9: Firestore setup complete');
    } catch (e, st) {
      // Non-fatal: Firestore setup failed after successful Firebase Auth.
      // Bootstrap will create/fix the user doc when rebootstrap() triggers
      // _resolveStartup(). Do NOT rethrow — caller must reach rebootstrap().
      debugPrint('AUTH FLOW STEP 9: Firestore setup error (non-fatal): $e');
      debugPrintStack(stackTrace: st);
    }

    return GoogleSignInFlowResult(
      user: user,
      hasExistingProfile: hasExistingProfile,
    );
  }

  Future<void> setPasswordForCurrentUser(String password) async {
    throw StateError(
      'Password sign-in is no longer supported. Please use email OTP or Google sign-in.',
    );
  }

  Future<void> sendEmailOtp(String email) {
    final normalizedEmail = _normalizeEmail(email);
    if (!_isValidEmail(normalizedEmail)) {
      throw StateError('Please enter a valid email address.');
    }

    final activeSend = _activeEmailOtpSend;
    if (activeSend != null) return activeSend;

    final flow = _postOtpRequest(
      path: 'sendOtp',
      body: {'email': normalizedEmail},
    );
    _activeEmailOtpSend = flow;
    return flow.whenComplete(() {
      if (identical(_activeEmailOtpSend, flow)) {
        _activeEmailOtpSend = null;
      }
    });
  }

  Future<EmailOtpVerificationResult> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedOtp = otp.trim();
    if (!_isValidEmail(normalizedEmail)) {
      throw StateError('Please enter a valid email address.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedOtp)) {
      throw StateError('Enter the 6-digit code.');
    }

    final uri = _functionUri('verifyOtp');
    Map<String, dynamic> data = const <String, dynamic>{};
    const maxVerifyAttempts = 2;
    for (var attempt = 1; attempt <= maxVerifyAttempts; attempt++) {
      try {
        // ignore: avoid_print
        print('OTP verify started (attempt $attempt/$maxVerifyAttempts)');
        final response = await http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': normalizedEmail,
                'otp': normalizedOtp,
              }),
            )
            .timeout(
              _otpVerifyTimeout,
              onTimeout: () => throw TimeoutException('Request timeout'),
            );
        // ignore: avoid_print
        print('API response received');

        data = _decodeJsonResponse(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final message = _errorMessageFromResponse(data);
          final code = _errorCodeFromResponse(data);
          final lockedUntil = _lockedUntilFromResponse(data);
          throw EmailOtpFailure(message, code: code, lockedUntil: lockedUntil);
        }
        break;
      } on TimeoutException catch (e) {
        // ignore: avoid_print
        print('Error occurred: timeout - $e');
        if (attempt == maxVerifyAttempts) {
          throw EmailOtpFailure('Request timed out', code: 'NETWORK_ERROR');
        }
      } on FormatException catch (e) {
        // ignore: avoid_print
        print('Error occurred: format - $e');
        if (attempt == maxVerifyAttempts) {
          throw EmailOtpFailure('Invalid response from server.',
              code: 'NETWORK_ERROR');
        }
      } on http.ClientException catch (e) {
        // ignore: avoid_print
        print('Error occurred: client exception - $e');
        if (attempt == maxVerifyAttempts) {
          throw EmailOtpFailure('Network issue. Try again.',
              code: 'NETWORK_ERROR');
        }
      } on EmailOtpFailure catch (e) {
        final message = e.message.toLowerCase();
        final shouldRetry = e.code == 'NETWORK_ERROR' ||
            e.code == 'UNKNOWN_ERROR' ||
            message.contains('internal error');
        if (!shouldRetry || attempt == maxVerifyAttempts) {
          rethrow;
        }
      } on StateError catch (e) {
        // preserve StateError (used for input validation earlier)
        // ignore: avoid_print
        print('StateError thrown: $e');
        rethrow;
      } catch (e, stack) {
        // ignore: avoid_print
        print('❌ SIGN-IN UNKNOWN ERROR: $e');
        print(stack);
        if (attempt == maxVerifyAttempts) {
          // Surface as EmailOtpFailure so UI can handle it gracefully.
          throw EmailOtpFailure('Something went wrong. Please try again.',
              code: 'UNKNOWN_ERROR');
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    final token = (data['token'] as String?)?.trim();
    final hasToken = token != null && token.isNotEmpty;
    print('TOKEN LENGTH: ${token?.length}');
    print(
        'TOKEN START: ${token != null && token.length > 20 ? token.substring(0, 20) : token}');
    final success = data['success'] == true;
    final isNewUserRaw = data['isNewUser'];
    final isNewUser = isNewUserRaw is bool ? isNewUserRaw : false;
    if (!success && !hasToken) {
      // ignore: avoid_print
      print('API reported success=false; failing with server error');
      final message = _errorMessageFromResponse(data);
      final code = _errorCodeFromResponse(data);
      final lockedUntil = _lockedUntilFromResponse(data);
      throw EmailOtpFailure(message, code: code, lockedUntil: lockedUntil);
    }
    if (isNewUserRaw is! bool && !hasToken) {
      // ignore: avoid_print
      print('Invalid response: isNewUser missing or not boolean');
      throw EmailOtpFailure('Invalid response from server.',
          code: 'INVALID_RESPONSE');
    }
    if (!hasToken) {
      // ignore: avoid_print
      print('Missing token in response after successful verify');
      throw EmailOtpFailure('OTP verification did not return a sign-in token.',
          code: 'INVALID_RESPONSE');
    }
    if (!success && hasToken) {
      // ignore: avoid_print
      print('API reported success=false but token present; proceeding.');
    }
    // ignore: avoid_print
    print('Token received');

    late final UserCredential credential;
    const maxSignInAttempts = 2;
    for (var attempt = 1; attempt <= maxSignInAttempts; attempt++) {
      try {
        // ignore: avoid_print
        print('TOKEN RECEIVED: $token');
        credential = await _auth
            .signInWithCustomToken(token)
            .timeout(_otpVerifyTimeout, onTimeout: () {
          throw TimeoutException('Request timeout');
        });
        // ignore: avoid_print
        print('SIGN IN SUCCESS: ${credential.user?.uid}');
        break;
      } on TimeoutException {
        // ignore: avoid_print
        print('SIGN IN ERROR: Request timed out while signing in.');
        if (attempt == maxSignInAttempts) {
          throw EmailOtpFailure('Request timed out while signing in.',
              code: 'NETWORK_ERROR');
        }
      } on FirebaseAuthException catch (e, stack) {
        // ignore: avoid_print
        print('SIGN IN ERROR: $e');
        print(stack);
        if ((e.code == 'internal-error' ||
                e.code == 'network-request-failed') &&
            attempt < maxSignInAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
        switch (e.code) {
          case 'invalid-custom-token':
            throw EmailOtpFailure('Invalid sign-in token.',
                code: 'INVALID_TOKEN');
          case 'custom-token-mismatch':
            throw EmailOtpFailure('Sign-in token mismatch.',
                code: 'INVALID_TOKEN');
          default:
            throw EmailOtpFailure(
                ErrorHandler.messageFor(AppErrorType.authGeneric),
                code: 'AUTH_ERROR');
        }
      } catch (e, stack) {
        // ignore: avoid_print
        print('SIGN IN ERROR: $e');
        print(stack);
        if (attempt == maxSignInAttempts) {
          throw EmailOtpFailure('Something went wrong while signing in.',
              code: 'UNKNOWN_ERROR');
        }
      }
    }
    final user = credential.user ?? _auth.currentUser;
    if (user == null) {
      // ignore: avoid_print
      print('Error occurred');
      throw StateError('Unable to sign in with the verified email.');
    }
    // ignore: avoid_print
    print('✅ SIGN-IN SUCCESS UID: ${user.uid}');
    try {
      await (() async {
        await _userService.createOrGetUser(
          uid: user.uid,
          email: normalizedEmail,
          authProvider: 'email_otp',
        );
        await _userService.syncAuthContactFields();
        await _userService.refreshCurrentUserProfile();
      })()
          .timeout(_otpVerifyTimeout, onTimeout: () {
        throw TimeoutException('Request timeout');
      });
    } on TimeoutException {
      // ignore: avoid_print
      print('Error occurred while refreshing/creating user: timeout');
      // Allow sign-in to proceed even if profile sync timed out.
    } catch (e, stack) {
      // ignore: avoid_print
      print('❌ UNKNOWN ERROR while creating/syncing user: $e');
      print(stack);
      // Do not block sign-in if profile sync fails; onboarding can recover.
    }

    return EmailOtpVerificationResult(
      credential: credential,
      isNewUser: isNewUser,
    );
  }

  Future<bool> isUsernameAvailable(
    String username, {
    String? exceptUserId,
  }) async {
    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty) return false;

    final usernameDoc = await _usernames.doc(normalized).get();
    if (!usernameDoc.exists) return true;

    final claimedBy = (usernameDoc.data()?['userId'] as String?) ?? '';
    if (exceptUserId != null && claimedBy == exceptUserId) {
      return true;
    }

    return false;
  }

  Future<void> completeProfile({
    required String name,
    required String username,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    final trimmedName = name.trim();
    final normalizedUsername = _normalizeUsername(username);

    if (trimmedName.isEmpty || normalizedUsername.isEmpty) {
      throw StateError('Name and username are required.');
    }

    final normalizedEmail = _normalizeEmail(user.email);
    if (normalizedEmail.isNotEmpty) {
      // Best-effort uniqueness pre-check. Firebase Auth itself enforces
      // single-provider email uniqueness atomically; this query catches the
      // rarer multi-provider case (e.g. a Google-linked account and an
      // Email-OTP account sharing the same address). Firestore transactions
      // cannot run queries, so true transactional enforcement requires an
      // `email_claims/{normalizedEmail}` lookup collection — scheduled for
      // Stage 2 alongside the server-side counter migration.
      final emailQuery = await _users
          .where('email', isEqualTo: normalizedEmail)
          .limit(5)
          .get();
      final hasDuplicate = emailQuery.docs.any((d) => d.id != user.uid);
      if (hasDuplicate) {
        throw StateError(
            'Duplicate account detected for this email. Please login instead.');
      }
    }

    final userRef = _users.doc(user.uid);
    final usernameRef = _usernames.doc(normalizedUsername);

    final preExistingUserDoc = await userRef.get();
    final preExistingData = preExistingUserDoc.data();
    final alreadyCompleted = preExistingUserDoc.exists &&
        preExistingData?['hasCompletedProfile'] == true;
    if (alreadyCompleted) {
      return;
    }

    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final usernameSnapshot = await transaction.get(usernameRef);

      final claimedBy = (usernameSnapshot.data()?['userId'] as String?) ?? '';
      if (usernameSnapshot.exists && claimedBy != user.uid) {
        throw StateError('Username already taken. Please choose another.');
      }

      final existingUserData = userSnapshot.data() ?? const <String, dynamic>{};
      final previousUsername =
          _normalizeUsername((existingUserData['username'] as String?) ?? '');

      if (previousUsername.isNotEmpty &&
          previousUsername != normalizedUsername) {
        final oldUsernameRef = _usernames.doc(previousUsername);
        final oldUsernameSnapshot = await transaction.get(oldUsernameRef);
        final oldClaimedBy =
            (oldUsernameSnapshot.data()?['userId'] as String?) ?? '';
        if (oldUsernameSnapshot.exists && oldClaimedBy == user.uid) {
          transaction.delete(oldUsernameRef);
        }
      }

      transaction.set(
        usernameRef,
        {
          'userId': user.uid,
          'username': normalizedUsername,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': usernameSnapshot.exists
              ? (usernameSnapshot.data()?['createdAt'] ??
                  FieldValue.serverTimestamp())
              : FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Only write fields that are actually changing at step 1.
      // userId, uid, createdAt are already set by createOrGetUser and are
      // NOT in the update allowlist — re-writing them causes PERMISSION_DENIED.
      final Map<String, dynamic> userUpdatePayload = {
        'name': trimmedName,
        'username': normalizedUsername,
        'usernameLower': normalizedUsername,
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (normalizedEmail.isNotEmpty) {
        userUpdatePayload['email'] = normalizedEmail;
      }
      transaction.update(userRef, userUpdatePayload);
    });
  }

  Future<UserCredential> loginWithIdentifierAndPassword({
    required String identifier,
    required String password,
  }) async {
    throw StateError(
      'Password sign-in is no longer supported. Please use email OTP or Google sign-in.',
    );
  }

  Future<void> sendPasswordResetForIdentifier(String identifier) async {
    throw StateError(
      'Password reset is no longer available. Please use email OTP instead.',
    );
  }

  Future<void> signOut() => _authService.signOut();

  Future<void> _postOtpRequest({
    required String path,
    required Map<String, String> body,
  }) async {
    final response = await http.post(
      _functionUri(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = _decodeJsonResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _errorMessageFromResponse(data);
      final code = _errorCodeFromResponse(data);
      throw EmailOtpFailure(message, code: code);
    }
  }

  Uri _functionUri(String path) {
    final base = _functionsBaseUrl.endsWith('/')
        ? _functionsBaseUrl.substring(0, _functionsBaseUrl.length - 1)
        : _functionsBaseUrl;
    return Uri.parse('$base/$path');
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    if (response.body.trim().isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  String _errorMessageFromResponse(Map<String, dynamic> data) {
    final message = data['error'] ?? data['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    return 'Authentication failed. Please try again.';
  }

  String _errorCodeFromResponse(Map<String, dynamic> data) {
    final code = data['code'];
    if (code is String && code.trim().isNotEmpty) {
      return code.trim();
    }
    return 'NETWORK_ERROR';
  }

  int? _lockedUntilFromResponse(Map<String, dynamic> data) {
    final value = data['lockedUntil'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Maps an arbitrary [error] to a user-facing string. Never returns raw
  /// exception or Firebase code text — unknown failures fall back to the
  /// centralized [ErrorHandler] friendly message.
  String toFriendlyError(Object error) {
    // EmailOtpFailure messages are app-defined, user-friendly strings.
    if (error is EmailOtpFailure) return error.message;

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'user-not-found':
          return ErrorHandler.messageFor(AppErrorType.authWrongPassword);
        case 'invalid-action-code':
        case 'expired-action-code':
        case 'invalid-verification-code':
        case 'invalid-verification-id':
          return ErrorHandler.messageFor(AppErrorType.authOtpInvalid);
        case 'network-request-failed':
          return ErrorHandler.messageFor(AppErrorType.network);
        case 'email-already-in-use':
          return ErrorHandler.messageFor(AppErrorType.authEmailInUse);
        case 'weak-password':
          return ErrorHandler.messageFor(AppErrorType.authWeakPassword);
        case 'too-many-requests':
          return ErrorHandler.messageFor(AppErrorType.rateLimited);
        case 'invalid-email':
          return ErrorHandler.messageFor(AppErrorType.authInvalidEmail);
        case 'requires-recent-login':
          return ErrorHandler.messageFor(AppErrorType.authRequiresRecentLogin);
        default:
          return ErrorHandler.messageFor(AppErrorType.authGeneric);
      }
    }

    return ErrorHandler.friendlyMessage(
      error,
      fallback: AppErrorType.authGeneric,
      where: 'auth_flow_service.toFriendlyError',
    );
  }

  String _normalizeEmail(String? email) => (email ?? '').trim().toLowerCase();

  String _normalizeUsername(String username) {
    var normalized = username.trim().toLowerCase();
    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  bool _isValidEmail(String input) {
    final value = input.trim();
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(value);
  }
}
