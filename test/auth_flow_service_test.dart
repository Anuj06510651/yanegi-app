import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yanegi/services/auth_flow_service.dart';

void main() {
  group('AuthFlowService.sendEmailOtp', () {
    test('throws on invalid email format before network calls', () async {
      final service = AuthFlowService();

      expect(
        () => service.sendEmailOtp('invalid-email'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Please enter a valid email address.',
          ),
        ),
      );
    });
  });

  group('AuthFlowService.verifyEmailOtp', () {
    test('throws on invalid OTP format before network calls', () async {
      final service = AuthFlowService();

      expect(
        () => service.verifyEmailOtp(
          email: 'user@example.com',
          otp: '123',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Enter the 6-digit code.',
          ),
        ),
      );
    });
  });

  group('AuthFlowService.loginWithIdentifierAndPassword', () {
    test('throws when identifier is empty', () async {
      final service = AuthFlowService();

      expect(
        () => service.loginWithIdentifierAndPassword(
          identifier: '   ',
          password: 'password123',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Password sign-in is no longer supported. Please use email OTP or Google sign-in.',
          ),
        ),
      );
    });

    test('throws when password is empty', () async {
      final service = AuthFlowService();

      expect(
        () => service.loginWithIdentifierAndPassword(
          identifier: 'my_username',
          password: '   ',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Password sign-in is no longer supported. Please use email OTP or Google sign-in.',
          ),
        ),
      );
    });
  });

  group('AuthFlowService.sendPasswordResetForIdentifier', () {
    test('throws when identifier is empty', () async {
      final service = AuthFlowService();

      expect(
        () => service.sendPasswordResetForIdentifier('   '),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Password reset is no longer available. Please use email OTP instead.',
          ),
        ),
      );
    });

    test('throws when identifier is invalid email format', () async {
      final service = AuthFlowService();

      expect(
        () => service.sendPasswordResetForIdentifier('broken@email'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Password reset is no longer available. Please use email OTP instead.',
          ),
        ),
      );
    });
  });

  group('AuthFlowService.toFriendlyError', () {
    test('returns StateError message directly', () {
      final service = AuthFlowService();

      final msg = service.toFriendlyError(StateError('Custom state issue'));

      expect(msg, 'Custom state issue');
    });

    test('maps FirebaseAuthException codes to friendly text', () {
      final service = AuthFlowService();

      final msg = service.toFriendlyError(
        FirebaseAuthException(code: 'too-many-requests'),
      );

      expect(msg, 'Too many attempts. Please wait and try again.');
    });
  });
}
