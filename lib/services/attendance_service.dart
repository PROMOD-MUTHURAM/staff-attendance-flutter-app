import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'device_service.dart';

class AttendanceService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final DeviceService deviceService = DeviceService();

  Future<Map<String, dynamic>?> getEmployeeDetails() async {
    final user = auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in.');
    }

    final result = await firestore
        .collection('employees')
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (result.docs.isEmpty) {
      return null;
    }

    return result.docs.first.data();
  }

  // ------------------------------------------------------------
  // TODAY'S ATTENDANCE DOCUMENT ID
  // ------------------------------------------------------------

  String _todayDocumentId(String uid) {
    final now = DateTime.now();

    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    return '${uid}_$date';
  }

  // ------------------------------------------------------------
  // TODAY'S DATE
  // ------------------------------------------------------------

  String _todayDate() {
    final now = DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------
  // AUTOMATIC CHECKOUT TIME
  //
  // Previous attendance is automatically closed at 10:00 PM
  // on the DATE OF THAT ATTENDANCE.
  // ------------------------------------------------------------

  DateTime _automaticCheckoutTime(String date) {
    final parts = date.split('-');

    if (parts.length != 3) {
      throw Exception('Invalid attendance date: $date');
    }

    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);

    return DateTime(
      year,
      month,
      day,
      22, // 10 PM
      0,
      0,
    );
  }

  // ------------------------------------------------------------
  // FIND PREVIOUS OPEN ATTENDANCE
  //
  // An attendance is considered open when:
  //
  // checkInCount > checkOutCount
  //
  // Example:
  // checkInCount = 1
  // checkOutCount = 0
  //
  // means one check-in is still open.
  // ------------------------------------------------------------

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _findPreviousOpenAttendance(String uid) async {
    final today = _todayDate();

    final result = await firestore
        .collection('attendance')
        .where('userId', isEqualTo: uid)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? previousOpen;

    for (final document in result.docs) {
      final data = document.data();

      final date = data['date']?.toString();

      if (date == null || date == today) {
        continue;
      }

      final inCount = _getInt(data['checkInCount']);
      final outCount = _getInt(data['checkOutCount']);

      // This attendance still has an unfinished check-in.
      if (inCount > outCount) {
        if (previousOpen == null) {
          previousOpen = document;
        } else {
          final previousDate =
              previousOpen.data()['date']?.toString() ?? '';

          // Select the most recent previous open attendance.
          if (date.compareTo(previousDate) > 0) {
            previousOpen = document;
          }
        }
      }
    }

    return previousOpen;
  }

  // ------------------------------------------------------------
  // SAFE INTEGER CONVERSION
  // ------------------------------------------------------------

  int _getInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  // ------------------------------------------------------------
  // AUTOMATICALLY CHECK OUT PREVIOUS OPEN ATTENDANCE
  // ------------------------------------------------------------

  Future<void> _autoCheckoutPreviousAttendance({
    required QueryDocumentSnapshot<Map<String, dynamic>> previousDocument,
  }) async {
    final previousRef = previousDocument.reference;

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(previousRef);

      if (!snapshot.exists) {
        return;
      }

      final data = snapshot.data();

      if (data == null) {
        return;
      }

      final inCount = _getInt(data['checkInCount']);
      final outCount = _getInt(data['checkOutCount']);

      // It may have been checked out between the query and transaction.
      if (inCount <= outCount) {
        return;
      }

      final date = data['date']?.toString();

      if (date == null || date.isEmpty) {
        return;
      }

      // The next checkout number.
      //
      // Example:
      // checkInCount = 1
      // checkOutCount = 0
      //
      // Therefore this becomes checkOut1.
      final checkoutNumber = outCount + 1;

      // 10:00 PM on the PREVIOUS ATTENDANCE DATE.
      final automaticCheckoutDate =
      _automaticCheckoutTime(date);

      final automaticCheckoutTimestamp =
      Timestamp.fromDate(automaticCheckoutDate);

      final updateFields = <String, dynamic>{
        'checkOutCount': checkoutNumber,

        'checkOut$checkoutNumber':
        automaticCheckoutTimestamp,

        'checkOut${checkoutNumber}QrCode':
        'AUTO_CHECKOUT',

        // We intentionally do NOT provide a fake GPS location.
        'checkOut${checkoutNumber}Latitude': null,

        'checkOut${checkoutNumber}Longitude': null,

        // Identify this as a system-generated checkout.
        'checkOut${checkoutNumber}Type':
        'automatic',

        'checkOut${checkoutNumber}Device': {
          'platform': 'Automatic',
          'device': 'Automatic Checkout',
          'reason':
          'Previous attendance automatically closed when employee checked in again.',
        },

        'autoCheckout': true,

        'autoCheckoutTime':
        automaticCheckoutTimestamp,

        'status': 'checked_out',
      };

      transaction.update(previousRef, updateFields);
    });
  }

  // ------------------------------------------------------------
  // CHECK IN
  // ------------------------------------------------------------

  Future<void> checkIn({
    required String qrCode,
    required double latitude,
    required double longitude,
  }) async {
    final user = auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in.');
    }

    final employee = await getEmployeeDetails();

    if (employee == null) {
      throw Exception('Employee record not found.');
    }

    // ----------------------------------------------------------
    // FIRST:
    // Find and automatically close a previous unfinished
    // attendance record.
    // ----------------------------------------------------------

    final previousOpenAttendance =
    await _findPreviousOpenAttendance(user.uid);

    if (previousOpenAttendance != null) {
      await _autoCheckoutPreviousAttendance(
        previousDocument: previousOpenAttendance,
      );
    }

    // ----------------------------------------------------------
    // GET DEVICE INFORMATION FOR TODAY'S CHECK-IN
    // ----------------------------------------------------------

    final device = await deviceService.getDeviceDetails();

    final ref = firestore
        .collection('attendance')
        .doc(_todayDocumentId(user.uid));

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      final data =
          snapshot.data() ?? <String, dynamic>{};

      final inCount =
      _getInt(data['checkInCount']);

      final outCount =
      _getInt(data['checkOutCount']);

      // Maximum 2 check-ins per day.
      if (inCount >= 2) {
        throw Exception(
          'Maximum 2 check-ins allowed per day.',
        );
      }

      // There must not be an open check-in today.
      if (inCount != outCount) {
        throw Exception(
          'Please check out before checking in again.',
        );
      }

      final number = inCount + 1;

      final fields = <String, dynamic>{
        'userId': user.uid,
        'email': user.email,

        'employeeName':
        employee['employeeName'],

        'designation':
        employee['designation'],

        'date': _todayDate(),

        'checkInCount': number,

        'checkOutCount': outCount,

        'status': 'checked_in',

        'checkIn$number':
        FieldValue.serverTimestamp(),

        'checkIn${number}QrCode':
        qrCode,

        'checkIn${number}Latitude':
        latitude,

        'checkIn${number}Longitude':
        longitude,

        'checkIn${number}Device':
        device,
      };

      if (snapshot.exists) {
        transaction.update(ref, fields);
      } else {
        transaction.set(ref, fields);
      }
    });
  }

  // ------------------------------------------------------------
  // CHECK OUT
  // ------------------------------------------------------------

  Future<void> checkOut({
    required String qrCode,
    required double latitude,
    required double longitude,
  }) async {
    final user = auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in.');
    }

    final device =
    await deviceService.getDeviceDetails();

    final ref = firestore
        .collection('attendance')
        .doc(_todayDocumentId(user.uid));

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception(
          'Please check in before checking out.',
        );
      }

      final data = snapshot.data()!;

      final inCount =
      _getInt(data['checkInCount']);

      final outCount =
      _getInt(data['checkOutCount']);

      // Maximum 2 check-outs per day.
      if (outCount >= 2) {
        throw Exception(
          'Maximum 2 check-outs allowed per day.',
        );
      }

      // Employee must have an open check-in.
      if (inCount != outCount + 1) {
        throw Exception(
          'Please check in before checking out.',
        );
      }

      final number = outCount + 1;

      transaction.update(ref, {
        'checkOutCount': number,

        'checkOut$number':
        FieldValue.serverTimestamp(),

        'checkOut${number}QrCode':
        qrCode,

        'checkOut${number}Latitude':
        latitude,

        'checkOut${number}Longitude':
        longitude,

        'checkOut${number}Device':
        device,

        'checkOut${number}Type':
        'manual',

        'status':
        number == 2
            ? 'checked_out'
            : 'checked_out_once',
      });
    });
  }
}