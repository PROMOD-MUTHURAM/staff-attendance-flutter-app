import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  final DeviceInfoPlugin deviceInfo =
  DeviceInfoPlugin();

  Future<Map<String, dynamic>> getDeviceDetails() async {
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;

      return {
        'platform': 'Android',
        'manufacturer': info.manufacturer,
        'brand': info.brand,
        'model': info.model,
        'device': info.device,
        'androidVersion': info.version.release,
        'androidSdk': info.version.sdkInt,
      };
    }

    if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;

      return {
        'platform': 'iOS',
        'manufacturer': 'Apple',
        'model': info.model,
        'device': info.name,
        'iosVersion': info.systemVersion,
      };
    }

    return {
      'platform': Platform.operatingSystem,
    };
  }
}