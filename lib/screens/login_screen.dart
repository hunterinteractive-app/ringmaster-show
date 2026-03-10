
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'show_list_screen.dart';

final supabase = Supabase.instance.client;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  String? _msg;
  bool _busy = false;

  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _sendLink() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await supabase.auth.signInWithOtp(email: _email.text.trim());
      setState(() => _msg = 'Check your email for the login link.');
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RingMaster Show')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _sendLink,
              child: Text(_busy ? 'Sending…' : 'Send magic link'),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 12),
              Text(_msg!),
            ],
          ],
        ),
      ),
    );
  }
}