import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/providers.dart';

enum _AuthMode { signIn, signUp }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscure = true;
  bool _busy = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authProvider.notifier);
      if (_mode == _AuthMode.signIn) {
        await auth.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        final confirmed = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : _emailController.text.trim().split('@').first,
        );
        if (!confirmed && mounted) {
          // Project requires email confirmation before the session exists.
          setState(() => _mode = _AuthMode.signIn);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account created! Check your inbox to confirm your email, '
                'then sign in.',
              ),
            ),
          );
          return;
        }
      }
      HapticFeedback.mediumImpact();
      // Redirect to /chats happens in the router once the session exists.
    } on AuthApiException catch (e) {
      HapticFeedback.selectionClick();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendly(e.message))),
        );
      }
    } catch (_) {
      HapticFeedback.selectionClick();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not reach the account service. Check the connection and '
              'try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String? message) {
    final m = (message ?? '').toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (m.contains('already registered')) {
      return 'This email already has an account — try signing in.';
    }
    if (m.contains('password')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    if (m.contains('rate limit')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return message?.isNotEmpty == true
        ? message!
        : 'Sign-in failed. Try again in a moment.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            children: [
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: colors.primaryContainer.withValues(alpha: 0.6),
                    ),
                    child: Icon(
                      Icons.build_circle_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Building', style: text.headlineSmall),
                      Text(
                        'From prompt to installable APK',
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SegmentedButton<_AuthMode>(
                segments: const [
                  ButtonSegment(
                    value: _AuthMode.signIn,
                    label: Text('Sign in'),
                  ),
                  ButtonSegment(
                    value: _AuthMode.signUp,
                    label: Text('Create account'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (modes) =>
                    setState(() => _mode = modes.first),
              ),
              const SizedBox(height: 20),
              if (_mode == _AuthMode.signUp) ...[
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Display name',
                    labelText: 'Display name',
                  ),
                  validator: (v) => null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'you@example.dev',
                  labelText: 'Email',
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (!_emailRegex.hasMatch(value)) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  hintText: 'At least 6 characters',
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (v) {
                  if ((v ?? '').length < 6) {
                    return 'Use at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(
                          _mode == _AuthMode.signIn
                              ? 'Sign in'
                              : 'Create account',
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Email + password. Your account, chats and apps carry across '
                'installs and devices.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
