import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'home_page.dart';
import 'login_page.dart';
import 'admin/admin_dashboard_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<bool> isAdmin(String uid) async {
    final document = await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .get();

    if (!document.exists) {
      return false;
    }

    final data = document.data();

    return data?['role'] == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Firebase is checking login status.
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Nobody is logged in.
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        final user = snapshot.data!;

        return FutureBuilder<bool>(
          future: isAdmin(user.uid),
          builder: (context, adminSnapshot) {
            if (adminSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (adminSnapshot.data == true) {
              return const AdminDashboardPage();
            }

            return const HomePage();
          },
        );
      },
    );
  }
}