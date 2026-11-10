import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/config/brand_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_assets_base64.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _obscurePassword = true;
  bool _rememberMe = true;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) return;

    final success = await ref.read(authProvider.notifier).login(
          identifier: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );

    if (mounted) {
      if (!success) {
        final error = ref.read(authProvider).error;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F9),
      body: Stack(
        children: [
          // ── 1. BACKGROUND NEUMORPHIC CONTOURS & 3D FLOATING ORBS ──
          _buildBackgroundDecor(),

          // ── 2. SCROLLABLE LOGIN CARD & CONTENT ──
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 410),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),

                      // ── Large 3D Neumorphic Emblem Card (160x160) ──
                      _buildNeumorphicLogo()
                          .animate()
                          .fadeIn(duration: 650.ms, curve: Curves.easeOut)
                          .scale(begin: const Offset(0.92, 0.92), duration: 650.ms, curve: Curves.easeOutBack),

                      const SizedBox(height: 26),

                      // ── Typography Headers ──
                      const Text(
                        'Welcome Back',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 31,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B172D),
                          letterSpacing: -0.8,
                        ),
                      ).animate().fadeIn(delay: 120.ms, duration: 550.ms).slideY(begin: 0.08),

                      const SizedBox(height: 8),

                      const Text(
                        'Sign in to continue',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF758AA6),
                          letterSpacing: 2.6,
                        ),
                      ).animate().fadeIn(delay: 200.ms, duration: 550.ms),

                      const SizedBox(height: 34),

                      // ── Plump Neumorphic Capsule Inputs ──
                      _buildNeumorphicInput(
                        controller: _emailCtrl,
                        hint: 'Username or Email',
                        icon: Icons.person_outline_rounded,
                        keyboardType: TextInputAction.next,
                      ).animate().fadeIn(delay: 280.ms, duration: 550.ms).slideY(begin: 0.08),

                      const SizedBox(height: 18),

                      _buildNeumorphicInput(
                        controller: _passCtrl,
                        hint: 'Password',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                        keyboardType: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                      ).animate().fadeIn(delay: 360.ms, duration: 550.ms).slideY(begin: 0.08),

                      const SizedBox(height: 18),

                      // ── Remember Me & Forgot Password ──
                      _buildRememberAndForgotRow().animate().fadeIn(delay: 440.ms, duration: 550.ms),

                      const SizedBox(height: 28),

                      // ── Glowing Royal Blue Gradient Login Pill Button ──
                      _buildLoginButton().animate().fadeIn(delay: 520.ms, duration: 550.ms).slideY(begin: 0.06),

                      const SizedBox(height: 36),

                      // ── Subtle Centered Divider ──
                      _buildFleetDivider().animate().fadeIn(delay: 600.ms, duration: 500.ms),

                      const SizedBox(height: 24),

                      // ── 3 Neumorphic Fleet Squircle Buttons ──
                      _buildFleetIconRow().animate().fadeIn(delay: 680.ms, duration: 550.ms).scale(begin: const Offset(0.92, 0.92)),

                      const SizedBox(height: 24),

                      // ── Tracking Subtitle & Copyright Footer ──
                      _buildFooter().animate().fadeIn(delay: 760.ms, duration: 550.ms),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  COMPONENTS & NEUMORPHIC WIDGETS
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBackgroundDecor() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── TOP-LEFT: Soft ambient porcelain contour ──
            Positioned(
              top: -80,
              left: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEFF5FC),
                  boxShadow: [
                    const BoxShadow(
                      color: Colors.white,
                      offset: Offset(-6, -6),
                      blurRadius: 16,
                    ),
                    BoxShadow(
                      color: const Color(0xFFC7D7EC).withOpacity(0.45),
                      offset: const Offset(8, 8),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ),

            // ── MIDDLE-RIGHT: Soft gentle floating sphere ──
            Positioned(
              top: 180,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.35),
                    radius: 0.85,
                    colors: [
                      Colors.white,
                      Color(0xFFF3F7FD),
                      Color(0xFFDFEAF7),
                      Color(0xFFC8DBEE),
                    ],
                    stops: [0.0, 0.35, 0.75, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB5CCE8).withOpacity(0.45),
                      offset: const Offset(-8, 14),
                      blurRadius: 24,
                    ),
                    const BoxShadow(
                      color: Colors.white,
                      offset: Offset(-3, -3),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),

            // ── BOTTOM-RIGHT: Subtle corner curve ──
            Positioned(
              bottom: -40,
              right: -40,
              child: Container(
                width: 160,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF5FC),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(120),
                  ),
                  boxShadow: [
                    const BoxShadow(
                      color: Colors.white,
                      offset: Offset(-4, -4),
                      blurRadius: 12,
                    ),
                    BoxShadow(
                      color: const Color(0xFFC7D7EC).withOpacity(0.40),
                      offset: const Offset(6, 6),
                      blurRadius: 18,
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

  Widget _buildNeumorphicLogo() {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FD),
        borderRadius: BorderRadius.circular(46),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8CEEA).withOpacity(0.65),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-3, -3),
            blurRadius: 14,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Image.memory(
          AppAssetsB64.logoIcon,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildNeumorphicInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputAction? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        textInputAction: keyboardType,
        onSubmitted: onSubmitted,
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 22, right: 14),
            child: Icon(
              icon,
              color: const Color(0xFF566A85),
              size: 21,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 56),
          suffixIcon: isPassword
              ? GestureDetector(
                  onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
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

  Widget _buildRememberAndForgotRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Remember Me
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _rememberMe ? const Color(0xFF1E60FF) : const Color(0xFFF1F6FD),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: _rememberMe ? const Color(0xFF1E60FF) : const Color(0xFFC7D7EC),
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (_rememberMe)
                        BoxShadow(
                          color: const Color(0xFF1E60FF).withOpacity(0.4),
                          offset: const Offset(0, 3),
                          blurRadius: 6,
                        )
                      else ...[
                        const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                        BoxShadow(
                          color: const Color(0xFFC7D7EC).withOpacity(0.6),
                          offset: const Offset(2, 2),
                          blurRadius: 5,
                        ),
                      ],
                    ],
                  ),
                  child: _rememberMe
                      ? const Center(
                          child: Icon(Icons.check, size: 14, color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Remember Me',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A2B44),
                  ),
                ),
              ],
            ),
          ),

          // Forgot Password
          GestureDetector(
            onTap: () => context.push('/forgot-password'),
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B60FF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    final isBusy = ref.watch(authProvider).isBusy;

    return Container(
      height: 60,
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
            offset: const Offset(0, 12),
            blurRadius: 26,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.7),
            offset: const Offset(0, -1),
            blurRadius: 3,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isBusy ? null : _login,
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: isBusy
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
                      const Center(
                        child: Text(
                          'Login',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
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

  Widget _buildFleetDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFCAD8EC),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'FLEET MONITORING',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A8DA6),
              letterSpacing: 2.2,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFCAD8EC),
          ),
        ),
      ],
    );
  }

  Widget _buildFleetIconRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildFleetIconTile(
          icon: Icons.local_shipping_rounded,
          color: const Color(0xFF1E60FF),
        ),
        const SizedBox(width: 24),
        _buildFleetIconTile(
          icon: Icons.directions_car_filled_rounded,
          color: const Color(0xFF00A3FF),
        ),
        const SizedBox(width: 24),
        _buildFleetIconTile(
          icon: Icons.sensors_rounded,
          color: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _buildFleetIconTile({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FC),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.55),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          color: color,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        const Text(
          'TRUCKS  •  FLEET  •  TELEMETRY',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF7A8DA6),
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '© ${DateTime.now().year} ${BrandConfig.legalEntityName}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF96A7C0),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
