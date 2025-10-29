import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfo {
  static Future<int> getAndroidSdkVersion() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt;
  }

  static bool isAndroidVersionAtLeast12(int sdkInt) {
    return sdkInt >= 31;
  }

  static bool isAndroidVersion13(int sdkInt) {
    return sdkInt == 33;
  }
}