import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yanegi/auth/screens/email_input_page.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/services/auth_flow_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/widgets/google_signin_button.dart';

class AuthLandingPage extends StatefulWidget {
  const AuthLandingPage({super.key});

  @override
  State<AuthLandingPage> createState() => _AuthLandingPageState();
}

class _AuthLandingPageState extends State<AuthLandingPage> {
  final AuthFlowService _authFlowService = AuthFlowService();
  bool _isGoogleLoading = false;
  bool _isNavigating = false;

  Future<void> _continueWithGoogle() async {
    if (_isGoogleLoading) return;
    setState(() => _isGoogleLoading = true);

    try {
      final result = await _authFlowService.continueWithGoogle();
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in was cancelled.')),
        );
        return;
      }

      debugPrint('AUTH FLOW STEP 10: rebootstrapping after Google sign-in');
      AuthBootstrapperController.rebootstrap(navigationContext: context);
    } catch (e) {
      if (!mounted) return;
      // Safety net: even if Firestore setup threw, Firebase Auth may have
      // succeeded. If the current user is real (non-anonymous), rebootstrap
      // instead of showing an error — bootstrap will handle profile creation.
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.isAnonymous) {
        debugPrint(
          'AUTH FLOW STEP 10: Firestore error but auth succeeded — rebooting anyway',
        );
        AuthBootstrapperController.rebootstrap(navigationContext: context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authFlowService.toFriendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _continueWithEmail() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => const EmailInputPage(),
      ),
    )
        .whenComplete(() {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YanegiColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                width: double.infinity,
                child: Image.asset(
                  'image assest/auth_hero.gif',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  children: [
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        color: YanegiColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: YanegiSpacing.lg),
                    GoogleSignInButton(
                      onPressed: _isGoogleLoading ? null : _continueWithGoogle,
                      isLoading: _isGoogleLoading,
                    ),
                    const SizedBox(height: YanegiSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isNavigating ? null : _continueWithEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YanegiColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(YanegiRadius.md),
                          ),
                        ),
                        child: const Text('Continue with Email'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
