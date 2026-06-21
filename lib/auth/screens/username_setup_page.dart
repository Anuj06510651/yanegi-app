import 'package:flutter/material.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/services/auth_flow_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

class UsernameSetupPage extends StatefulWidget {
  const UsernameSetupPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<UsernameSetupPage> createState() => _UsernameSetupPageState();
}

class _UsernameSetupPageState extends State<UsernameSetupPage> {
  final AuthFlowService _authFlowService = AuthFlowService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();

    if (name.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and username are required.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _authFlowService.completeProfile(name: name, username: username);
      if (!mounted) return;
      AuthBootstrapperController.rebootstrap(
        navigationContext: context,
        resetNavigation: false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authFlowService.toFriendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
                    'Set up your profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: YanegiColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((widget.initialEmail ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: YanegiSpacing.sm),
                    Text(
                      widget.initialEmail!.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: YanegiColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: YanegiSpacing.xl),
                  _AuthField(
                    controller: _nameController,
                    label: 'Name',
                    hint: 'Your display name',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: YanegiSpacing.md),
                  _AuthField(
                    controller: _usernameController,
                    label: 'Username',
                    hint: 'Unique username (e.g. anujdev)',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: YanegiSpacing.lg),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
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
                          : const Text('Continue to Map'),
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

class _AuthField extends StatelessWidget {
  const _AuthField({
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: YanegiColors.textSecondary)),
        const SizedBox(height: YanegiSpacing.sm),
        TextField(
          controller: controller,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: YanegiColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: YanegiColors.textTertiary),
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
      ],
    );
  }
}
