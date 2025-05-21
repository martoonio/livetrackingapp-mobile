import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

// Tambahkan metode helper untuk mendapatkan informasi perangkat
Future<Map<String, dynamic>> getDeviceInfo() async {
  try {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final Map<String, dynamic> deviceData = <String, dynamic>{};
    
    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;
      deviceData['type'] = 'android';
      deviceData['model'] = info.model;
      deviceData['manufacturer'] = info.manufacturer;
      deviceData['androidVersion'] = info.version.release;
      deviceData['sdkInt'] = info.version.sdkInt;
      deviceData['brand'] = info.brand;
      deviceData['device'] = info.device;
      deviceData['product'] = info.product;
    } else if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;
      deviceData['type'] = 'ios';
      deviceData['name'] = info.name;
      deviceData['model'] = info.model;
      deviceData['systemName'] = info.systemName;
      deviceData['systemVersion'] = info.systemVersion;
      deviceData['localizedModel'] = info.localizedModel;
      deviceData['identifierForVendor'] = info.identifierForVendor;
    }
    
    return deviceData;
  } catch (e) {
    print('Error getting device info: $e');
    return {'error': 'Failed to get device info'};
  }
}