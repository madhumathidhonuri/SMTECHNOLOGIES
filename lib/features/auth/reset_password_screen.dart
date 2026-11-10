import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_assets_base64.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({this.token = '', super.key});

  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final TextEditingController _tokenCtrl;
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.token);
    _passCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// 0–4 strength score driving the meter.
  int get _strength {
    final String p = _passCtrl.text;
    if (p.isEmpty) return 0;
    int score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) {
      score++;
    }
    return score.clamp(0, 4);
  }

  Future<void> _submit() async {
    final String token = _tokenCtrl.text.trim();
    final String pass = _passCtrl.text;
    final String confirm = _confirmCtrl.text;

    if (token.isEmpty) {
      _showError('Please provide a valid reset token');
      return;
    }
    if (pass.isEmpty) {
      _showError('Please enter a new password');
      return;
    }
    if (pass.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }
    if (pass != confirm) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    final bool ok = await ref.read(authProvider.notifier).resetPassword(
          token: token,
          password: pass,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (ok) {
      setState(() => _success = true);
    } else {
      final String? err = ref.read(authProvider).error;
      _showError(err ?? 'Could not reset password. The link may have expired.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFFE63946),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.day0,
      body: Stack(
        children: [
          // Background ambient circles
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.9),
                    AppColors.day0.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFC7D7EC).withOpacity(0.4),
                    AppColors.day0.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar with Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFF0D1B36),
                        size: 20,
                      ),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/login');
                        }
                      },
                    ),
                  ),
                ),

                Expanded(
                  child: CustomScrollView(
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            children: [
                              const Spacer(),

                              // Logo Squircle Card
                              _buildLogoCard().animate().fadeIn(duration: 600.ms).slideY(begin: -0.05),

                              const SizedBox(height: 28),

                              // Form or Success
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 420),
                                child: _success
                                    ? _buildSuccessCard()
                                    : _buildResetForm().animate().fadeIn(delay: 200.ms, duration: 600.ms),
                              ),

                              const Spacer(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoCard() {
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FD),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.85),
            offset: const Offset(8, 8),
            blurRadius: 18,
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Image.memory(
            AppAssetsB64.logoEmblem,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildResetForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create New Password',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0D1B36),
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your new password must be different from previous passwords.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF637691),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Token Input
        _buildInputField(
          controller: _tokenCtrl,
          hint: 'Reset Token',
          icon: Icons.vpn_key_rounded,
        ),
        const SizedBox(height: 16),

        // New Password Input
        _buildInputField(
          controller: _passCtrl,
          hint: 'New Password',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          obscureText: _obscurePass,
          onToggleVisibility: () => setState(() => _obscurePass = !_obscurePass),
        ),
        const SizedBox(height: 10),

        // Strength Meter
        _buildStrengthMeter(),
        const SizedBox(height: 16),

        // Confirm Password Input
        _buildInputField(
          controller: _confirmCtrl,
          hint: 'Confirm New Password',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          obscureText: _obscureConfirm,
          onToggleVisibility: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        const SizedBox(height: 28),

        // Submit Button
        _buildLoginStyleButton(
          label: 'Reset Password',
          onTap: _isLoading ? null : _submit,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.55),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF101F36),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF7A8FA8),
          ),
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 20, right: 14),
            child: Icon(icon, color: const Color(0xFF566A85), size: 21),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 54),
          suffixIcon: isPassword
              ? GestureDetector(
                  onTap: onToggleVisibility,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(
                      obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: const Color(0xFF566A85),
                      size: 21,
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 54),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildStrengthMeter() {
    final int score = _strength;
    Color color = Colors.grey.shade300;
    String label = 'Too Weak';

    if (score == 1) {
      color = const Color(0xFFEF4444);
      label = 'Weak';
    } else if (score == 2) {
      color = const Color(0xFFF59E0B);
      label = 'Fair';
    } else if (score == 3) {
      color = const Color(0xFF10B981);
      label = 'Good';
    } else if (score == 4) {
      color = const Color(0xFF059669);
      label = 'Strong';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score == 0 ? 0.05 : score / 4.0,
                backgroundColor: const Color(0xFFE2ECF8),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.6),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
              size: 38,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Password Reset Complete',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D1B36),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Your password has been changed successfully. You can now sign in with your new credentials.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Color(0xFF637691),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          _buildLoginStyleButton(
            label: 'Sign In Now',
            onTap: () => context.go('/login'),
            isLoading: false,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginStyleButton({
    required String label,
    required VoidCallback? onTap,
    required bool isLoading,
  }) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2872FF),
            Color(0xFF0C46D4),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E60FF).withOpacity(0.55),
            offset: const Offset(0, 10),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF387BFF).withOpacity(0.75),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.35),
                              width: 1.0,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
