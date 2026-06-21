import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignIn;

  GoogleSignIn _getGoogleSignInClient() {
    final existing = _googleSignIn;
    if (existing != null) return existing;

    if (kIsWeb) {
      const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
      _googleSignIn = webClientId.isNotEmpty
          ? GoogleSignIn(clientId: webClientId)
          : GoogleSignIn();
      return _googleSignIn!;
    }

    _googleSignIn = GoogleSignIn();
    return _googleSignIn!;
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        return await _signInWithGoogleOnWeb();
      }

      final googleSignIn = _getGoogleSignInClient();
      // Sign out first so the platform always shows the account chooser.
      // Without this, a cached Google session silently re-authenticates the
      // previous account instead of letting the user pick (Bug 3).
      await googleSignIn.signOut().catchError((_) async => null);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;

      final email = (googleUser.email).trim().toLowerCase();

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final currentUser = _auth.currentUser;
      UserCredential? result;

      if (currentUser != null && currentUser.isAnonymous) {
        try {
          result = await currentUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use') rethrow;
        }
      }

      if (result == null &&
          currentUser != null &&
          currentUser.email?.toLowerCase() == email &&
          !currentUser.providerData
              .any((provider) => provider.providerId == 'google.com')) {
        try {
          result = await currentUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use') rethrow;
        }
      }

      result ??= await _auth.signInWithCredential(credential);
      return result;
    } on FirebaseAuthException catch (e, st) {
      debugPrint(
          'Google sign-in FirebaseAuthException: ${e.code} ${e.message}');
      debugPrintStack(stackTrace: st);
      throw StateError(_friendlyGoogleError(e));
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      throw StateError(_friendlyGoogleError(e));
    }
  }

  Future<UserCredential?> _signInWithGoogleOnWeb() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    try {
      final result = await _auth.signInWithPopup(provider);
      return result;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-blocked') {
        await _auth.signInWithRedirect(provider);
        return null;
      }
      rethrow;
    }
  }

  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onVerificationFailed,
    void Function(UserCredential credential)? onAutoVerified,
  }) async {
    throw StateError('Phone sign-in is no longer supported.');
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    throw StateError('Phone sign-in is no longer supported.');
  }

  String _friendlyGoogleError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'operation-not-allowed':
          return 'Google sign-in is disabled in Firebase Authentication. Please enable the Google provider.';
        case 'unauthorized-domain':
          return 'This domain is not authorized for Firebase Auth. Add it in Firebase Console > Authentication > Settings > Authorized domains.';
        case 'popup-closed-by-user':
          return 'Google sign-in was cancelled.';
        case 'popup-blocked':
          return 'Popup was blocked by the browser. Allow popups and try again.';
        case 'network-request-failed':
          return 'Network error. Please check internet and try again.';
        case 'too-many-requests':
          return 'Too many sign-in attempts. Please try again in a few minutes.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with a different sign-in method. Try signing in with that method first.';
      }
    }

    final message = error.toString();
    if (message.contains('ClientID not set')) {
      return 'Google Sign-In is not configured for web yet. Add your Web OAuth client ID and try again.';
    }
    if (message.contains('ApiException: 12500')) {
      return 'Google Sign-In configuration mismatch for this build. Add the correct SHA fingerprint (including Play App Signing SHA for tester/store builds) in Firebase and re-download google-services.json.';
    }
    if (message.contains('ApiException: 10')) {
      return 'Google Sign-In setup is incomplete (SHA-1/SHA-256 or google-services.json mismatch).';
    }
    if (message.contains('sign_in_failed')) {
      return 'Google sign-in failed due to app configuration mismatch. Verify package name and all required SHA fingerprints in Firebase.';
    }
    if (message.contains('network_error')) {
      return 'Network error. Please check internet and try again.';
    }
    if (message.contains('sign_in_canceled') ||
        message.contains('sign_in_cancelled')) {
      return 'Google sign-in was cancelled.';
    }
    return 'Google sign-in failed. Please try again.';
  }

  Future<void> signOut() async {
    // Always sign out Google regardless of whether we have a cached instance.
    // A new temporary GoogleSignIn() calls the same underlying platform channel
    // as any cached instance, so it clears the platform-level session.
    final googleSignIn = _googleSignIn ?? GoogleSignIn();
    await Future.wait([
      _auth.signOut().catchError((_) async {}),
      googleSignIn.signOut().catchError((_) async => null),
    ]);
    _googleSignIn = null; // reset so next sign-in starts fresh
  }
}
