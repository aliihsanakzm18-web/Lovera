import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key, required this.onSignedIn});
  final ValueChanged<bool> onSignedIn;

  Future<void> _handleGoogleSignIn(BuildContext context, WidgetRef ref) async {
    try {
      final auth = ref.read(authServiceProvider);
      final cred = await auth.signInWithGoogle();
      if (cred != null && cred.user != null) {
        final name = cred.user!.displayName ?? '';
        if (name.isNotEmpty) {
          ref.read(userNameProvider.notifier).state = name;
        }
        final isNew = cred.additionalUserInfo?.isNewUser ?? false;
        onSignedIn(isNew);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google ile giriş yapılamadı: $e'),
            backgroundColor: LoveraColors.primary,
          ),
        );
      }
    }
  }

  void _openEmailSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _EmailSheet(
        onSuccess: (username, isNewUser) async {
          if (username.isNotEmpty) {
            ref.read(userNameProvider.notifier).state = username;
          }
          Navigator.of(context).pop();
          await Future.delayed(const Duration(milliseconds: 150));
          onSignedIn(isNewUser);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LoveraColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: AppTheme.primaryGlow,
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 50),
            ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 28),
            Text('Lovera',
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Sadece ikinize özel,\nsakin ve samimi bir alan.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: LoveraColors.textMuted, height: 1.45),
            ).animate(delay: 150.ms).fadeIn(),
            const Spacer(flex: 3),
            _AuthButton(
              label: 'Google ile devam et',
              icon: const Text('G',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFDB4437))),
              background: theme.colorScheme.surface,
              foreground: theme.colorScheme.onSurface,
              bordered: true,
              onTap: () => _handleGoogleSignIn(context, ref),
            ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 14),
            _AuthButton(
              label: 'Apple ile devam et',
              icon: const Icon(Icons.apple, color: Colors.white, size: 24),
              background: const Color(0xFF1C1C1E),
              foreground: Colors.white,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Apple ile giriş yakında aktif olacak. Lütfen e-posta ile devam edin.'),
                    backgroundColor: LoveraColors.textDark,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                );
              },
            ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 14),
            _AuthButton(
              label: 'E-posta ile devam et',
              icon: const Icon(Icons.mail_outline_rounded, color: LoveraColors.primary, size: 22),
              background: LoveraColors.primary.withValues(alpha: 0.12),
              foreground: LoveraColors.primary,
              onTap: () => _openEmailSheet(context, ref),
            ).animate(delay: 450.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 20),
            Text(
              'Devam ederek Kullanım Koşulları ve Gizlilik Politikası’nı kabul etmiş olursun.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.bordered = false,
  });

  final String label;
  final Widget icon;
  final Color background;
  final Color foreground;
  final bool bordered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: bordered ? Border.all(color: Theme.of(context).dividerColor) : null,
            boxShadow: bordered ? AppTheme.ambientShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// E-posta ile giriş / kayıt formu.
class _EmailSheet extends StatefulWidget {
  const _EmailSheet({required this.onSuccess});
  final void Function(String username, bool isNewUser) onSuccess;

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = AuthService();
      if (_register) {
        await auth.registerWithEmail(
          email: _email.text.trim(),
          password: _password.text.trim(),
          username: _username.text.trim(),
        );
        widget.onSuccess(_username.text.trim(), true);
      } else {
        final cred = await auth.signInWithEmail(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
        widget.onSuccess(cred.user?.displayName ?? '', false);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential' || e.code == 'INVALID_LOGIN_CREDENTIALS') {
          _error = 'E-posta veya şifre hatalı.';
        } else if (e.code == 'email-already-in-use') {
          _error = 'Bu e-posta adresi zaten kullanımda.';
        } else if (e.code == 'weak-password') {
          _error = 'Şifre çok zayıf. En az 6 karakter seçin.';
        } else if (e.code == 'network-request-failed') {
          _error = 'İnternet bağlantınızı kontrol edin.';
        } else {
          _error = e.message ?? 'Giriş yapılamadı.';
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Beklenmeyen bir hata oluştu: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_register ? 'Hesap oluştur' : 'Tekrar hoş geldin',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            if (_register) ...[
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Kullanıcı adı',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length < 3) return 'En az 3 karakter olmalı';
                  if (!RegExp(r'^[a-zA-Z0-9_.çğıöşüÇĞİÖŞÜ]+$').hasMatch(t)) {
                    return 'Boşluk ve özel karakter kullanma';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'E-posta',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                  ? null
                  : 'Geçerli bir e-posta gir',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Şifre',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v ?? '').length < 6 ? 'En az 6 karakter olmalı' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LoveraColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: LoveraColors.primary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_register ? 'Kayıt ol' : 'Giriş yap'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _loading ? null : () => setState(() => _register = !_register),
              child: Text(_register ? 'Zaten hesabım var' : 'Hesabın yok mu? Kayıt ol'),
            ),
          ],
        ),
      ),
    );
  }
}
