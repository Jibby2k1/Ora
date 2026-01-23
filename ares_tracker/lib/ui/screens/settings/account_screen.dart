import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _lastMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<void> _signInEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _show('Email and password required.');
      return;
    }
    await _runBusy(() async {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _setMessage('Signed in with email.');
    });
  }

  Future<void> _signUpEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _show('Email and password required.');
      return;
    }
    await _runBusy(() async {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _setMessage('Account created.');
    });
  }

  Future<void> _signInGoogle() async {
    await _runBusy(() async {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        _setMessage('Google sign-in cancelled.');
        return;
      }
      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        throw FirebaseAuthException(
          code: 'google-auth-failed',
          message: 'Google authentication did not return tokens.',
        );
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      _setMessage('Signed in with Google.');
    });
  }

  Future<void> _signInApple() async {
    if (!Platform.isIOS) {
      _show('Apple sign-in is available on iOS.');
      return;
    }
    await _runBusy(() async {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauth = OAuthProvider('apple.com').credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauth);
      _setMessage('Signed in with Apple.');
    });
  }

  Future<void> _signInMicrosoft() async {
    await _runBusy(() async {
      final provider = OAuthProvider('microsoft.com');
      await FirebaseAuth.instance.signInWithProvider(provider);
      _setMessage('Signed in with Microsoft.');
    });
  }

  Future<void> _signOut() async {
    await _runBusy(() async {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
      _setMessage('Signed out.');
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      _show(_friendlyError(e));
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
        return 'This sign-in method is disabled in Firebase Console.';
      case 'email-already-in-use':
        return 'Email already in use. Try signing in instead.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'google-auth-failed':
        return e.message ?? 'Google auth failed. Check Firebase config.';
      default:
        return e.message ?? e.code;
    }
  }

  void _setMessage(String message) {
    if (!mounted) return;
    setState(() => _lastMessage = message);
    _show(message);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: Stack(
          children: const [
            GlassBackground(),
            Center(child: Text('Account features are available on mobile only.')),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Stack(
        children: [
          const GlassBackground(),
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              final providers = user?.providerData.map((p) => p.providerId).toList() ?? const [];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_lastMessage != null)
                    GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Text(_lastMessage!),
                    ),
                  if (_lastMessage != null) const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Status'),
                        const SizedBox(height: 8),
                        Text(user == null ? 'Signed out' : 'Signed in as ${user.email ?? user.uid}'),
                        if (user != null) ...[
                          const SizedBox(height: 8),
                          Text('UID: ${user.uid}'),
                          const SizedBox(height: 4),
                          Text('Providers: ${providers.isEmpty ? 'unknown' : providers.join(', ')}'),
                          const SizedBox(height: 4),
                          Text('Email verified: ${user.emailVerified ? 'yes' : 'no'}'),
                        ],
                        const SizedBox(height: 12),
                        if (user != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _signOut,
                              icon: const Icon(Icons.logout),
                              label: const Text('Sign out'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Email & Password'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(labelText: 'Password'),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _busy ? null : _signInEmail,
                                child: const Text('Sign in'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy ? null : _signUpEmail,
                                child: const Text('Create account'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sign in with'),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _signInGoogle,
                          icon: const Icon(Icons.g_mobiledata),
                          label: const Text('Google'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _signInApple,
                          icon: const Icon(Icons.apple),
                          label: const Text('Apple'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _signInMicrosoft,
                          icon: const Icon(Icons.business),
                          label: const Text('Microsoft'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
