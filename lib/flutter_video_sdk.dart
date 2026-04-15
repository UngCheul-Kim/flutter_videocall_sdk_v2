library flutter_ipstack_videocall;

export 'src/sdk_initializer.dart';
export 'src/call_manager.dart';
export 'src/push_manager.dart';
export 'src/livekit_manager.dart';

import 'src/call_manager.dart';
import 'src/push_manager.dart';
import 'src/livekit_manager.dart';
import 'src/sdk_initializer.dart';

class VideoSDK {
  static Future<void> initialize({
    required String licenseKey,
    required String userId,
    String? deviceId, // If no device ID is specified, the device ID will be automatically detected.
    String appId = 'videocall',

    /// service_name: The unique name given to an app developed by a developer.
    /// This value is stored in the `service_name` field when a Push Token is saved,
    /// and it is used to identify users who have the same `service_name` when sending a push notification.
    /// For example, "MyChatApp", "BusinessCall", etc.
    String? serviceName,
    bool skipLicenseVerify = false,
  }) async {
    await SDKConfig.init(
      licenseKey: licenseKey,
      userId: userId,
      deviceId: deviceId,
      appId: appId,
      serviceName: serviceName,
      skipLicenseVerify: skipLicenseVerify,
    );
    await PushManager.init();
  }

  static void reset() {
    SDKConfig.reset();
    PushManager.reset();
    CallManager.resetState();
    LiveKitManager.resetTracks();
  }

  static Future<void> startVideoCall(String targetUserId) async {
    await CallManager.startCall(targetUserId, isVideo: true);
  }

  static Future<void> startAudioCall(String targetUserId) async {
    await CallManager.startCall(targetUserId, isVideo: false);
  }

  static Future<void> acceptCall(String callerId) async {
    await CallManager.acceptCall(callerId);
  }

  static Future<void> rejectCall(String callerId) async {
    await CallManager.rejectCall(callerId);
  }

  static Future<void> endCall(String? calleeId) async {
    await CallManager.endCall(calleeId);
  }

  static bool get isInitialized => SDKConfig.isInitialized;
  static String? get licenseError => SDKConfig.licenseError;
  static String get userId => SDKConfig.userId;
  static String get deviceId => SDKConfig.deviceId;
  static String get platform => SDKConfig.platform;
}
