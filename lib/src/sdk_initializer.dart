import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

class SDKConfig {
  static String? _licenseKey;

  static final String _apiUrl = 'https://videocall.ipstack.online';
  static String? _userId;
  static String? _deviceId;
  static String? _appId;

  /// service_name: The unique name given to an app developed by a developer.
  /// This value is stored in the `service_name` field when a Push Token is saved,
  /// and it is used to identify users who have the same `service_name` when sending a push notification.
  /// For example, "MyChatApp", "BusinessCall", etc.
  static String? _serviceName;
  static bool _isInitialized = false;
  static String? _licenseError;

  /// Current device platform information (android / ios / macos / windows / linux)
  static String? _platform;

  static String get licenseKey => _licenseKey ?? '';
  static String get apiUrl => _apiUrl;
  static String get userId => _userId ?? '';
  static String get deviceId => _deviceId ?? '';
  static String get appId => _appId ?? '';
  static String get serviceName => _serviceName ?? '';
  static String get platform => _platform ?? '';
  static bool get isInitialized => _isInitialized;
  static String? get licenseError => _licenseError;


  static Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'ios_unknown';
    } else if (Platform.isMacOS) {
      final macInfo = await deviceInfo.macOsInfo;
      return macInfo.systemGUID ?? 'macos_unknown';
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return windowsInfo.deviceId;
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      return linuxInfo.id;
    }

    return 'unknown_device';
  }


  static String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static Future<void> init({
    required String licenseKey,
    required String userId,
    String? deviceId,
    String appId = 'videocall',

    /// service_name: The unique name given to an app developed by a developer.
    /// This value is stored in the `service_name` field when a Push Token is saved,
    /// and it is used to identify users who have the same `service_name` when sending a push notification.
    /// For example, "MyChatApp", "BusinessCall", etc.
    String? serviceName,
    bool skipLicenseVerify = false,
  }) async {
    _serviceName = serviceName;
    _platform = _detectPlatform();


    if (deviceId == null || deviceId.isEmpty) {
      try {
        _deviceId = await _getDeviceId();
      } catch (e) {
        print('=== Error getting device ID: $e, using fallback ===');
        _deviceId = '${_platform}_${userId}_${DateTime.now().millisecondsSinceEpoch}';
      }
    } else {
      _deviceId = deviceId;
    }

    if (skipLicenseVerify) {
      _licenseKey = licenseKey;
      _userId = userId;
      _appId = appId;
      _licenseError = null;
      _isInitialized = true;
      return;
    }

    final url = _apiUrl.startsWith('https://')
        ? '${_apiUrl}/api/license/verify'
        : 'http://${_apiUrl.substring(7)}/api/license/verify';

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'license_key': licenseKey,
              'device_id': _deviceId,
              'app_id': appId,
              'platform': _platform,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] != 'valid') {
          _licenseError = _getLicenseErrorMessage(data['status']);
          throw Exception(_licenseError);
        }
      } else {
        _licenseError = 'Failed to verify license';
        throw Exception(_licenseError);
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        _licenseError = 'Cannot connect to server';
      }
      rethrow;
    }

    _licenseKey = licenseKey;
    _userId = userId;
    _appId = appId;
    _licenseError = null;
    _isInitialized = true;
  }

  static String _getLicenseErrorMessage(String status) {
    switch (status) {
      case 'invalid':
        return 'Invalid license key';
      case 'expired':
        return 'License has expired';
      case 'suspended':
        return 'License is suspended';
      case 'limit_exceeded':
        return 'Call duration limit exceeded for your plan';
      default:
        return 'Unknown license error';
    }
  }

  static void reset() {
    _licenseKey = null;
    _userId = null;
    _deviceId = null;
    _platform = null;
    _licenseError = null;
    _isInitialized = false;
  }
}
