import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/legal_document_view.dart';

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
            content: Text(loc('Google ile giriş yapılamadı: $e', 'Could not sign in with Google: $e')),
            backgroundColor: LoveraColors.primary,
          ),
        );
      }
    }
  }

  Future<void> _handleAppleSignIn(BuildContext context, WidgetRef ref) async {
    try {
      final auth = ref.read(authServiceProvider);
      final cred = await auth.signInWithApple();
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
            content: Text(loc('Apple ile giriş yapılamadı: $e', 'Could not sign in with Apple: $e')),
            backgroundColor: LoveraColors.primary,
          ),
        );
      }
    }
  }

  void _openLegalDoc(BuildContext context, LegalDocType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentView(type: type),
      ),
    );
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
              loc(
                'Sadece ikinize özel,\nsakin ve samimi bir alan.',
                'A private, peaceful,\nand intimate space just for the two of you.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: LoveraColors.textMuted, height: 1.45),
            ).animate(delay: 150.ms).fadeIn(),
            const Spacer(flex: 3),
            // Apple ile Giriş & Google ile Giriş (Guideline 4.8: Her iki platformda da görünür)
            _AuthButton(
              label: loc('Apple ile devam et', 'Continue with Apple'),
              icon: const Icon(Icons.apple, color: Colors.white, size: 24),
              background: const Color(0xFF1C1C1E),
              foreground: Colors.white,
              onTap: () => _handleAppleSignIn(context, ref),
            ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 12),
            _AuthButton(
              label: loc('Google ile devam et', 'Continue with Google'),
              icon: const Text('G',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFDB4437))),
              background: theme.colorScheme.surface,
              foreground: theme.colorScheme.onSurface,
              bordered: true,
              onTap: () => _handleGoogleSignIn(context, ref),
            ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 12),
            _AuthButton(
              label: loc('E-posta ile devam et', 'Continue with email'),
              icon: Icon(Icons.mail_outline_rounded, color: LoveraColors.primary, size: 22),
              background: LoveraColors.primary.withValues(alpha: 0.12),
              foreground: LoveraColors.primary,
              onTap: () => _openEmailSheet(context, ref),
            ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 20),
            // Guideline 5.1.1 & 5.1.2: Tıklanabilir Gizlilik Politikası ve Kullanım Koşulları (EULA)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, height: 1.4),
                  children: [
                    TextSpan(text: loc('Devam ederek ', 'By continuing, you accept our ')),
                    TextSpan(
                      text: loc('Kullanım Koşulları', 'Terms of Use'),
                      style: TextStyle(
                        color: LoveraColors.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openLegalDoc(context, LegalDocType.termsOfUse),
                    ),
                    TextSpan(text: loc(' ve ', ' and ')),
                    TextSpan(
                      text: loc('Gizlilik Politikası', 'Privacy Policy'),
                      style: TextStyle(
                        color: LoveraColors.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openLegalDoc(context, LegalDocType.privacyPolicy),
                    ),
                    TextSpan(text: loc('’nı kabul etmiş olursun.', '.')),
                  ],
                ),
              ),
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
  bool _ageConfirmed = false;

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
    if (_register && !_ageConfirmed) {
      setState(() => _error = loc('Devam etmek için 18 yaşından büyük olduğunu onaylamalısın.', 'You must confirm you are over 18 to continue.'));
      return;
    }
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
          _error = loc('E-posta veya şifre hatalı.', 'Incorrect email or password.');
        } else if (e.code == 'email-already-in-use') {
          _error = loc('Bu e-posta adresi zaten kullanımda.', 'This email address is already in use.');
        } else if (e.code == 'weak-password') {
          _error = loc('Şifre çok zayıf. En az 6 karakter seçin.', 'Password is too weak. Use at least 6 characters.');
        } else if (e.code == 'network-request-failed') {
          _error = loc('İnternet bağlantınızı kontrol edin.', 'Please check your internet connection.');
        } else {
          _error = e.message ?? loc('Giriş yapılamadı.', 'Could not sign in.');
        }
      });
    } catch (e) {
      setState(() {
        _error = loc('Beklenmeyen bir hata oluştu: $e', 'An unexpected error occurred: $e');
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
            Text(_register ? loc('Hesap oluştur', 'Create account') : loc('Tekrar hoş geldin', 'Welcome back'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            if (_register) ...[
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: loc('Kullanıcı adı', 'Username'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length < 3) return loc('En az 3 karakter olmalı', 'Must be at least 3 characters');
                  if (!RegExp(r'^[a-zA-Z0-9_.çğıöşüÇĞİÖŞÜ]+$').hasMatch(t)) {
                    return loc('Boşluk ve özel karakter kullanma', 'Do not use spaces or special characters');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _ageConfirmed,
                onChanged: (v) => setState(() => _ageConfirmed = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(loc('18 yaşından büyük olduğumu onaylıyorum.', 'I confirm that I am over 18.'),
                    style: TextStyle(fontSize: 13)),
              ),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: loc('E-posta', 'Email'),
                prefixIcon: const Icon(Icons.mail_outline_rounded),
              ),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                  ? null
                  : loc('Geçerli bir e-posta gir', 'Enter a valid email'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: loc('Şifre', 'Password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v ?? '').length < 6 ? loc('En az 6 karakter olmalı', 'Must be at least 6 characters') : null,
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
                  style: TextStyle(color: LoveraColors.primary, fontSize: 13),
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
                  : Text(_register ? loc('Kayıt ol', 'Sign up') : loc('Giriş yap', 'Sign in')),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _loading ? null : () => setState(() => _register = !_register),
              child: Text(_register ? loc('Zaten hesabım var', 'I already have an account') : loc('Hesabın yok mu? Kayıt ol', "Don't have an account? Sign up")),
            ),
          ],
        ),
      ),
    );
  }
}
