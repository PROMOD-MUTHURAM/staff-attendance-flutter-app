import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminEmployeeAttendancePage extends StatefulWidget {
  const AdminEmployeeAttendancePage({super.key});

  @override
  State<AdminEmployeeAttendancePage> createState() =>
      _AdminEmployeeAttendancePageState();
}

class _AdminEmployeeAttendancePageState
    extends State<AdminEmployeeAttendancePage> {
  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  String? selectedEmployeeUid;

  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  DateTime? selectedDate;

  bool loading = true;

  List<Map<String, dynamic>> employees = [];

  List<QueryDocumentSnapshot<Map<String, dynamic>>> attendanceRecords = [];

  @override
  void initState() {
    super.initState();
    loadEmployees();
  }

  // ============================================================
  // LOAD EMPLOYEES
  // ============================================================

  Future<void> loadEmployees() async {
    try {
      final snapshot =
      await firestore.collection('employees').get();

      final result = snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          'documentId': doc.id,
          'uid': data['uid']?.toString() ?? '',
          'employeeNo': data['employeeNo']?.toString() ??
              data['employeeId']?.toString() ??
              data['userId']?.toString() ??
              doc.id,
          'employeeName':
          data['employeename']?.toString() ??
              data['employeeName']?.toString() ??
              'Unknown Employee',
          'designation':
          data['designation']?.toString() ?? '-',
        };
      }).toList();

      result.sort(
            (a, b) => a['employeeName']
            .toString()
            .toLowerCase()
            .compareTo(
          b['employeeName']
              .toString()
              .toLowerCase(),
        ),
      );

      if (!mounted) return;

      setState(() {
        employees = result;
        loading = false;
      });

      await loadAttendance();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showMessage(
        'Unable to load employees: $e',
      );
    }
  }

  // ============================================================
  // LOAD ATTENDANCE
  // ============================================================

  Future<void> loadAttendance() async {
    if (selectedEmployeeUid == null ||
        selectedEmployeeUid!.isEmpty) {
      setState(() {
        attendanceRecords = [];
      });
      return;
    }

    try {
      final snapshot = await firestore
          .collection('attendance')
          .where(
        'userId',
        isEqualTo: selectedEmployeeUid,
      )
          .get();

      final records = snapshot.docs.where((doc) {
        final data = doc.data();

        final date = attendanceDate(data);

        if (date == null) {
          return false;
        }

        // Specific date filter
        if (selectedDate != null) {
          return date.year == selectedDate!.year &&
              date.month == selectedDate!.month &&
              date.day == selectedDate!.day;
        }

        // Month/year filter
        return date.year == selectedYear &&
            date.month == selectedMonth;
      }).toList();

      records.sort((a, b) {
        final first = attendanceDate(a.data());
        final second = attendanceDate(b.data());

        if (first == null || second == null) {
          return 0;
        }

        return second.compareTo(first);
      });

      if (!mounted) return;

      setState(() {
        attendanceRecords = records;
      });
    } catch (e) {
      if (!mounted) return;

      showMessage(
        'Unable to load attendance: $e',
      );
    }
  }

  // ============================================================
  // ATTENDANCE DATE
  // ============================================================

  DateTime? attendanceDate(
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
      final parsed = DateTime.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    value = data['date'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String &&
        value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    value = data['checkIn1'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    value = data['checkOut1'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  // ============================================================
  // TIMESTAMP
  // ============================================================

  DateTime? timestamp(
      dynamic value,
      ) {
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

  // ============================================================
  // WORKING TIME
  // ============================================================

  Duration workingTime(
      Map<String, dynamic> data,
      ) {
    Duration total = Duration.zero;

    for (int i = 1; i <= 10; i++) {
      final checkIn =
      timestamp(data['checkIn$i']);

      final checkOut =
      timestamp(data['checkOut$i']);

      if (checkIn != null &&
          checkOut != null &&
          checkOut.isAfter(checkIn)) {
        total += checkOut.difference(checkIn);
      }
    }

    return total;
  }

  // ============================================================
  // FORMAT DURATION
  // ============================================================

  String formatDuration(
      Duration duration,
      ) {
    final hours = duration.inHours;
    final minutes =
    duration.inMinutes.remainder(60);

    return '${hours}h ${minutes}m';
  }

  // ============================================================
  // FORMAT TIME
  // ============================================================

  String formatTime(
      dynamic value,
      ) {
    final date = timestamp(value);

    if (date == null) {
      return '-';
    }

    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;

    final minute =
    date.minute.toString().padLeft(2, '0');

    final period =
    date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

  String formatDate(
      DateTime? date,
      ) {
    if (date == null) {
      return '-';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ============================================================
  // MONTH NAME
  // ============================================================

  String monthName(
      int month,
      ) {
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

  // ============================================================
  // SELECTED EMPLOYEE
  // ============================================================

  Map<String, dynamic>? get selectedEmployee {
    for (final employee in employees) {
      if (employee['uid'] ==
          selectedEmployeeUid) {
        return employee;
      }
    }

    return null;
  }

  // ============================================================
  // PRESENT DAYS
  // ============================================================

  int get presentDays {
    return attendanceRecords.length;
  }

  // ============================================================
  // TOTAL WORKING HOURS
  // ============================================================

  Duration get totalWorkingHours {
    Duration total = Duration.zero;

    for (final record in attendanceRecords) {
      total += workingTime(record.data());
    }

    return total;
  }

  // ============================================================
  // DEVICE
  // ============================================================

  Map<String, dynamic>? deviceOf(
      Map<String, dynamic> data,
      String event,
      ) {
    final value =
    data['${event}Device'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  // ============================================================
  // DEVICE NAME
  // ============================================================

  String deviceName(
      Map<String, dynamic>? device,
      ) {
    if (device == null) {
      return '-';
    }

    final manufacturer =
        device['manufacturer']?.toString() ?? '';

    final model =
        device['model']?.toString() ?? '';

    final parts = [
      manufacturer,
      model,
    ].where(
          (value) => value.isNotEmpty,
    );

    final result = parts.join(' ');

    return result.isEmpty ? '-' : result;
  }

  // ============================================================
  // OPERATING SYSTEM
  // ============================================================

  String operatingSystem(
      Map<String, dynamic>? device,
      ) {
    if (device == null) {
      return '-';
    }

    final platform =
        device['platform']?.toString() ?? '';

    if (platform == 'Android') {
      return 'Android '
          '${device['androidVersion'] ?? '-'}';
    }

    if (platform == 'iOS') {
      return 'iOS '
          '${device['iosVersion'] ?? '-'}';
    }

    return platform.isEmpty
        ? '-'
        : platform;
  }

  // ============================================================
  // QR CODE
  // ============================================================

  String eventValue(
      Map<String, dynamic> data,
      String event,
      String suffix,
      ) {
    final value =
    data['$event$suffix'];

    if (value == null) {
      return '-';
    }

    return value.toString();
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void showMessage(
      String message,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

  Future<void> selectDate() async {
    final picked =
    await showDatePicker(
      context: context,
      initialDate:
      selectedDate ?? DateTime.now(),
      firstDate:
      DateTime(2020),
      lastDate:
      DateTime.now(),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      selectedDate = picked;
    });

    await loadAttendance();
  }

  // ============================================================
  // CLEAR DATE
  // ============================================================

  Future<void> clearDate() async {
    setState(() {
      selectedDate = null;
    });

    await loadAttendance();
  }

  // ============================================================
  // EMPLOYEE DROPDOWN
  // ============================================================

  Widget employeeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedEmployeeUid,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Employee',
        border: OutlineInputBorder(),
        prefixIcon:
        Icon(Icons.person),
      ),
      hint: const Text(
        'Select Employee',
      ),
      items: employees.map(
            (employee) {
          return DropdownMenuItem<String>(
            value:
            employee['uid']
                .toString(),
            child: Text(
              '${employee['employeeName']} '
                  '(${employee['employeeNo']})',
              overflow:
              TextOverflow.ellipsis,
            ),
          );
        },
      ).toList(),
      onChanged: (value) async {
        setState(() {
          selectedEmployeeUid =
              value;
          selectedDate = null;
        });

        await loadAttendance();
      },
    );
  }

  // ============================================================
  // FILTER SECTION
  // ============================================================

  Widget filterSection() {
    final currentYear =
        DateTime.now().year;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance Filters',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 14),

            employeeDropdown(),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child:
                  DropdownButtonFormField<int>(
                    value: selectedMonth,
                    decoration:
                    const InputDecoration(
                      labelText: 'Month',
                      border:
                      OutlineInputBorder(),
                    ),
                    items:
                    List.generate(
                      12,
                          (index) {
                        final month =
                            index + 1;

                        return DropdownMenuItem<
                            int>(
                          value: month,
                          child: Text(
                            monthName(
                              month,
                            ),
                          ),
                        );
                      },
                    ),
                    onChanged:
                        (value) async {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        selectedMonth =
                            value;
                        selectedDate =
                        null;
                      });

                      await loadAttendance();
                    },
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child:
                  DropdownButtonFormField<int>(
                    value: selectedYear,
                    decoration:
                    const InputDecoration(
                      labelText: 'Year',
                      border:
                      OutlineInputBorder(),
                    ),
                    items:
                    List.generate(
                      6,
                          (index) {
                        final year =
                            currentYear -
                                index;

                        return DropdownMenuItem<
                            int>(
                          value: year,
                          child: Text(
                            year.toString(),
                          ),
                        );
                      },
                    ),
                    onChanged:
                        (value) async {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        selectedYear =
                            value;
                        selectedDate =
                        null;
                      });

                      await loadAttendance();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                    selectDate,
                    icon: const Icon(
                      Icons.calendar_today,
                    ),
                    label: Text(
                      selectedDate == null
                          ? 'Select Date'
                          : formatDate(
                        selectedDate,
                      ),
                    ),
                  ),
                ),

                if (selectedDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip:
                    'Clear date',
                    onPressed:
                    clearDate,
                    icon: const Icon(
                      Icons.clear,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SUMMARY
  // ============================================================

  Widget summarySection() {
    final employee =
        selectedEmployee;

    return Column(
      children: [
        if (employee != null)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child:
                Icon(Icons.person),
              ),
              title: Text(
                employee['employeeName']
                    .toString(),
                style:
                const TextStyle(
                  fontWeight:
                  FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${employee['employeeNo']} • '
                    '${employee['designation']}',
              ),
            ),
          ),

        Row(
          children: [
            Expanded(
              child: summaryCard(
                'Days Present',
                '$presentDays',
                Icons.event_available,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: summaryCard(
                'Working Hours',
                formatDuration(
                  totalWorkingHours,
                ),
                Icons.access_time,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget summaryCard(
      String title,
      String value,
      IconData icon,
      ) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              size: 30,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight:
                FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign:
              TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ATTENDANCE CARD
  // ============================================================

  Widget attendanceCard(
      QueryDocumentSnapshot<
          Map<String, dynamic>>
      document,
      ) {
    final data = document.data();

    final date =
    attendanceDate(data);

    final duration =
    workingTime(data);

    return Card(
      margin:
      const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding:
        const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatDate(date),
                    style:
                    const TextStyle(
                      fontSize: 17,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  formatDuration(
                    duration,
                  ),
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ],
            ),

            const Divider(),

            // Check In 1
            eventRow(
              'Check In 1',
              data,
              'checkIn1',
            ),

            eventRow(
              'Check Out 1',
              data,
              'checkOut1',
            ),

            // Check In 2
            eventRow(
              'Check In 2',
              data,
              'checkIn2',
            ),

            eventRow(
              'Check Out 2',
              data,
              'checkOut2',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EVENT ROW
  // ============================================================

  Widget eventRow(
      String title,
      Map<String, dynamic> data,
      String event,
      ) {
    final time =
    formatTime(data[event]);

    final qr =
    eventValue(
      data,
      event,
      'QrCode',
    );

    final latitude =
    eventValue(
      data,
      event,
      'Latitude',
    );

    final longitude =
    eventValue(
      data,
      event,
      'Longitude',
    );

    final device =
    deviceOf(
      data,
      event,
    );

    return ExpansionTile(
      tilePadding:
      EdgeInsets.zero,
      leading: Icon(
        event.startsWith('checkIn')
            ? Icons.login
            : Icons.logout,
        color:
        event.startsWith('checkIn')
            ? Colors.green
            : Colors.orange,
      ),
      title: Text(
        title,
        style:
        const TextStyle(
          fontWeight:
          FontWeight.w600,
        ),
      ),
      trailing: Text(
        time,
        style:
        const TextStyle(
          fontWeight:
          FontWeight.bold,
        ),
      ),
      children: [
        detailRow(
          'Time',
          time,
        ),
        detailRow(
          'QR Location',
          qr,
        ),
        detailRow(
          'Latitude',
          latitude,
        ),
        detailRow(
          'Longitude',
          longitude,
        ),
        detailRow(
          'Device',
          deviceName(device),
        ),
        detailRow(
          'Operating System',
          operatingSystem(device),
        ),
      ],
    );
  }

  // ============================================================
  // DETAIL ROW
  // ============================================================

  Widget detailRow(
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style:
              const TextStyle(
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Employee Attendance',
        ),
        centerTitle: true,
      ),
      body: loading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: () async {
          await loadEmployees();
          await loadAttendance();
        },
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets.all(16),
          children: [
            const Text(
              'Check Employee Attendance',
              style: TextStyle(
                fontSize: 24,
                fontWeight:
                FontWeight.bold,
                  color: Color(0xFFFFEE58),
              ),
            ),

            const SizedBox(height: 5),

            Text(
              'View employee attendance, check-in, check-out and working hours.',
              style: TextStyle(
                  color: Color(0xFFFFEE58),
              ),
            ),

            const SizedBox(height: 16),

            filterSection(),

            const SizedBox(height: 12),

            if (selectedEmployeeUid == null)
              const Card(
                child: Padding(
                  padding:
                  EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_search,
                        size: 55,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Select an employee to view attendance.',
                        textAlign:
                        TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            if (selectedEmployeeUid != null)
              summarySection(),

            const SizedBox(height: 12),

            if (selectedEmployeeUid != null &&
                attendanceRecords.isEmpty)
              const Card(
                child: Padding(
                  padding:
                  EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 55,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No attendance records found for the selected filter.',
                        textAlign:
                        TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            if (attendanceRecords.isNotEmpty)
              ...attendanceRecords.map(
                    (record) =>
                    attendanceCard(
                      record,
                    ),
              ),

            const SizedBox(
              height: 30,
            ),
          ],
        ),
      ),
    );
  }
}