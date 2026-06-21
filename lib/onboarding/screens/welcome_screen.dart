import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yanegi/auth/screens/auth_landing_page.dart';
import 'package:yanegi/auth/screens/map_page.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/services/auth_service.dart';
import 'package:yanegi/services/auth_flow_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/utils/error_handler.dart';
import 'package:yanegi/widgets/google_signin_button.dart';

/// First screen of the onboarding flow.
/// Welcomes the user and initiates the onboarding process.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final AuthFlowService _authFlowService = AuthFlowService();
  final AuthService _authService = AuthService();
  bool _isGoogleSigningIn = false;
  bool _isContinuingAsGuest = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'image assest/welcome_bg.png',
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(40),
                  Colors.black.withAlpha(110),
                  Colors.black.withAlpha(210),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed:
                          _isContinuingAsGuest ? null : _continueAsGuest,
                      child: _isContinuingAsGuest
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Skip',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const Spacer(),
                  Image.asset(
                    'image assest/yanegi_logo_clean.png',
                    width: 80,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  _buildGoogleSignInButton(),
                  const SizedBox(height: YanegiSpacing.md),
                  _buildEmailContinueButton(),
                  const SizedBox(height: YanegiSpacing.sm),
                  Text(
                    'By continuing, you agree to our Terms of Service',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continueAsGuest() async {
    if (_isContinuingAsGuest) return;
    setState(() => _isContinuingAsGuest = true);
    try {
    } catch (_) {
      // Anonymous provider disabled or auth failed — navigate to map anyway.
      // The map handles unauthenticated state gracefully.
    }
    if (!mounted) {
      _isContinuingAsGuest = false;
      return;
    }
    setState(() => _isContinuingAsGuest = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MapPage()),
      (route) => false,
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_isGoogleSigningIn) return;
    setState(() => _isGoogleSigningIn = true);

    try {
      final result = await _authFlowService.continueWithGoogle();
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in was cancelled.')),
        );
        return;
      }

      AuthBootstrapperController.rebootstrap(
        navigationContext: context,
        resetNavigation: false,
      );
    } on StateError catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.authGeneric,
        error: e,
        stackTrace: stack,
        where: 'welcome_screen._signInWithGoogle',
      );
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showFromError(
        context,
        e,
        stackTrace: stack,
        fallback: AppErrorType.authGeneric,
        where: 'welcome_screen._signInWithGoogle',
      );
    } finally {
      if (mounted) setState(() => _isGoogleSigningIn = false);
    }
  }

  Widget _buildGoogleSignInButton() {
    return GoogleSignInButton(
      onPressed: _isGoogleSigningIn ? null : _signInWithGoogle,
      isLoading: _isGoogleSigningIn,
    );
  }

  Widget _buildEmailContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AuthLandingPage(),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black.withAlpha(150),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: const Text(
          'Continue to sign in',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PhoneAuthSheet extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onSuccess;
  final ValueChanged<bool> onBusyChanged;

  const _PhoneAuthSheet({
    required this.authService,
    required this.onSuccess,
    required this.onBusyChanged,
  });

  @override
  State<_PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends State<_PhoneAuthSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String? _verificationId;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _error = 'Enter phone as +91XXXXXXXXXX');
      return;
    }

    setState(() {
      _error = null;
      _isSendingCode = true;
    });
    widget.onBusyChanged(true);

    try {
      await widget.authService.sendOtp(
        phoneNumber: phone,
        onCodeSent: (verificationId, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;
          });
          widget.onBusyChanged(false);
        },
        onVerificationFailed: (message) {
          if (!mounted) return;
          setState(() {
            _error = message;
            _isSendingCode = false;
          });
          widget.onBusyChanged(false);
        },
        onAutoVerified: (_) {
          if (!mounted) return;
          widget.onBusyChanged(false);
          widget.onSuccess();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to send OTP. Please try again.';
        _isSendingCode = false;
      });
      widget.onBusyChanged(false);
      debugPrint('Error while sending OTP: $e');
    }
  }

  Future<void> _verifyOtp() async {
    final verificationId = _verificationId;
    final code = _otpController.text.trim();
    if (verificationId == null || verificationId.isEmpty) {
      setState(() => _error = 'Request OTP first.');
      return;
    }
    if (code.length < 6) {
      setState(() => _error = 'Enter valid 6-digit OTP.');
      return;
    }

    setState(() {
      _error = null;
      _isVerifyingCode = true;
    });
    widget.onBusyChanged(true);

    try {
      await widget.authService.verifyOtp(
        verificationId: verificationId,
        smsCode: code,
      );
      if (!mounted) return;
      widget.onBusyChanged(false);
      widget.onSuccess();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Invalid OTP. Please try again.';
        _isVerifyingCode = false;
      });
      widget.onBusyChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canSend = !_isSendingCode && !_isVerifyingCode;
    final canVerify =
        _verificationId != null && !_isSendingCode && !_isVerifyingCode;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sign in with Phone',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Phone (+country code)',
              hintText: '+91XXXXXXXXXX',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSend ? _sendOtp : null,
              child: _isSendingCode
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send OTP'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'OTP',
              hintText: '6-digit code',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canVerify ? _verifyOtp : null,
              child: _isVerifyingCode
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify OTP'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }
}
