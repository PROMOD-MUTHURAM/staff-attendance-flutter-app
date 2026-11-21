
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/attendance_service.dart';
import '../services/location_service.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController scannerController =
  MobileScannerController();

  final LocationService locationService = LocationService();
  final AttendanceService attendanceService = AttendanceService();

  bool processing = false;
  String selectedAction = 'checkIn';

  Map<String, dynamic>? employee;
  String? employeeError;

  @override
  void initState() {
    super.initState();
    loadEmployee();
  }

  // ------------------------------------------------------------
  // LOAD EMPLOYEE DETAILS
  // ------------------------------------------------------------

  Future<void> loadEmployee() async {
    try {
      final details = await attendanceService.getEmployeeDetails();

      if (!mounted) return;

      setState(() {
        employee = details;

        if (details == null) {
          employeeError = 'Employee record not found.';
        } else {
          employeeError = null;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        employeeError =
            e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ------------------------------------------------------------
  // PROCESS QR CODE
  // ------------------------------------------------------------

  Future<void> processQr(String scannedValue) async {
    if (processing) return;

    final locationId = scannedValue.trim();

    debugPrint('================================');
    debugPrint('SCANNED QR VALUE: [$scannedValue]');
    debugPrint('PROCESSING LOCATION ID: [$locationId]');
    debugPrint('================================');

    setState(() {
      processing = true;
    });

    try {
      await scannerController.stop();

      // --------------------------------------------------------
      // VALIDATE QR CODE
      // --------------------------------------------------------

      if (locationId.isEmpty) {
        throw Exception('QR code is empty.');
      }

      // A Firestore document ID must not contain slashes.
      // Expected values: OFFICE-001, OFFICE-002, etc.
      if (locationId.contains('/')) {
        throw Exception(
          'Invalid QR code.\n\n'
              'Expected a branch ID such as OFFICE-001 or OFFICE-002.\n'
              'Scanned value: $locationId',
        );
      }

      // --------------------------------------------------------
      // GET BRANCH DETAILS FROM FIRESTORE
      // --------------------------------------------------------

      debugPrint('Reading locations/$locationId');

      final attendanceLocation =
      await locationService.getAttendanceLocation(
        locationId,
      );

      debugPrint(
        'Branch found: ${attendanceLocation.name}',
      );

      debugPrint(
        'Branch ID: ${attendanceLocation.id}',
      );

      debugPrint(
        'Branch active: ${attendanceLocation.active}',
      );

      if (!attendanceLocation.active) {
        throw Exception(
          'This attendance location is inactive.',
        );
      }

      // --------------------------------------------------------
      // GET CURRENT GPS POSITION
      // --------------------------------------------------------

      final position =
      await locationService.getCurrentLocation();

      debugPrint(
        'Current GPS: ${position.latitude}, '
            '${position.longitude}',
      );

      // --------------------------------------------------------
      // CALCULATE DISTANCE
      // --------------------------------------------------------

      final distance = locationService.calculateDistance(
        currentLatitude: position.latitude,
        currentLongitude: position.longitude,
        targetLatitude: attendanceLocation.latitude,
        targetLongitude: attendanceLocation.longitude,
      );

      debugPrint(
        'Distance from branch: ${distance.toStringAsFixed(2)} metres',
      );

      debugPrint(
        'Allowed radius: ${attendanceLocation.radiusMeters} metres',
      );

      // --------------------------------------------------------
      // VALIDATE GPS RADIUS
      // --------------------------------------------------------

      if (distance > attendanceLocation.radiusMeters) {
        throw Exception(
          'You are outside the attendance area.\n\n'
              'Branch: ${attendanceLocation.name}\n'
              'Distance: ${distance.toStringAsFixed(1)} metres\n'
              'Allowed: ${attendanceLocation.radiusMeters.toStringAsFixed(0)} metres',
        );
      }

      // --------------------------------------------------------
      // SAVE CHECK IN OR CHECK OUT
      // --------------------------------------------------------

      if (selectedAction == 'checkIn') {
        await attendanceService.checkIn(
          qrCode: locationId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } else {
        await attendanceService.checkOut(
          qrCode: locationId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      debugPrint(
        'Attendance successfully saved for $locationId',
      );

      if (!mounted) return;

      final actionName = selectedAction == 'checkIn'
          ? 'Check In'
          : 'Check Out';

      // --------------------------------------------------------
      // SUCCESS POPUP
      // --------------------------------------------------------

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              size: 60,
              color: Colors.green,
            ),
            title: Text('$actionName Successful'),
            content: Text(
              'Employee: ${employee?['employeeName'] ?? ''}\n'
                  'Branch: ${attendanceLocation.branch}\n'
                  'Distance: ${distance.toStringAsFixed(1)} metres',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      // Return to employee home page.
      Navigator.pop(context);
    } catch (e, stackTrace) {
      debugPrint('ATTENDANCE ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');

      if (!mounted) return;

      // --------------------------------------------------------
      // ERROR POPUP
      // --------------------------------------------------------

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.cancel,
              size: 60,
              color: Colors.red,
            ),
            title: const Text(
              'Attendance Not Marked',
            ),
            content: Text(
              e.toString().replaceFirst(
                'Exception: ',
                '',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      setState(() {
        processing = false;
      });

      // Allow employee to scan again.
      try {
        await scannerController.start();
      } catch (scannerError) {
        debugPrint(
          'Scanner restart error: $scannerError',
        );
      }
    }
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // BUILD UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Employee Attendance',
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ----------------------------------------------------
          // EMPLOYEE DETAILS
          // ----------------------------------------------------

          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    child: Icon(
                      Icons.person,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee?['employeeName'] ??
                              (employeeError == null
                                  ? 'Loading employee...'
                                  : 'Employee unavailable'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          employee?['designation'] ??
                              employeeError ??
                              '',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh employee details',
                    onPressed:
                    processing ? null : loadEmployee,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),

          // ----------------------------------------------------
          // SELECT ATTENDANCE ACTION
          // ----------------------------------------------------

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select Attendance Action',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFEE58),
                ),
              ),
            ),
          ),

          // ----------------------------------------------------
          // CHECK IN / CHECK OUT BUTTONS
          // ----------------------------------------------------

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: processing
                        ? null
                        : () {
                      setState(() {
                        selectedAction = 'checkIn';
                      });
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Check In'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      selectedAction == 'checkIn'
                          ? Colors.green
                          : Colors.grey.shade300,
                      foregroundColor:
                      selectedAction == 'checkIn'
                          ? Colors.white
                          : Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: processing
                        ? null
                        : () {
                      setState(() {
                        selectedAction = 'checkOut';
                      });
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Check Out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      selectedAction == 'checkOut'
                          ? Colors.orange.shade800
                          : Colors.grey.shade300,
                      foregroundColor:
                      selectedAction == 'checkOut'
                          ? Colors.white
                          : Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // INSTRUCTION
          // ----------------------------------------------------

          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              selectedAction == 'checkIn'
                  ? 'Scan the office QR code to Check In'
                  : 'Scan the office QR code to Check Out',
              style: const TextStyle(
                color: Color(0xFFFFEE58),
              ),
            ),
          ),

          // ----------------------------------------------------
          // QR SCANNER
          // ----------------------------------------------------

          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: (capture) {
                    if (processing ||
                        capture.barcodes.isEmpty) {
                      return;
                    }

                    final value =
                        capture.barcodes.first.rawValue;

                    if (value != null &&
                        value.trim().isNotEmpty) {
                      processQr(value);
                    }
                  },
                ),

                // Processing overlay
                if (processing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 20),
                          Text(
                            'Verifying location and attendance...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
