import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MyAttendancePage extends StatefulWidget {
  const MyAttendancePage({super.key});

  @override
  State<MyAttendancePage> createState() => _MyAttendancePageState();
}

class _MyAttendancePageState extends State<MyAttendancePage> {
  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth auth =
      FirebaseAuth.instance;

  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  bool loadingEmployee = true;

  String employeeName = '';
  String designation = '';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> attendanceRecords =
  [];

  bool loadingAttendance = true;

  @override
  void initState() {
    super.initState();

    loadEmployeeDetails();
    loadAttendance();
  }

  // ------------------------------------------------------------
  // LOAD EMPLOYEE DETAILS
  // ------------------------------------------------------------

  Future<void> loadEmployeeDetails() async {
    try {
      final user = auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          employeeName = 'Employee';
          designation = '';
          loadingEmployee = false;
        });

        return;
      }

      final query = await firestore
          .collection('employees')
          .where(
        'uid',
        isEqualTo: user.uid,
      )
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();

        setState(() {
          employeeName =
              (data['employeename'] ??
                  data['employeeName'] ??
                  'Employee')
                  .toString();

          designation =
              (data['designation'] ?? '').toString();

          loadingEmployee = false;
        });
      } else {
        setState(() {
          employeeName = 'Employee';
          designation = '';
          loadingEmployee = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        employeeName = 'Employee';
        designation = '';
        loadingEmployee = false;
      });
    }
  }

  // ------------------------------------------------------------
  // LOAD ATTENDANCE
  // ------------------------------------------------------------

  Future<void> loadAttendance() async {
    setState(() {
      loadingAttendance = true;
    });

    try {
      final user = auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          attendanceRecords = [];
          loadingAttendance = false;
        });

        return;
      }

      final snapshot = await firestore
          .collection('attendance')
          .where(
        'userId',
        isEqualTo: user.uid,
      )
          .get();

      final records = snapshot.docs.where((doc) {
        final data = doc.data();

        final date = getAttendanceDate(data);

        if (date == null) {
          return false;
        }

        return date.year == selectedYear &&
            date.month == selectedMonth;
      }).toList();

      records.sort((a, b) {
        final dateA = getAttendanceDate(a.data());
        final dateB = getAttendanceDate(b.data());

        if (dateA == null || dateB == null) {
          return 0;
        }

        return dateB.compareTo(dateA);
      });

      if (!mounted) return;

      setState(() {
        attendanceRecords = records;
        loadingAttendance = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        attendanceRecords = [];
        loadingAttendance = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to load attendance: $e',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // GET ATTENDANCE DATE
  // ------------------------------------------------------------

  DateTime? getAttendanceDate(
      Map<String, dynamic> data,
      ) {
    dynamic value = data['attendanceDate'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    // Fallback to Check In 1
    value = data['checkIn1'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    // Fallback to Check Out 1
    value = data['checkOut1'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  // ------------------------------------------------------------
  // GET TIMESTAMP
  // ------------------------------------------------------------

  DateTime? getTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  // ------------------------------------------------------------
  // FORMAT TIME
  // ------------------------------------------------------------

  String formatTime(DateTime? time) {
    if (time == null) {
      return '--';
    }

    final hour = time.hour > 12
        ? time.hour - 12
        : time.hour == 0
        ? 12
        : time.hour;

    final minute =
    time.minute.toString().padLeft(2, '0');

    final period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  // ------------------------------------------------------------
  // FORMAT DATE
  // ------------------------------------------------------------

  String formatDate(DateTime date) {
    final day =
    date.day.toString().padLeft(2, '0');

    final month =
    date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  // ------------------------------------------------------------
  // CALCULATE WORKING TIME
  // ------------------------------------------------------------

  Duration calculateWorkingTime(
      Map<String, dynamic> data,
      ) {
    Duration total = Duration.zero;

    for (int i = 1; i <= 10; i++) {
      final checkIn =
      getTimestamp(data['checkIn$i']);

      final checkOut =
      getTimestamp(data['checkOut$i']);

      if (checkIn != null && checkOut != null) {
        if (checkOut.isAfter(checkIn)) {
          total += checkOut.difference(checkIn);
        }
      }
    }

    return total;
  }

  // ------------------------------------------------------------
  // FORMAT DURATION
  // ------------------------------------------------------------

  String formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes =
    duration.inMinutes.remainder(60);

    return '${hours}h ${minutes}m';
  }

  // ------------------------------------------------------------
  // MONTH NAME
  // ------------------------------------------------------------

  String monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  // ------------------------------------------------------------
  // PRESENT DAYS
  // ------------------------------------------------------------

  int get presentDays {
    return attendanceRecords.length;
  }

  // ------------------------------------------------------------
  // TOTAL WORKING HOURS
  // ------------------------------------------------------------

  Duration get totalWorkingTime {
    Duration total = Duration.zero;

    for (final record in attendanceRecords) {
      total += calculateWorkingTime(
        record.data(),
      );
    }

    return total;
  }

  // ------------------------------------------------------------
  // BUILD EMPLOYEE HEADER
  // ------------------------------------------------------------

  Widget buildEmployeeHeader() {
    return Card(
      margin: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        8,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 30,
              child: Icon(
                Icons.person,
                size: 34,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: loadingEmployee
                  ? const Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 20,
                    width: 150,
                    child: LinearProgressIndicator(),
                  ),
                  SizedBox(height: 8),
                  SizedBox(
                    height: 16,
                    width: 100,
                    child: LinearProgressIndicator(),
                  ),
                ],
              )
                  : Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (designation.isNotEmpty) ...[
                    const SizedBox(height: 5),

                    Text(
                      designation,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            IconButton(
              tooltip: 'Refresh',
              onPressed: () {
                loadEmployeeDetails();
                loadAttendance();
              },
              icon: const Icon(
                Icons.refresh,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD FILTERS
  // ------------------------------------------------------------

  Widget buildFilters() {
    final currentYear = DateTime.now().year;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'Month',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  12,
                      (index) {
                    final month = index + 1;

                    return DropdownMenuItem<int>(
                      value: month,
                      child: Text(
                        monthName(month),
                      ),
                    );
                  },
                ),
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    selectedMonth = value;
                  });

                  loadAttendance();
                },
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: DropdownButtonFormField<int>(
                value: selectedYear,
                decoration: const InputDecoration(
                  labelText: 'Year',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  5,
                      (index) {
                    final year =
                        currentYear - index;

                    return DropdownMenuItem<int>(
                      value: year,
                      child: Text(
                        year.toString(),
                      ),
                    );
                  },
                ),
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    selectedYear = value;
                  });

                  loadAttendance();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // SUMMARY CARDS
  // ------------------------------------------------------------

  Widget buildSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    const Icon(
                      Icons.event_available,
                      size: 30,
                      color: Colors.green,
                    ),

                    const SizedBox(height: 6),

                    Text(
                      presentDays.toString(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    const Text(
                      'Present Days',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 30,
                      color: Colors.blue,
                    ),

                    const SizedBox(height: 6),

                    Text(
                      formatDuration(
                        totalWorkingTime,
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    const Text(
                      'Working Hours',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD ATTENDANCE RECORD
  // ------------------------------------------------------------

  Widget buildAttendanceCard(
      QueryDocumentSnapshot<
          Map<String, dynamic>>
      document,
      ) {
    final data = document.data();

    final date = getAttendanceDate(data);

    final workingTime =
    calculateWorkingTime(data);

    final List<Widget> sessions = [];

    for (int i = 1; i <= 10; i++) {
      final checkIn =
      getTimestamp(data['checkIn$i']);

      final checkOut =
      getTimestamp(data['checkOut$i']);

      if (checkIn == null && checkOut == null) {
        continue;
      }

      sessions.add(
        Container(
          margin: const EdgeInsets.only(
            top: 8,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius:
            BorderRadius.circular(8),
            color: Colors.grey.shade100,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.login,
                    size: 20,
                    color: Colors.green,
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    'Check In',
                    style: TextStyle(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    formatTime(checkIn),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  const Icon(
                    Icons.logout,
                    size: 20,
                    color: Colors.orange,
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    'Check Out',
                    style: TextStyle(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    formatTime(checkOut),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 22,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    date == null
                        ? 'Unknown Date'
                        : formatDate(date),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Text(
                  date == null
                      ? ''
                      : _weekdayName(date.weekday),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),

            if (sessions.isNotEmpty)
              ...sessions,

            const SizedBox(height: 10),

            const Divider(),

            Row(
              children: [
                const Icon(
                  Icons.timer,
                  size: 20,
                  color: Colors.blue,
                ),

                const SizedBox(width: 8),

                const Text(
                  'Total Working Time',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Spacer(),

                Text(
                  formatDuration(workingTime),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayName(int weekday) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return weekdays[weekday - 1];
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Attendance',
        ),
        centerTitle: true,
      ),

      body: RefreshIndicator(
        onRefresh: () async {
          await loadEmployeeDetails();
          await loadAttendance();
        },

        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),

          children: [
            // Employee name + designation
            buildEmployeeHeader(),

            // Month and year filters
            buildFilters(),

            // Summary
            buildSummary(),

            const SizedBox(height: 6),

            if (loadingAttendance)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (attendanceRecords.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy,
                      size: 60,
                      color: Colors.grey.shade500,
                    ),

                    const SizedBox(height: 15),

                    Text(
                      'No attendance records found',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '${monthName(selectedMonth)} $selectedYear',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...attendanceRecords.map(
                    (record) =>
                    buildAttendanceCard(record),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}