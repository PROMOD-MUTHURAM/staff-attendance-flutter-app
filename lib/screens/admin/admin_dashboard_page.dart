import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/export_service.dart';
import 'admin_employee_attendance_page.dart';
import 'attendance_search_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // QR IDs are resolved to the branch field in locations/{locationId}.
  final Map<String, Future<String>> _branchNameCache = {};

  bool isExporting = false;

  final ScrollController _tableHorizontalController =
  ScrollController();

  // The attendance system supports two check-ins
  // and two check-outs per employee per day.
  final List<String> events = [
    'checkIn1',
    'checkOut1',
    'checkIn2',
    'checkOut2',
  ];

  // Tracks event timestamps so the first snapshot does not trigger old alerts.
  // Notifications are shown only for attendance events added/changed afterward.
  bool _hasInitializedAttendanceSnapshot = false;
  final Map<String, int> _previousAttendanceEventValues = {};
  final List<Map<String, dynamic>> _pendingAttendanceNotifications = [];
  bool _notificationDialogShowing = false;

  // ---------------------------------------------------------------------------
  // BASIC HELPERS
  // ---------------------------------------------------------------------------

  String _stringValue(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  String _formatTimestamp(dynamic value) {
    if (value == null) return '-';

    DateTime? dateTime;

    if (value is Timestamp) {
      dateTime = value.toDate();
    } else if (value is DateTime) {
      dateTime = value;
    }

    if (dateTime == null) {
      return value.toString();
    }

    final String day = dateTime.day.toString().padLeft(2, '0');
    final String month = dateTime.month.toString().padLeft(2, '0');
    final String year = dateTime.year.toString();

    int hour = dateTime.hour;

    final String minute =
    dateTime.minute.toString().padLeft(2, '0');

    final String period = hour >= 12 ? 'PM' : 'AM';

    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }

    return '$day/$month/$year '
        '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  // ---------------------------------------------------------------------------
  // GET LATEST ATTENDANCE TIMESTAMP
  // ---------------------------------------------------------------------------
  //
  // Finds the most recent timestamp from:
  //
  // checkIn1
  // checkOut1
  // checkIn2
  // checkOut2
  //
  // This value is used to sort attendance records.
  // Newest attendance activity appears first.
  // ---------------------------------------------------------------------------

  DateTime _getLatestAttendanceTimestamp(
      Map<String, dynamic> data,
      ) {
    final List<dynamic> timestamps = [
      data['checkIn1'],
      data['checkOut1'],
      data['checkIn2'],
      data['checkOut2'],
    ];

    DateTime latest =
    DateTime.fromMillisecondsSinceEpoch(0);

    for (final value in timestamps) {
      DateTime? dateTime;

      if (value is Timestamp) {
        dateTime = value.toDate();
      } else if (value is DateTime) {
        dateTime = value;
      }

      if (dateTime != null && dateTime.isAfter(latest)) {
        latest = dateTime;
      }
    }

    return latest;
  }

  // ---------------------------------------------------------------------------
  // SORT ATTENDANCE DOCUMENTS
  // ---------------------------------------------------------------------------

  List<QueryDocumentSnapshot> _sortAttendanceDocuments(
      List<QueryDocumentSnapshot> documents,
      ) {
    final List<QueryDocumentSnapshot> sortedDocuments =
    List<QueryDocumentSnapshot>.from(documents);

    sortedDocuments.sort((a, b) {
      final dataA = Map<String, dynamic>.from(
        a.data() as Map,
      );

      final dataB = Map<String, dynamic>.from(
        b.data() as Map,
      );

      final latestA =
      _getLatestAttendanceTimestamp(dataA);

      final latestB =
      _getLatestAttendanceTimestamp(dataB);

      // Newest first.
      return latestB.compareTo(latestA);
    });

    return sortedDocuments;
  }

  String _getEmployeeName(Map<String, dynamic> data) {
    final possibleNames = [
      data['employeeName'],
      data['employeename'],
      data['employee_name'],
      data['name'],
      data['displayName'],
    ];

    for (final value in possibleNames) {
      final name = _stringValue(value);

      if (name.isNotEmpty) {
        return name;
      }
    }

    return _stringValue(data['email']).isNotEmpty
        ? _stringValue(data['email'])
        : 'Unknown Employee';
  }

  String _getDesignation(Map<String, dynamic> data) {
    final possibleValues = [
      data['designation'],
      data['employeeDesignation'],
      data['role'],
    ];

    for (final value in possibleValues) {
      final result = _stringValue(value);

      if (result.isNotEmpty) {
        return result;
      }
    }

    return '-';
  }

  int? _eventTimestampMilliseconds(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return null;
  }

  // Called for every Firestore snapshot. Existing records are used as the
  // initial baseline; only subsequent event changes generate pop-ups.
  void _checkForNewAttendanceEvents(
      List<QueryDocumentSnapshot> documents,
      ) {
    final Map<String, int> currentValues = {};
    final List<Map<String, dynamic>> newNotifications = [];

    for (final document in documents) {
      final data = Map<String, dynamic>.from(document.data() as Map);

      for (final eventName in events) {
        final milliseconds =
        _eventTimestampMilliseconds(data[eventName]);
        if (milliseconds == null) continue;

        final eventKey = '${document.id}:$eventName';
        currentValues[eventKey] = milliseconds;

        final previousValue = _previousAttendanceEventValues[eventKey];
        if (_hasInitializedAttendanceSnapshot &&
            (previousValue == null || previousValue != milliseconds)) {
          final eventLabel = switch (eventName) {
            'checkIn1' => 'Check In',
            'checkOut1' => 'Check Out',
            'checkIn2' => 'Second Check In',
            'checkOut2' => 'Second Check Out',
            _ => eventName,
          };

          newNotifications.add({
            'employeeName': _getEmployeeName(data),
            'designation': _getDesignation(data),
            'eventLabel': eventLabel,
            'timestamp': data[eventName],
            'qrCode': _getQrCode(data, eventName),
            'documentId': document.id,
            'eventKey': eventKey,
          });
        }
      }
    }

    _previousAttendanceEventValues
      ..clear()
      ..addAll(currentValues);

    if (!_hasInitializedAttendanceSnapshot) {
      _hasInitializedAttendanceSnapshot = true;
      return;
    }

    if (newNotifications.isNotEmpty) {
      _pendingAttendanceNotifications.addAll(newNotifications);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNextAttendanceNotification();
      });
    }
  }

  void _showNextAttendanceNotification() {
    if (!mounted ||
        _notificationDialogShowing ||
        _pendingAttendanceNotifications.isEmpty) {
      return;
    }

    final notification = _pendingAttendanceNotifications.removeAt(0);
    _notificationDialogShowing = true;

    final eventLabel = notification['eventLabel'] as String;
    final isCheckIn = eventLabel.toLowerCase().contains('check in');

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            isCheckIn ? Icons.login : Icons.logout,
            size: 36,
            color: isCheckIn ? Colors.green : Colors.deepOrange,
          ),
          title: Text('Employee $eventLabel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification['employeeName'] as String? ??
                    'Unknown Employee',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Designation: ${notification['designation'] ?? '-'}',
              ),
              const SizedBox(height: 6),
              Text(
                'Time: ${_formatTimestamp(notification['timestamp'])}',
              ),
              const SizedBox(height: 6),
              FutureBuilder<String>(
                future: _getBranchName(
                  notification['qrCode']?.toString() ?? '-',
                ),
                builder: (context, snapshot) {
                  final branch = snapshot.data ??
                      notification['qrCode']?.toString() ?? '-';
                  return Text('QR Location: $branch');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _notificationDialogShowing = false;
      if (mounted && _pendingAttendanceNotifications.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showNextAttendanceNotification();
        });
      }
    });
  }

  String _getEmployeeId(
      Map<String, dynamic> data,
      String documentId,
      ) {
    final possibleValues = [
      data['employeeNo'],
      data['employeeNumber'],
      data['employeeId'],
      data['userId'],
      data['uid'],
    ];

    for (final value in possibleValues) {
      final result = _stringValue(value);

      if (result.isNotEmpty) {
        return result;
      }
    }

    return documentId;
  }

  Map<String, dynamic> _getDeviceData(
      Map<String, dynamic> data,
      String type,
      ) {
    final value = data['${type}Device'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {};
  }

  String _getDeviceName(
      Map<String, dynamic> data,
      String type,
      ) {
    final device = _getDeviceData(data, type);

    final possibleValues = [
      device['model'],
      device['device'],
      device['brand'],
      device['manufacturer'],
    ];

    for (final value in possibleValues) {
      final result = _stringValue(value);

      if (result.isNotEmpty) {
        return result;
      }
    }

    return '-';
  }

  String _getOperatingSystem(
      Map<String, dynamic> data,
      String type,
      ) {
    final device = _getDeviceData(data, type);

    final platform = _stringValue(device['platform']);
    final androidVersion =
    _stringValue(device['androidVersion']);

    if (platform.isNotEmpty && androidVersion.isNotEmpty) {
      return '$platform $androidVersion';
    }

    if (platform.isNotEmpty) {
      return platform;
    }

    if (androidVersion.isNotEmpty) {
      return 'Android $androidVersion';
    }

    final iosVersion =
    _stringValue(device['iosVersion']);

    if (iosVersion.isNotEmpty) {
      return 'iOS $iosVersion';
    }

    return '-';
  }

  String _getQrCode(
      Map<String, dynamic> data,
      String type,
      ) {
    final value =
    _stringValue(data['${type}QrCode']);

    return value.isNotEmpty ? value : '-';
  }

  // Resolve the QR document ID to locations/{id}.branch.
  // If an older location has no branch field, show its QR ID as fallback.
  Future<String> _getBranchName(String qrCode) {
    final locationId = qrCode.trim();

    if (locationId.isEmpty || locationId == '-') {
      return Future.value('-');
    }

    return _branchNameCache.putIfAbsent(locationId, () async {
      final location = await _firestore
          .collection('locations')
          .doc(locationId)
          .get();

      if (!location.exists) return locationId;

      final locationData = location.data();
      final branch = _stringValue(locationData?['branch']);
      return branch.isNotEmpty ? branch : locationId;
    });
  }

  Widget _buildQrLocation(
      Map<String, dynamic> data,
      String eventName,
      ) {
    final qrCode = _getQrCode(data, eventName);

    return FutureBuilder<String>(
      future: _getBranchName(qrCode),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(qrCode);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text('Loading...');
        }
        return Text(snapshot.data ?? qrCode);
      },
    );
  }

  Widget _detailRowWithWidget(
      String title,
      Widget value, {
        IconData? icon,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 135,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  String _getLatitude(
      Map<String, dynamic> data,
      String type,
      ) {
    final value = data['${type}Latitude'];

    if (value == null) {
      return '-';
    }

    return value.toString();
  }

  String _getLongitude(
      Map<String, dynamic> data,
      String type,
      ) {
    final value = data['${type}Longitude'];

    if (value == null) {
      return '-';
    }

    return value.toString();
  }

  int _getCheckInCount(Map<String, dynamic> data) {
    final storedCount = data['checkInCount'];

    if (storedCount is int) {
      return storedCount;
    }

    int count = 0;

    for (int i = 1; i <= 2; i++) {
      if (data['checkIn$i'] is Timestamp) {
        count++;
      }
    }

    return count;
  }

  int _getCheckOutCount(Map<String, dynamic> data) {
    final storedCount = data['checkOutCount'];

    if (storedCount is int) {
      return storedCount;
    }

    int count = 0;

    for (int i = 1; i <= 2; i++) {
      if (data['checkOut$i'] is Timestamp) {
        count++;
      }
    }

    return count;
  }

  String _getStatus(Map<String, dynamic> data) {
    final checkIns = _getCheckInCount(data);
    final checkOuts = _getCheckOutCount(data);

    if (checkIns == 0) {
      return 'Absent';
    }

    if (checkIns > checkOuts) {
      return 'Currently Checked In';
    }

    return 'Checked Out';
  }

  // ---------------------------------------------------------------------------
  // EXPORT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _createExportRows(
      List<QueryDocumentSnapshot> documents,
      ) async {
    final List<Map<String, dynamic>> rows = [];

    for (final document in documents) {
      final data = Map<String, dynamic>.from(
        document.data() as Map,
      );

      final employeeName = _getEmployeeName(data);
      final designation = _getDesignation(data);
      final status = _getStatus(data);

      final branchName = await _getBranchName(
        _getQrCode(data, 'checkIn1'),
      );

      rows.add({
        'Employee': employeeName,
        'Designation': designation,
        'Status': status,
        'Check In 1':
        _formatTimestamp(data['checkIn1']),
        'Check Out 1':
        _formatTimestamp(data['checkOut1']),
        'Check In 2':
        _formatTimestamp(data['checkIn2']),
        'Check Out 2':
        _formatTimestamp(data['checkOut2']),
        'QR Location': branchName,
        'Latitude':
        _getLatitude(data, 'checkIn1'),
        'Longitude':
        _getLongitude(data, 'checkIn1'),
        'Device':
        _getDeviceName(data, 'checkIn1'),
        'OS':
        _getOperatingSystem(data, 'checkIn1'),
      });
    }

    return rows;
  }

  Future<void> _exportData(
      List<QueryDocumentSnapshot> documents,
      bool excel,
      ) async {
    if (documents.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No attendance records available to export.',
          ),
        ),
      );

      return;
    }

    setState(() {
      isExporting = true;
    });

    try {
      final rows = await _createExportRows(documents);

      if (excel) {
        await ExportService.exportExcel(rows);
      } else {
        await ExportService.exportCsv(rows);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            excel
                ? 'Excel file exported successfully.'
                : 'CSV file exported successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isExporting = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ATTENDANCE DETAILS
  // ---------------------------------------------------------------------------

  Widget _detailRow(
      String title,
      String value, {
        IconData? icon,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 20,
              color:
              Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 135,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventDetails(
      Map<String, dynamic> data,
      String eventName,
      String displayName,
      ) {
    final timestamp = data[eventName];

    if (timestamp == null) {
      return const SizedBox.shrink();
    }

    final device =
    _getDeviceData(data, eventName);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const Divider(),

            _detailRow(
              'Date & Time',
              _formatTimestamp(timestamp),
              icon: Icons.access_time,
            ),

            _detailRowWithWidget(
              'QR Location',
              _buildQrLocation(data, eventName),
              icon: Icons.qr_code,
            ),

            _detailRow(
              'Latitude',
              _getLatitude(data, eventName),
              icon: Icons.location_on,
            ),

            _detailRow(
              'Longitude',
              _getLongitude(data, eventName),
              icon: Icons.location_on,
            ),

            _detailRow(
              'Device',
              _getDeviceName(data, eventName),
              icon: Icons.phone_android,
            ),

            _detailRow(
              'Operating System',
              _getOperatingSystem(
                data,
                eventName,
              ),
              icon: Icons.settings,
            ),

            if (device['brand'] != null)
              _detailRow(
                'Brand',
                _stringValue(device['brand']),
              ),

            if (device['manufacturer'] != null)
              _detailRow(
                'Manufacturer',
                _stringValue(
                  device['manufacturer'],
                ),
              ),

            if (device['model'] != null)
              _detailRow(
                'Model',
                _stringValue(device['model']),
              ),

            if (device['device'] != null)
              _detailRow(
                'Device ID',
                _stringValue(device['device']),
              ),

            if (device['androidSdk'] != null)
              _detailRow(
                'Android SDK',
                _stringValue(
                  device['androidSdk'],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAttendanceDetails(
      BuildContext context,
      QueryDocumentSnapshot document,
      ) {
    final data = Map<String, dynamic>.from(
      document.data() as Map,
    );

    final employeeName =
    _getEmployeeName(data);

    final employeeId =
    _getEmployeeId(data, document.id);

    final designation =
    _getDesignation(data);

    final status =
    _getStatus(data);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              CircleAvatar(
                child: Text(
                  employeeName.isNotEmpty
                      ? employeeName[0].toUpperCase()
                      : '?',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  employeeName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  _detailRow(
                    'Employee ID',
                    employeeId,
                    icon: Icons.badge,
                  ),

                  _detailRow(
                    'Designation',
                    designation,
                    icon: Icons.work,
                  ),

                  _detailRow(
                    'Status',
                    status,
                    icon: Icons.info,
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Attendance Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildEventDetails(
                    data,
                    'checkIn1',
                    'Check In 1',
                  ),

                  _buildEventDetails(
                    data,
                    'checkOut1',
                    'Check Out 1',
                  ),

                  _buildEventDetails(
                    data,
                    'checkIn2',
                    'Check In 2',
                  ),

                  _buildEventDetails(
                    data,
                    'checkOut2',
                    'Check Out 2',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY CARD
  // ---------------------------------------------------------------------------

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: 0.12,
                ),
                borderRadius:
                BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SMALL INFO
  // ---------------------------------------------------------------------------

  Widget _smallInfo(
      String title,
      String value, {
        IconData? icon,
      }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Padding(
            padding:
            const EdgeInsets.only(right: 5),
            child: Icon(
              icon,
              size: 16,
              color:
              Theme.of(context).colorScheme.primary,
            ),
          ),

        Expanded(
          child: RichText(
            text: TextSpan(
              style:
              DefaultTextStyle.of(context)
                  .style,
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: value,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE ATTENDANCE CARD
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // MOBILE ATTENDANCE CARD
  // Compact layout for phones and narrow screens.
  // GPS/device details remain available in the full-details dialog.
  // ---------------------------------------------------------------------------

  Widget _buildAttendanceCard(
      QueryDocumentSnapshot document,
      ) {
    final data = Map<String, dynamic>.from(
      document.data() as Map,
    );

    final employeeName = _getEmployeeName(data);
    final designation = _getDesignation(data);
    final status = _getStatus(data);

    final checkIn1 = data['checkIn1'];
    final checkOut1 = data['checkOut1'];
    final checkIn2 = data['checkIn2'];
    final checkOut2 = data['checkOut2'];

    final hasSecondAttendance =
        checkIn2 != null || checkOut2 != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _showAttendanceDetails(
            context,
            document,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // EMPLOYEE HEADER
              // -------------------------------------------------------------
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Text(
                      employeeName.isNotEmpty
                          ? employeeName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context)
                            .colorScheme
                            .primary,
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          designation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 6),

                  Flexible(
                    child: _statusChip(status),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Divider(height: 1),

              const SizedBox(height: 8),

              // -------------------------------------------------------------
              // CHECK IN / CHECK OUT TIMES
              // -------------------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: _mobileAttendanceTime(
                      label: 'Check In 1',
                      value: _formatTimestamp(checkIn1),
                      icon: Icons.login_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _mobileAttendanceTime(
                      label: 'Check Out 1',
                      value: _formatTimestamp(checkOut1),
                      icon: Icons.logout_outlined,
                    ),
                  ),
                ],
              ),

              if (hasSecondAttendance) ...[
                const SizedBox(height: 7),

                Row(
                  children: [
                    Expanded(
                      child: _mobileAttendanceTime(
                        label: 'Check In 2',
                        value: _formatTimestamp(checkIn2),
                        icon: Icons.login_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _mobileAttendanceTime(
                        label: 'Check Out 2',
                        value: _formatTimestamp(checkOut2),
                        icon: Icons.logout_outlined,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 7),

              // -------------------------------------------------------------
              // SMALL DETAILS BUTTON
              // -------------------------------------------------------------
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    _showAttendanceDetails(
                      context,
                      document,
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: const Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileAttendanceTime({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 15,
          color: Colors.black54,
        ),

        const SizedBox(width: 5),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 1),

              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STATUS CHIP
  // ---------------------------------------------------------------------------

  Widget _statusChip(String status) {
    Color color;

    if (status == 'Currently Checked In') {
      color = Colors.green;
    } else if (status == 'Checked Out') {
      color = Colors.blue;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DESKTOP TABLE
  // ---------------------------------------------------------------------------

  Widget _buildDesktopTable(
      List<QueryDocumentSnapshot> documents,
      ) {
    return Scrollbar(
      controller: _tableHorizontalController,
      thumbVisibility: true,
      trackVisibility: true,
      scrollbarOrientation:
      ScrollbarOrientation.bottom,
      child: SingleChildScrollView(
        controller:
        _tableHorizontalController,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 22,
          headingRowHeight: 55,
          dataRowMinHeight: 75,
          dataRowMaxHeight: 95,
          columns: const [
            DataColumn(
              label: Text(
                'Employee',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Designation',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Check In 1',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Check Out 1',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Check In 2',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Check Out 2',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'QR Location',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Latitude',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Longitude',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Device',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'OS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          rows: documents.map((document) {
            final data =
            Map<String, dynamic>.from(
              document.data() as Map,
            );

            final employeeName =
            _getEmployeeName(data);

            final designation =
            _getDesignation(data);

            final status =
            _getStatus(data);

            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      employeeName,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                  ),
                ),

                DataCell(
                  SizedBox(
                    width: 120,
                    child: Text(
                      designation,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                  ),
                ),

                DataCell(
                  _statusChip(status),
                ),

                DataCell(
                  Text(
                    _formatTimestamp(
                      data['checkIn1'],
                    ),
                  ),
                ),

                DataCell(
                  Text(
                    _formatTimestamp(
                      data['checkOut1'],
                    ),
                  ),
                ),

                DataCell(
                  Text(
                    _formatTimestamp(
                      data['checkIn2'],
                    ),
                  ),
                ),

                DataCell(
                  Text(
                    _formatTimestamp(
                      data['checkOut2'],
                    ),
                  ),
                ),

                DataCell(
                  _buildQrLocation(data, 'checkIn1'),
                ),

                DataCell(
                  Text(
                    _getLatitude(
                      data,
                      'checkIn1',
                    ),
                  ),
                ),

                DataCell(
                  Text(
                    _getLongitude(
                      data,
                      'checkIn1',
                    ),
                  ),
                ),

                DataCell(
                  Text(
                    _getDeviceName(
                      data,
                      'checkIn1',
                    ),
                  ),
                ),

                DataCell(
                  Text(
                    _getOperatingSystem(
                      data,
                      'checkIn1',
                    ),
                  ),
                ),

                DataCell(
                  IconButton(
                    tooltip:
                    'View full details',
                    icon: const Icon(
                      Icons.visibility,
                    ),
                    onPressed: () {
                      _showAttendanceDetails(
                        context,
                        document,
                      );
                    },
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              _branchNameCache.clear();
              setState(() {});
            },
            icon: const Icon(
              Icons.refresh,
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance
                  .signOut();
            },
            icon: const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('attendance')
            .limit(500)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding:
                const EdgeInsets.all(24),
                child: Text(
                  'Error loading attendance records:\n\n'
                      '${snapshot.error}',
                  textAlign:
                  TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child:
              CircularProgressIndicator(),
            );
          }

          final documents =
              snapshot.data?.docs ?? [];

          // Trigger a pop-up only when a new attendance event arrives after
          // the dashboard's initial Firestore snapshot.
          _checkForNewAttendanceEvents(documents);

          // -----------------------------------------------------------------
          // SORT RECORDS BY MOST RECENT ATTENDANCE ACTIVITY
          // -----------------------------------------------------------------
          //
          // The newest timestamp from:
          //
          // checkIn1
          // checkOut1
          // checkIn2
          // checkOut2
          //
          // is used for sorting.
          //
          // Newest record -> first
          // Oldest record -> last
          // -----------------------------------------------------------------

          final sortedDocuments =
          _sortAttendanceDocuments(
            documents,
          );

          // -----------------------------------------------------------------
          // TODAY'S SUMMARY
          // -----------------------------------------------------------------

          final now = DateTime.now();

          final todayStart = DateTime(
            now.year,
            now.month,
            now.day,
          );

          final tomorrowStart =
          todayStart.add(
            const Duration(days: 1),
          );

          int todayRecords = 0;

          final Set<String> employeesToday =
          {};

          final Set<String>
          currentlyCheckedInEmployees = {};

          for (final document in documents) {
            final data =
            Map<String, dynamic>.from(
              document.data() as Map,
            );

            bool hasTodayAttendance = false;

            for (final event in events) {
              final value = data[event];

              if (value is Timestamp) {
                final date =
                value.toDate();

                if (!date.isBefore(
                  todayStart,
                ) &&
                    date.isBefore(
                      tomorrowStart,
                    )) {
                  hasTodayAttendance = true;
                  break;
                }
              }
            }

            if (hasTodayAttendance) {
              todayRecords++;

              final employeeKey =
              _stringValue(
                data['userId'],
              ).isNotEmpty
                  ? _stringValue(
                data['userId'],
              )
                  : document.id;

              employeesToday.add(
                employeeKey,
              );

              final checkInCount =
              _getCheckInCount(data);

              final checkOutCount =
              _getCheckOutCount(data);

              if (checkInCount >
                  checkOutCount) {
                currentlyCheckedInEmployees
                    .add(employeeKey);
              }
            }
          }

          // -----------------------------------------------------------------
          // MAIN CONTENT
          // -----------------------------------------------------------------

          return RefreshIndicator(
            onRefresh: () async {
              _branchNameCache.clear();
              setState(() {});
            },
            child: SingleChildScrollView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding:
              const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  // -----------------------------------------------------------
                  // HEADER
                  // -----------------------------------------------------------

                  const Text(
                    'Attendance Dashboard',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight:
                      FontWeight.bold,
                      color: Color(0xFFFFEE58),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Today: '
                        '${now.day.toString().padLeft(2, '0')}/'
                        '${now.month.toString().padLeft(2, '0')}/'
                        '${now.year}',
                    style: TextStyle(
                      color: Color(0xFFFFEE58),
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // -----------------------------------------------------------
                  // SUMMARY CARDS
                  // -----------------------------------------------------------

                  LayoutBuilder(
                    builder: (
                        context,
                        constraints,
                        ) {
                      if (constraints.maxWidth >=
                          900) {
                        return Row(
                          children: [
                            Expanded(
                              child:
                              _buildSummaryCard(
                                title:
                                'Today Records',
                                value:
                                todayRecords
                                    .toString(),
                                icon:
                                Icons.today,
                                color:
                                Colors.blue,
                              ),
                            ),

                            const SizedBox(
                              width: 16,
                            ),

                            Expanded(
                              child:
                              _buildSummaryCard(
                                title:
                                'Employees Today',
                                value:
                                employeesToday
                                    .length
                                    .toString(),
                                icon:
                                Icons.people,
                                color:
                                Colors.green,
                              ),
                            ),

                            const SizedBox(
                              width: 16,
                            ),

                            Expanded(
                              child:
                              _buildSummaryCard(
                                title:
                                'Currently Checked In',
                                value:
                                currentlyCheckedInEmployees
                                    .length
                                    .toString(),
                                icon:
                                Icons.login,
                                color:
                                Colors.orange,
                              ),
                            ),
                          ],
                        );
                      }

                      if (constraints.maxWidth >=
                          550) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child:
                                  _buildSummaryCard(
                                    title:
                                    'Today Records',
                                    value:
                                    todayRecords
                                        .toString(),
                                    icon:
                                    Icons.today,
                                    color:
                                    Colors.blue,
                                  ),
                                ),

                                const SizedBox(
                                  width: 16,
                                ),

                                Expanded(
                                  child:
                                  _buildSummaryCard(
                                    title:
                                    'Employees Today',
                                    value:
                                    employeesToday
                                        .length
                                        .toString(),
                                    icon:
                                    Icons.people,
                                    color:
                                    Colors.green,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(
                              height: 16,
                            ),

                            _buildSummaryCard(
                              title:
                              'Currently Checked In',
                              value:
                              currentlyCheckedInEmployees
                                  .length
                                  .toString(),
                              icon:
                              Icons.login,
                              color:
                              Colors.orange,
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildSummaryCard(
                            title:
                            'Today Records',
                            value:
                            todayRecords
                                .toString(),
                            icon:
                            Icons.today,
                            color:
                            Colors.blue,
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          _buildSummaryCard(
                            title:
                            'Employees Today',
                            value:
                            employeesToday
                                .length
                                .toString(),
                            icon:
                            Icons.people,
                            color:
                            Colors.green,
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          _buildSummaryCard(
                            title:
                            'Currently Checked In',
                            value:
                            currentlyCheckedInEmployees
                                .length
                                .toString(),
                            icon:
                            Icons.login,
                            color:
                            Colors.orange,
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // -----------------------------------------------------------
                  // ACTION BUTTONS
                  // -----------------------------------------------------------

                  LayoutBuilder(
                    builder: (
                        context,
                        constraints,
                        ) {
                      if (constraints.maxWidth >=
                          800) {
                        return Row(
                          children: [
                            Expanded(
                              child:
                              _buildActionCard(
                                icon:
                                Icons.search,
                                title:
                                'Search Attendance',
                                subtitle:
                                'Search attendance records by employee or date.',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const AttendanceSearchPage(),
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(
                              width: 16,
                            ),

                            Expanded(
                              child:
                              _buildActionCard(
                                icon:
                                Icons.people_alt,
                                title:
                                'Check Employee Attendance',
                                subtitle:
                                'View each employee attendance, present days and working hours.',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const AdminEmployeeAttendancePage(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildActionCard(
                            icon:
                            Icons.search,
                            title:
                            'Search Attendance',
                            subtitle:
                            'Search attendance records by employee or date.',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                  const AttendanceSearchPage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          _buildActionCard(
                            icon:
                            Icons.people_alt,
                            title:
                            'Check Employee Attendance',
                            subtitle:
                            'View each employee attendance, present days and working hours.',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                  const AdminEmployeeAttendancePage(),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // -----------------------------------------------------------
                  // ATTENDANCE RECORDS HEADER
                  // -----------------------------------------------------------

                  Card(
                    child: Padding(
                      padding:
                      const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Attendance Records',
                                      style:
                                      TextStyle(
                                        fontSize:
                                        21,
                                        fontWeight:
                                        FontWeight.bold,
                                      ),
                                    ),

                                    SizedBox(
                                      height: 4,
                                    ),

                                    Text(
                                      'Complete attendance details including check-in, check-out, GPS and device information.',
                                    ),
                                  ],
                                ),
                              ),

                              if (isExporting)
                                const Padding(
                                  padding:
                                  EdgeInsets.all(
                                    8,
                                  ),
                                  child:
                                  CircularProgressIndicator(),
                                )
                              else
                                PopupMenuButton<
                                    String>(
                                  tooltip:
                                  'Export',
                                  icon:
                                  const Icon(
                                    Icons.download,
                                  ),
                                  onSelected:
                                      (value) {
                                    if (value ==
                                        'excel') {
                                      _exportData(
                                        sortedDocuments,
                                        true,
                                      );
                                    } else if (value ==
                                        'csv') {
                                      _exportData(
                                        sortedDocuments,
                                        false,
                                      );
                                    }
                                  },
                                  itemBuilder:
                                      (context) {
                                    return const [
                                      PopupMenuItem(
                                        value:
                                        'excel',
                                        child:
                                        Row(
                                          children: [
                                            Icon(
                                              Icons
                                                  .table_chart,
                                            ),
                                            SizedBox(
                                              width:
                                              10,
                                            ),
                                            Text(
                                              'Export Excel',
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value:
                                        'csv',
                                        child:
                                        Row(
                                          children: [
                                            Icon(
                                              Icons
                                                  .description,
                                            ),
                                            SizedBox(
                                              width:
                                              10,
                                            ),
                                            Text(
                                              'Export CSV',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ];
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // -----------------------------------------------------------
                  // RECORDS
                  // -----------------------------------------------------------

                  if (documents.isEmpty)
                    Card(
                      child: Padding(
                        padding:
                        const EdgeInsets.all(
                          40,
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.event_busy,
                                size: 55,
                                color: Colors
                                    .grey
                                    .shade500,
                              ),

                              const SizedBox(
                                height: 12,
                              ),

                              const Text(
                                'No attendance records found.',
                                style:
                                TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                  FontWeight
                                      .w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (
                          context,
                          constraints,
                          ) {
                        // Desktop/tablet
                        if (constraints.maxWidth >=
                            1000) {
                          return Card(
                            child: Padding(
                              padding:
                              const EdgeInsets
                                  .all(8),
                              child:
                              _buildDesktopTable(
                                sortedDocuments,
                              ),
                            ),
                          );
                        }

                        // Mobile / narrow tablet
                        return Column(
                          children:
                          sortedDocuments
                              .map(
                            _buildAttendanceCard,
                          )
                              .toList(),
                        );
                      },
                    ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTION CARD
  // ---------------------------------------------------------------------------

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius:
        BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding:
          const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration:
                BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimaryContainer,
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                      const TextStyle(
                        fontSize: 16,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors
                            .grey
                            .shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _tableHorizontalController.dispose();
    super.dispose();
  }
}
