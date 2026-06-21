import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/services/auth_flow_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/utils/error_handler.dart';

enum OtpState { idle, verifying, success, error, locked }

class EmailOtpPage extends StatefulWidget {
  const EmailOtpPage({super.key, required this.email});

  final String? email;

  @override
  State<EmailOtpPage> createState() => _EmailOtpPageState();
}

class _EmailOtpPageState extends State<EmailOtpPage> {
  final AuthFlowService _authFlowService = AuthFlowService();
  late final TextEditingController _emailController;
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  OtpState _state = OtpState.idle;
  String? _errorMessage;
  Timer? _resendTimer;
  Timer? _lockoutTimer;
  int _resendSeconds = 0;
  bool _isSendingOtp = false;
  bool _isVerifying = false;
  bool _hasNavigated = false;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();
    final email = widget.email?.trim();
    if (email == null || email.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    _emailController = TextEditingController(text: email ?? '');
    _state = OtpState.idle;
    _resendSeconds = 60;
    _startResendTimer();
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _setStateSafely(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

  String _normalizeEmail(String input) => input.trim().toLowerCase();

  bool _isValidEmail(String input) {
    final value = input.trim();
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(value);
  }

  bool get _isBusy =>
      _isSendingOtp || _state == OtpState.verifying || _isVerifying;

  bool get _isLocked => _state == OtpState.locked;

  bool get _canResend =>
      _resendSeconds == 0 &&
      !_isBusy &&
      _state != OtpState.success &&
      !_isLocked;

  String get _buttonLabel {
    if (_isSendingOtp) return 'Sending...';
    switch (_state) {
      case OtpState.idle:
        return 'Verify code';
      case OtpState.verifying:
        return 'Verifying...';
      case OtpState.success:
        return 'Verified ✅';
      case OtpState.error:
        return 'Try again';
      case OtpState.locked:
        return 'Locked';
    }
  }

  String get _otpValue =>
      _otpControllers.map((controller) => controller.text).join();

  Future<void> _sendOtp({bool isResend = false}) async {
    if (_isBusy) return;
    final email = _normalizeEmail(_emailController.text);
    if (!_isValidEmail(email)) {
      _setStateSafely(() {
        _state = OtpState.error;
        _errorMessage = 'Enter a valid email address.';
      });
      return;
    }

    _setStateSafely(() {
      _isSendingOtp = true;
      _errorMessage = null;
    });

    try {
      await _authFlowService.sendEmailOtp(email);

      _setStateSafely(() {
        _state = OtpState.idle;
        _resendSeconds = 60;
        _lockoutSeconds = 0;
      });

      _startResendTimer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isResend
                ? 'We sent a new code to your email.'
                : 'We sent a code to your email.',
          ),
        ),
      );
    } catch (e) {
      _setStateSafely(() {
        _state = OtpState.error;
        _errorMessage = _authFlowService.toFriendlyError(e);
      });
    } finally {
      _setStateSafely(() {
        _isSendingOtp = false;
      });
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        setState(() {
          _resendSeconds = 0;
        });
        timer.cancel();
      } else {
        setState(() {
          _resendSeconds -= 1;
        });
      }
    });
  }

  Future<void> _verifyOtp() async {
    if (_isBusy || _hasNavigated || _state == OtpState.success) return;
    if (_otpValue.length != 6) {
      _setStateSafely(() {
        _state = OtpState.error;
        _errorMessage = 'Invalid code / Try again';
      });
      return;
    }

    _setStateSafely(() {
      _isVerifying = true;
      _state = OtpState.verifying;
      _errorMessage = null;
    });

    try {
      // ignore: avoid_print
      print('VERIFY START');
      await _authFlowService
          .verifyEmailOtp(
            email: _emailController.text,
            otp: _otpValue,
          )
          .timeout(const Duration(seconds: 60));
      // ignore: avoid_print
      print('VERIFY SUCCESS');
      _setSuccessState();
      _returnToBootstrapper();
    } catch (e) {
      // ignore: avoid_print
      print('VERIFY FAILED');
      _handleVerifyError(e);
    } finally {
      final shouldSet = mounted && !_hasNavigated;
      if (shouldSet) {
        _setStateSafely(() {
          if (_state != OtpState.success) {
            _isVerifying = false;
          }
          if (_state == OtpState.verifying) {
            _state = OtpState.error;
            _errorMessage = 'Something went wrong. Please try again.';
          }
        });
      }
    }
  }

  void _setSuccessState() {
    // ignore: avoid_print
    print('SUCCESS STATE ENTERED');
    _setStateSafely(() {
      _state = OtpState.success;
      _errorMessage = null;
    });
  }

  void _returnToBootstrapper() {
    if (!mounted || _hasNavigated) return;
    // ignore: avoid_print
    print('AUTH BOOTSTRAPPER RETURN TRIGGERED');
    _hasNavigated = true;
    AuthBootstrapperController.rebootstrap(navigationContext: context);
  }

  void _handleVerifyError(Object error) {
    if (error is EmailOtpFailure) {
      switch (error.code) {
        case 'INVALID_EMAIL':
          _setStateSafely(() {
            _state = OtpState.error;
            _errorMessage = 'Enter a valid email address.';
          });
          return;
        case 'TOO_MANY_ATTEMPTS':
          _enterLockedState(error.lockedUntil);
          return;
        case 'OTP_USED':
          _setStateSafely(() {
            _state = OtpState.error;
            _errorMessage =
                'That code has already been used. Please request a new one.';
            _resendSeconds = 0;
          });
          return;
        case 'OTP_EXPIRED':
          _setStateSafely(() {
            _state = OtpState.error;
            _errorMessage =
                'That code has expired. Please request a new one.';
          });
          return;
        case 'INVALID_OTP':
          _setStateSafely(() {
            _state = OtpState.error;
            _errorMessage =
                ErrorHandler.messageFor(AppErrorType.authOtpInvalid);
          });
          return;
        case 'NETWORK_ERROR':
          _setStateSafely(() {
            _state = OtpState.error;
            _errorMessage = ErrorHandler.messageFor(AppErrorType.network);
          });
          return;
        case 'RESEND_COOLDOWN':
          _setStateSafely(() {
            _state = OtpState.error;
            _errorMessage = ErrorHandler.messageFor(AppErrorType.rateLimited);
          });
          return;
      }
    }

    _setStateSafely(() {
      _state = OtpState.error;
      _errorMessage = ErrorHandler.friendlyMessage(
        error,
        fallback: AppErrorType.authVerificationFailed,
        where: 'email_otp_page._handleVerifyError',
      );
    });
  }

  void _enterLockedState(int? lockedUntil) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = lockedUntil ?? now + 5 * 60 * 1000;
    final remainingSeconds = ((until - now) / 1000).ceil();
    // ignore: avoid_print
    print('LOCKED STATE ENTERED');
    _setStateSafely(() {
      _state = OtpState.locked;
      _lockoutSeconds = remainingSeconds > 0 ? remainingSeconds : 0;
      _errorMessage = null;
    });
    _startLockoutTimer();
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    // ignore: avoid_print
    print('LOCK COUNTDOWN START');
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        _setStateSafely(() {
          _lockoutSeconds = 0;
          _state = OtpState.idle;
        });
      } else {
        _setStateSafely(() {
          _lockoutSeconds -= 1;
        });
      }
    });
  }

  void _handleOtpChange(String value, int index) {
    if (_state == OtpState.error || _errorMessage != null) {
      _setStateSafely(() {
        _state = OtpState.idle;
        _errorMessage = null;
      });
    }

    if (value.length > 1) {
      _applyPastedOtp(value);
      return;
    }

    if (value.isNotEmpty && index < _otpFocusNodes.length - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  void _applyPastedOtp(String rawValue) {
    final digits = rawValue.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    for (var i = 0; i < _otpControllers.length; i++) {
      final char = i < digits.length ? digits[i] : '';
      _otpControllers[i].text = char;
    }
    if (_state == OtpState.error || _errorMessage != null) {
      _setStateSafely(() {
        _state = OtpState.idle;
        _errorMessage = null;
      });
    }
    if (digits.length >= _otpControllers.length) {
      _otpFocusNodes.last.unfocus();
    } else {
      _otpFocusNodes[digits.length].requestFocus();
    }
    _setStateSafely(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: YanegiColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(YanegiSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter the 6-digit code sent to your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: YanegiColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: YanegiSpacing.sm),
                  const Text(
                    'Check your inbox to continue signing in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: YanegiColors.textSecondary),
                  ),
                  // Lockout banner — shown above all inputs so it's always
                  // visible even when the keyboard pushes content up.
                  if (_lockoutSeconds > 0 || _state == OtpState.locked) ...[
                    const SizedBox(height: YanegiSpacing.lg),
                    _buildLockoutBanner(),
                  ],
                  const SizedBox(height: YanegiSpacing.xl),
                  _AuthField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'you@example.com',
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    enabled: false,
                    errorText: _state == OtpState.error ? _errorMessage : null,
                  ),
                  const SizedBox(height: YanegiSpacing.md),
                  _buildOtpInputRow(),
                  const SizedBox(height: YanegiSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'We sent a code to your email',
                        style: const TextStyle(
                          color: YanegiColors.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed:
                            _canResend ? () => _sendOtp(isResend: true) : null,
                        child: Text(
                          _resendSeconds > 0
                              ? 'Resend in ${_formatSeconds(_resendSeconds)}'
                              : 'Resend code',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: YanegiSpacing.lg),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isBusy ||
                              _state == OtpState.success ||
                              _hasNavigated ||
                              _isLocked
                          ? null
                          : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YanegiColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YanegiRadius.md),
                        ),
                      ),
                      child: _state == OtpState.success
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(_buttonLabel),
                              ],
                            )
                          : _isBusy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_buttonLabel),
                                  ],
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpInputRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_otpControllers.length, (index) {
        return SizedBox(
          width: 44,
          child: TextField(
            controller: _otpControllers[index],
            focusNode: _otpFocusNodes[index],
            enabled: !_isBusy && _state != OtpState.success && !_isLocked,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            onChanged: (value) => _handleOtpChange(value, index),
            decoration: InputDecoration(
              filled: true,
              fillColor: YanegiColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YanegiRadius.md),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YanegiRadius.md),
                borderSide: const BorderSide(color: YanegiColors.primary),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLockoutBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: YanegiSpacing.md,
        vertical: YanegiSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(25),
        borderRadius: BorderRadius.circular(YanegiRadius.md),
        border: Border.all(color: Colors.redAccent.withAlpha(120), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: YanegiSpacing.sm),
          Expanded(
            child: Text(
              _lockoutSeconds > 0
                  ? 'Too many attempts. Try again in ${_formatSeconds(_lockoutSeconds)}.'
                  : 'Too many attempts. Please try again.',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _lockoutMessage {
    return _lockoutSeconds > 0
        ? 'Too many attempts. Try again in ${_formatSeconds(_lockoutSeconds)}.'
        : 'Too many attempts. Please try again.';
  }

  String _formatSeconds(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remaining = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remaining';
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: YanegiColors.textSecondary),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          enabled: enabled,
          style: const TextStyle(color: YanegiColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: YanegiColors.textTertiary),
            filled: true,
            fillColor: YanegiColors.surface,
            errorText: errorText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              borderSide: const BorderSide(color: YanegiColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
