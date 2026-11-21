import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AttendanceSearchPage extends StatefulWidget {
  const AttendanceSearchPage({super.key});

  @override
  State<AttendanceSearchPage> createState() =>
      _AttendanceSearchPageState();
}

class _AttendanceSearchPageState
    extends State<AttendanceSearchPage> {
  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final TextEditingController searchController =
  TextEditingController();

  bool isSearching = false;

  String searchText = '';

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  searchResults = [];

  static const List<String> events = [
    'checkIn1',
    'checkOut1',
    'checkIn2',
    'checkOut2',
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // TIMESTAMP
  // ============================================================

  Timestamp? timestampOf(
      Map<String, dynamic> data,
      String key,
      ) {
    final value = data[key];

    if (value is Timestamp) {
      return value;
    }

    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }

    return null;
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

  String formatDate(Timestamp? timestamp) {
    if (timestamp == null) {
      return '-';
    }

    final date = timestamp.toDate();

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ============================================================
  // FORMAT TIME
  // ============================================================

  String formatTime(Timestamp? timestamp) {
    if (timestamp == null) {
      return '-';
    }

    final date = timestamp.toDate();

    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // FORMAT DATE TIME
  // ============================================================

  String formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) {
      return '-';
    }

    return '${formatDate(timestamp)} '
        '${formatTime(timestamp)}';
  }

  // ============================================================
  // EMPLOYEE NAME
  // ============================================================

  String employeeName(
      Map<String, dynamic> data,
      ) {
    final name =
        data['employeeName']?.toString().trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    final email =
        data['email']?.toString().trim() ?? '';

    if (email.isNotEmpty) {
      return email;
    }

    return data['userId']?.toString() ??
        'Unknown Employee';
  }

  // ============================================================
  // DESIGNATION
  // ============================================================

  String designation(
      Map<String, dynamic> data,
      ) {
    final value =
        data['designation']?.toString().trim() ?? '';

    return value.isEmpty ? '-' : value;
  }

  // ============================================================
  // EMAIL
  // ============================================================

  String emailOf(
      Map<String, dynamic> data,
      ) {
    final value =
        data['email']?.toString().trim() ?? '';

    return value.isEmpty ? '-' : value;
  }

  // ============================================================
  // USER ID
  // ============================================================

  String userIdOf(
      Map<String, dynamic> data,
      ) {
    final value =
        data['userId']?.toString().trim() ?? '';

    return value.isEmpty ? '-' : value;
  }

  // ============================================================
  // STATUS
  // ============================================================

  int intValue(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  String statusOf(
      Map<String, dynamic> data,
      ) {
    final checkIns =
    intValue(data['checkInCount']);

    final checkOuts =
    intValue(data['checkOutCount']);

    if (checkIns > checkOuts) {
      return 'Checked In';
    }

    if (checkIns > 0 &&
        checkOuts > 0) {
      return 'Checked Out';
    }

    final raw =
        data['status']?.toString().toLowerCase() ??
            '';

    if (raw == 'checked_in') {
      return 'Checked In';
    }

    if (raw == 'checked_out' ||
        raw == 'checked_out_once') {
      return 'Checked Out';
    }

    return raw.isEmpty
        ? 'No Attendance'
        : raw.replaceAll('_', ' ');
  }

  // ============================================================
  // STATUS COLOR
  // ============================================================

  Color statusColor(
      String status,
      ) {
    if (status == 'Checked In') {
      return Colors.orange.shade800;
    }

    if (status == 'Checked Out') {
      return Colors.green.shade700;
    }

    return Colors.grey.shade700;
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
      return Map<String, dynamic>.from(
        value,
      );
    }

    final legacy =
    data['device'];

    if (legacy is Map) {
      return Map<String, dynamic>.from(
        legacy,
      );
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
        device['manufacturer']
            ?.toString() ??
            '';

    final model =
        device['model']?.toString() ??
            '';

    final parts = [
      manufacturer,
      model,
    ]
        .where(
          (value) =>
      value.isNotEmpty,
    )
        .toList();

    return parts.isEmpty
        ? '-'
        : parts.join(' ');
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
        device['platform']
            ?.toString() ??
            '';

    if (platform == 'Android') {
      return 'Android '
          '${device['androidVersion']?.toString() ?? '-'}';
    }

    if (platform == 'iOS') {
      return 'iOS '
          '${device['iosVersion']?.toString() ?? '-'}';
    }

    return platform.isEmpty
        ? '-'
        : platform;
  }

  // ============================================================
  // EVENT VALUE
  // ============================================================

  String eventValue(
      Map<String, dynamic> data,
      String event,
      String suffix,
      ) {
    final value =
    data['$event$suffix'];

    if (value == null ||
        value.toString().isEmpty) {
      return '-';
    }

    return value.toString();
  }

  // ============================================================
  // FIRST EVENT VALUE
  // ============================================================

  String firstEventValue(
      Map<String, dynamic> data,
      String suffix,
      ) {
    for (final event in events) {
      final value =
      data['$event$suffix'];

      if (value != null &&
          value.toString().isNotEmpty) {
        return value.toString();
      }
    }

    final legacyKey =
        suffix[0].toLowerCase() +
            suffix.substring(1);

    final legacy =
    data[legacyKey];

    if (legacy != null &&
        legacy.toString().isNotEmpty) {
      return legacy.toString();
    }

    return '-';
  }

  // ============================================================
  // SEARCH VALUE CHECK
  // ============================================================

  bool recordMatchesSearch(
      Map<String, dynamic> data,
      String search,
      ) {
    final values = <String>[
      employeeName(data),
      designation(data),
      emailOf(data),
      userIdOf(data),
      data['date']?.toString() ?? '',
      statusOf(data),
      firstEventValue(
        data,
        'QrCode',
      ),
      firstEventValue(
        data,
        'Latitude',
      ),
      firstEventValue(
        data,
        'Longitude',
      ),
    ];

    for (final event in events) {
      values.addAll([
        eventValue(
          data,
          event,
          'QrCode',
        ),
        eventValue(
          data,
          event,
          'Latitude',
        ),
        eventValue(
          data,
          event,
          'Longitude',
        ),
        deviceName(
          deviceOf(data, event),
        ),
        operatingSystem(
          deviceOf(data, event),
        ),
      ]);
    }

    return values.any(
          (value) => value
          .toLowerCase()
          .contains(search),
    );
  }

  // ============================================================
  // SEARCH
  //
  // IMPORTANT:
  // Firestore is fetched ONLY when this method runs.
  // This method runs only when Enter is pressed.
  // ============================================================

  Future<void> performSearch() async {
    final value =
    searchController.text.trim();

    if (value.isEmpty) {
      setState(() {
        searchText = '';
        searchResults = [];
        isSearching = false;
      });

      return;
    }

    setState(() {
      isSearching = true;
      searchText = value.toLowerCase();
      searchResults = [];
    });

    try {
      final snapshot = await firestore
          .collection('attendance')
          .limit(500)
          .get();

      final results =
      snapshot.docs.where((document) {
        return recordMatchesSearch(
          document.data(),
          searchText,
        );
      }).toList();

      // Sort latest first.
      results.sort((a, b) {
        final aTime =
        latestTimestamp(a.data());

        final bTime =
        latestTimestamp(b.data());

        if (aTime == null &&
            bTime == null) {
          return 0;
        }

        if (aTime == null) {
          return 1;
        }

        if (bTime == null) {
          return -1;
        }

        return bTime.compareTo(aTime);
      });

      if (!mounted) return;

      setState(() {
        searchResults = results;
        isSearching = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSearching = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Search failed: $error',
            ),
            behavior:
            SnackBarBehavior.floating,
          ),
        );
    }
  }

  // ============================================================
  // LATEST TIMESTAMP
  // ============================================================

  Timestamp? latestTimestamp(
      Map<String, dynamic> data,
      ) {
    Timestamp? latest =
    timestampOf(
      data,
      'timestamp',
    );

    for (final event in events) {
      final value =
      timestampOf(
        data,
        event,
      );

      if (value != null &&
          (latest == null ||
              value.compareTo(latest) >
                  0)) {
        latest = value;
      }
    }

    return latest;
  }

  // ============================================================
  // CLEAR SEARCH
  // ============================================================

  void clearSearch() {
    searchController.clear();

    setState(() {
      searchText = '';
      searchResults = [];
      isSearching = false;
    });
  }

  // ============================================================
  // STATUS CHIP
  // ============================================================

  Widget statusChip(
      String status,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration:
      BoxDecoration(
        color: statusColor(status)
            .withOpacity(0.12),
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: statusColor(status),
          fontWeight:
          FontWeight.w600,
          fontSize: 12,
        ),
      ),
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
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
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
            child:
            SelectableText(value),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ATTENDANCE DETAILS
  // ============================================================

  void showAttendanceDetails(
      Map<String, dynamic> data,
      ) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Employee Attendance Details',
          ),
          content: SizedBox(
            width: 620,
            child:
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  detailRow(
                    'Employee Name',
                    employeeName(data),
                  ),
                  detailRow(
                    'Designation',
                    designation(data),
                  ),
                  detailRow(
                    'Email',
                    emailOf(data),
                  ),
                  detailRow(
                    'Employee/User ID',
                    userIdOf(data),
                  ),
                  detailRow(
                    'Date',
                    data['date']
                        ?.toString() ??
                        '-',
                  ),
                  detailRow(
                    'Status',
                    statusOf(data),
                  ),
                  detailRow(
                    'Check-in Count',
                    '${intValue(data['checkInCount'])}',
                  ),
                  detailRow(
                    'Check-out Count',
                    '${intValue(data['checkOutCount'])}',
                  ),
                  const Divider(
                    height: 24,
                  ),
                  for (final event
                  in events) ...[
                    Text(
                      event == 'checkIn1'
                          ? 'Check In 1'
                          : event ==
                          'checkOut1'
                          ? 'Check Out 1'
                          : event ==
                          'checkIn2'
                          ? 'Check In 2'
                          : 'Check Out 2',
                      style:
                      const TextStyle(
                        fontSize: 16,
                        fontWeight:
                        FontWeight
                            .bold,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    detailRow(
                      'Time',
                      formatDateTime(
                        timestampOf(
                          data,
                          event,
                        ),
                      ),
                    ),
                    detailRow(
                      'QR Location',
                      eventValue(
                        data,
                        event,
                        'QrCode',
                      ),
                    ),
                    detailRow(
                      'Latitude',
                      eventValue(
                        data,
                        event,
                        'Latitude',
                      ),
                    ),
                    detailRow(
                      'Longitude',
                      eventValue(
                        data,
                        event,
                        'Longitude',
                      ),
                    ),
                    detailRow(
                      'Device',
                      deviceName(
                        deviceOf(
                          data,
                          event,
                        ),
                      ),
                    ),
                    detailRow(
                      'Operating System',
                      operatingSystem(
                        deviceOf(
                          data,
                          event,
                        ),
                      ),
                    ),
                    if (deviceOf(
                      data,
                      event,
                    ) !=
                        null)
                      ...deviceOf(
                        data,
                        event,
                      )!.entries.map(
                            (entry) =>
                            detailRow(
                              'Device ${entry.key}',
                              entry.value
                                  ?.toString() ??
                                  '-',
                            ),
                      ),
                    const Divider(
                      height: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
              const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // RESULT CARD
  // ============================================================

  Widget buildResultCard(
      QueryDocumentSnapshot<
          Map<String, dynamic>>
      document,
      ) {
    final data = document.data();

    final device =
        deviceOf(data, 'checkIn1') ??
            deviceOf(data, 'checkOut1') ??
            deviceOf(data, 'checkIn2') ??
            deviceOf(data, 'checkOut2');

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
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  child:
                  Icon(Icons.person),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        employeeName(
                          data,
                        ),
                        style:
                        const TextStyle(
                          fontSize: 17,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                      Text(
                        designation(
                          data,
                        ),
                      ),
                      Text(
                        emailOf(data),
                        style:
                        TextStyle(
                          color: Colors
                              .grey
                              .shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip:
                  'View full details',
                  icon: const Icon(
                    Icons
                        .visibility_outlined,
                  ),
                  onPressed: () {
                    showAttendanceDetails(
                      data,
                    );
                  },
                ),
              ],
            ),
            const Divider(
              height: 22,
            ),
            statusChip(
              statusOf(data),
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              'Employee ID: '
                  '${userIdOf(data)}',
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              'Date: '
                  '${data['date']?.toString() ?? '-'}',
            ),
            const SizedBox(
              height: 10,
            ),
            for (final event
            in events) ...[
              Text(
                '${event == 'checkIn1' ? 'Check In 1' : event == 'checkOut1' ? 'Check Out 1' : event == 'checkIn2' ? 'Check In 2' : 'Check Out 2'}: '
                    '${formatDateTime(timestampOf(data, event))}',
              ),
              if (timestampOf(
                data,
                event,
              ) !=
                  null)
                Text(
                  '  QR: ${eventValue(data, event, 'QrCode')}',
                  style:
                  const TextStyle(
                    fontSize: 12,
                  ),
                ),
            ],
            const Divider(
              height: 22,
            ),
            Text(
              'QR Location: '
                  '${firstEventValue(data, 'QrCode')}',
            ),
            Text(
              'Latitude: '
                  '${firstEventValue(data, 'Latitude')}',
            ),
            Text(
              'Longitude: '
                  '${firstEventValue(data, 'Longitude')}',
            ),
            Text(
              'Device: '
                  '${deviceName(device)}',
            ),
            Text(
              'Operating System: '
                  '${operatingSystem(device)}',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY RESULT
  // ============================================================

  Widget buildEmptyResult() {
    if (searchText.isEmpty) {
      return const Padding(
        padding:
        EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Color(0xFFFFEE58),
            ),
            SizedBox(
              height: 16,
            ),
            Text(
              'Enter a search value and press Enter.',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFFEE58),
              )
            ),
            SizedBox(
              height: 8,
            ),
            Text(
              'You can search by employee name, designation, email, employee ID, QR location, GPS, device or OS.',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFFEE58),
              )
            ),
          ],
        ),
      );
    }

    return Padding(
      padding:
      const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(
            Icons
                .search_off,
            size: 64,
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            'No attendance records found for "$searchText".',
            textAlign:
            TextAlign.center,
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
          'Search Attendance',
        ),
      ),
      body: Column(
        children: [
          // ======================================================
          // SEARCH BOX
          // ======================================================

          Padding(
            padding:
            const EdgeInsets.all(16),
            child: TextField(
              controller:
              searchController,

              autofocus: true,

              textInputAction:
              TextInputAction.search,

              // IMPORTANT:
              // No listener.
              // No Firestore request while typing.
              //
              // Firestore search happens ONLY here.
              onSubmitted: (_) {
                performSearch();
              },

              decoration:
              InputDecoration(
                labelText:
                'Search attendance',

                hintText:
                'Name, ID, email, QR, device or OS',

                prefixIcon:
                const Icon(
                  Icons.search,
                ),

                suffixIcon:
                searchController
                    .text
                    .isNotEmpty
                    ? IconButton(
                  onPressed:
                  clearSearch,
                  icon:
                  const Icon(
                    Icons.clear,
                  ),
                )
                    : null,

                border:
                const OutlineInputBorder(),

                helperText:
                'Press Enter to search',
              ),
            ),
          ),

          // ======================================================
          // SEARCH BUTTON
          // ======================================================

          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                isSearching
                    ? null
                    : performSearch,
                icon: isSearching
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(
                  Icons.search,
                ),
                label: Text(
                  isSearching
                      ? 'Searching...'
                      : 'Search Attendance',
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // ======================================================
          // RESULT COUNT
          // ======================================================

          if (searchText.isNotEmpty &&
              !isSearching)
            Padding(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${searchResults.length} record(s) found',
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight.bold,
                        color: Color(0xFFFFEE58),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                    clearSearch,
                    icon:
                    const Icon(
                      Icons.clear,
                    ),
                    label:
                    const Text(
                      'Clear',
                      style: TextStyle(
                      color: Color(0xFFFFEE58),
                      )
                    ),
                  ),
                ],
              ),
            ),

          // ======================================================
          // RESULTS
          // ======================================================

          Expanded(
            child: isSearching
                ? const Center(
              child:
              CircularProgressIndicator(),
            )
                : searchResults.isEmpty
                ? SingleChildScrollView(
              child:
              buildEmptyResult(),
            )
                : ListView.builder(
              padding:
              const EdgeInsets
                  .fromLTRB(
                16,
                8,
                16,
                24,
              ),
              itemCount:
              searchResults
                  .length,
              itemBuilder:
                  (context, index) {
                return buildResultCard(
                  searchResults[
                  index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}