
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() =>
      _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController =
  TextEditingController();

  final TextEditingController passwordController =
  TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  Future<void> login() async {
    final email =
    emailController.text.trim();

    final password =
    passwordController.text.trim();

    if (email.isEmpty) {
      showMessage('Please enter your email.');
      return;
    }

    if (password.isEmpty) {
      showMessage('Please enter your password.');
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: email,
        password: password,
      );

// Do NOT navigate here.
//
// AuthGate is listening to FirebaseAuth.
// After successful login, AuthGate will automatically
// decide whether this user is:
//
// Admin  -> AdminDashboardPage
// Student -> HomePage
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'invalid-email':
          message = 'The email address is invalid.';
          break;

        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
          message =
          'Incorrect email or password.';
          break;

        case 'user-disabled':
          message =
          'This account has been disabled.';
          break;

        case 'too-many-requests':
          message =
          'Too many login attempts. Please try again later.';
          break;

        case 'network-request-failed':
          message =
          'Network error. Please check your internet connection.';
          break;

        default:
          message =
              e.message ??
                  'Unable to log in. Please try again.';
      }

      showMessage(message);
    } catch (e) {
      showMessage(
        'An unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void clearFields() {
    emailController.clear();
    passwordController.clear();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),

              child: Card(
                elevation: 4,
                color: const Color(0xFFFFEE58),
                child: Padding(
                  padding: const EdgeInsets.all(28),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

// Logo / icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          shape: BoxShape.circle,
                        ),

                        child:
                          Image.asset(
                            'assets/icon/app_icon.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.contain,
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'QR Attendance',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFF0800),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Sign in to continue',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 30),

// Email
                      TextField(
                        controller: emailController,

                        enabled: !loading,

                        keyboardType:
                        TextInputType.emailAddress,

                        textInputAction:
                        TextInputAction.next,

                        decoration:
                        const InputDecoration(
                          labelText: 'Email',
                          hintText:
                          'Enter your email',
                          prefixIcon:
                          Icon(Icons.email_outlined),
                          border:
                          OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 18),

// Password
                      TextField(
                        controller: passwordController,

                        enabled: !loading,

                        obscureText: obscurePassword,

                        textInputAction:
                        TextInputAction.done,

                        onSubmitted: (_) {
                          if (!loading) {
                            login();
                          }
                        },

                        decoration:
                        InputDecoration(
                          labelText: 'Password',
                          hintText:
                          'Enter your password',

                          prefixIcon:
                          const Icon(
                            Icons.lock_outline,
                          ),

                          suffixIcon:
                          IconButton(
                            onPressed: loading
                                ? null
                                : () {
                              setState(() {
                                obscurePassword =
                                !obscurePassword;
                              });
                            },

                            icon: Icon(
                              obscurePassword
                                  ? Icons
                                  .visibility_outlined
                                  : Icons
                                  .visibility_off_outlined,
                            ),
                          ),

                          border:
                          const OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 25),

// Login button
                      SizedBox(
                        width: double.infinity,
                        height: 52,

                        child: ElevatedButton(
                          onPressed:
                          loading ? null : login,

                          child: loading
                              ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                            CircularProgressIndicator(
                              strokeWidth: 2.5,
                            ),
                          )
                              : const Text(
                            'LOGIN',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

// Clear button
                      TextButton(
                        onPressed: loading
                            ? null
                            : clearFields,

                        child: const Text(
                          'Clear',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
