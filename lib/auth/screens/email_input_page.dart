import 'package:flutter/material.dart';
import 'package:yanegi/auth/screens/email_otp_page.dart';
import 'package:yanegi/services/auth_flow_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

class EmailInputPage extends StatefulWidget {
  const EmailInputPage({super.key});

  @override
  State<EmailInputPage> createState() => _EmailInputPageState();
}

class _EmailInputPageState extends State<EmailInputPage> {
  final AuthFlowService _authFlowService = AuthFlowService();
  final TextEditingController _emailController = TextEditingController();
  bool _isSending = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _normalizeEmail(String input) => input.trim().toLowerCase();

  bool _isValidEmail(String input) {
    final value = input.trim();
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(value);
  }

  Future<void> _sendOtp() async {
    if (_isSending) return;

    final email = _normalizeEmail(_emailController.text);
    if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _isSending = true;
      _emailError = null;
    });

    try {
      await _authFlowService.sendEmailOtp(email);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmailOtpPage(email: email),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailError = _authFlowService.toFriendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
                    'Enter your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: YanegiColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: YanegiSpacing.sm),
                  const Text(
                    'We’ll send a 6-digit code to your email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: YanegiColors.textSecondary),
                  ),
                  const SizedBox(height: YanegiSpacing.xl),
                  _EmailField(
                    controller: _emailController,
                    errorText: _emailError,
                    onSubmitted: (_) => _sendOtp(),
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                  ),
                  const SizedBox(height: YanegiSpacing.lg),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YanegiColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YanegiRadius.md),
                        ),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send OTP'),
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
}

class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.onSubmitted,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: TextStyle(color: YanegiColors.textSecondary),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          style: const TextStyle(color: YanegiColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'you@example.com',
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
