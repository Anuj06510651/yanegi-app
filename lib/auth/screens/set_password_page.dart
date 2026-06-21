import 'package:flutter/material.dart';
import 'package:yanegi/auth/screens/auth_landing_page.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final bool _isSaving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _savePasswordAndContinue() async {
    if (_isSaving) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password sign-in is no longer supported.'),
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthLandingPage()),
    );
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
                    'Set Your Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: YanegiColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: YanegiSpacing.sm),
                  const Text(
                    'Password sign-in is deprecated. Continue with an email OTP instead.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: YanegiColors.textSecondary),
                  ),
                  const SizedBox(height: YanegiSpacing.xl),
                  _PasswordField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'At least 6 characters',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: YanegiSpacing.md),
                  _PasswordField(
                    controller: _confirmController,
                    label: 'Confirm Password',
                    hint: 'Re-enter password',
                    onSubmitted: (_) => _savePasswordAndContinue(),
                  ),
                  const SizedBox(height: YanegiSpacing.lg),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _savePasswordAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YanegiColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YanegiRadius.md),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Continue'),
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

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(color: YanegiColors.textSecondary)),
        const SizedBox(height: YanegiSpacing.sm),
        TextField(
          controller: widget.controller,
          obscureText: _obscure,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(color: YanegiColors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: YanegiColors.textTertiary),
            filled: true,
            fillColor: YanegiColors.surface,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                color: YanegiColors.textSecondary,
              ),
            ),
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
