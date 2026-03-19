// lib/screens/login_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/rm_widgets.dart';
import 'show_list_screen.dart';

final supabase = Supabase.instance.client;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _msg;
  bool _busy = false;
  bool _showLogin = false;

  StreamSubscription<AuthState>? _sub;

  late final AnimationController _animationController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoScale = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _logoFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _cardFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _showLogin = true);
    });

    _sub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ShowListScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _email.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: _email.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _msg = 'Check your email for the login link.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Error: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Email is required.';
    if (!text.contains('@') || !text.contains('.')) {
      return 'Enter a valid email.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.navyDark,
              AppColors.navy,
              Color(0xFF1B3D82),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                              child: _LogoBlock(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            const Text(
                              'RingMaster Show',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Modern show management for rabbit, cavy, and small livestock events.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (_showLogin)
                      FadeTransition(
                        opacity: _cardFade,
                        child: SlideTransition(
                          position: _cardSlide,
                          child: RMCard(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Sign in',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Enter your email and we’ll send you a secure login link.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _email,
                                    validator: _validateEmail,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) {
                                      if (!_busy) _sendLink();
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'Email address',
                                      hintText: 'you@example.com',
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _sendLink,
                                    icon: _busy
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.login),
                                    label: Text(
                                      _busy ? 'Sending link…' : 'Send magic link',
                                    ),
                                  ),
                                  if (_msg != null) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    Container(
                                      padding: const EdgeInsets.all(AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: _msg!.startsWith('Error:')
                                            ? AppColors.dangerBg
                                            : AppColors.successBg,
                                        borderRadius: BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: Text(
                                        _msg!,
                                        style: TextStyle(
                                          color: _msg!.startsWith('Error:')
                                              ? AppColors.danger
                                              : AppColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.lg),
                                  Text(
                                    'Use the login link from your email to continue to RingMaster Show.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/ringmaster_show_logo.png',
          height: 160,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.emoji_events_outlined,
                size: 42,
                color: Colors.white,
              ),
            );
          },
        ),
      ],
    );
  }
}