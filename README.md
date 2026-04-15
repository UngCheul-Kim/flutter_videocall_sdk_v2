# IPSTACK VideoCall SDK

Comprehensive documentation for integrating high-performance video calling into your Flutter applications. Build enterprise-grade communication experiences in minutes.

## Introduction

IPSTACK VideoCall SDK is a production-ready Flutter SDK for building real-time video and audio calling applications. It provides ultra-low latency, enterprise-grade security, and seamless cross-platform support.

### Features

- **Easy Integration** - Add to your pubspec.yaml and initialize in minutes
- **Enterprise Security** - End-to-end encryption with AES-256
- **Native VoIP** - CallKit (iOS) and VoIP services support

## Quick Start

Get started with IPSTACK VideoCall SDK in 5 minutes. Follow these steps to integrate video calling into your app.

### 1. Add Dependency

```bash
flutter pub add flutter_ipstack_videocall
```

### 2. Initialize Firebase & Push Handlers

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is required for FCM/VoIP push features
  await Firebase.initializeApp();

  // Register background message handler (must be a top-level function)
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  runApp(InitApp(firebaseInitError: null));
}
```

### 3. Initialize the SDK After Login

```dart
import 'package:flutter_ipstack_videocall/flutter_video_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserStorage {
  static const String _userIdKey = 'member_UniqueId (db_id or email)';
  static const String _licenseKeyKey = 'videocall_licenseKey';
  static const _storage = FlutterSecureStorage();

  static Future<void> saveUserId(String userId) async {
    await _storage.write(key: _userIdKey, value: userId);
  }

  static Future<void> saveLicenseKey(String licenseKey) async {
    await _storage.write(key: _licenseKeyKey, value: licenseKey);
  }
}

// Initialize with your credentials (once you know the current user)
await VideoSDK.initialize(
  licenseKey: "YOUR_LICENSE_KEY",
  userId: "user_123",           // Required: Current user's ID
  serviceName: "YourAppName",   // Required: Your app name
);

await UserStorage.saveUserId("user_123");
await UserStorage.saveLicenseKey("YOUR_LICENSE_KEY");

// Initialize managers
CallManager.init();
PushManager.init();

// Connect WebSocket for real-time signaling
CallManager.connectWebSocket();
```

### 4. Handle Incoming Calls (Foreground UI + Background Overlay)

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void showIncomingCallUI(String callerId, String callType, String callId) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => IncomingCallScreen(
        callerId: callerId,
        callType: callType,
      ),
    ),
  );
}

Future<void> showAndroidIncomingOverlay(String callerId, String callId, String callType) async {
  const channel = MethodChannel('online.ipstack.videocall/incoming_call');
  await channel.invokeMethod('showIncomingCallOverlay', {
    'callerId': callerId,
    'callId': callId,
    'callType': callType,
  });
}

CallManager.onIncomingCall = (call) async {
  final callerId = (call['from'] ?? call['caller_id'] ?? 'Unknown').toString();
  final callType = (call['call_type'] ?? 'video').toString();
  final callId = (call['call_id'] ?? DateTime.now().millisecondsSinceEpoch).toString();

  final isForeground = WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached;

  if (isForeground) {
    showIncomingCallUI(callerId, callType, callId);
    RingtonePlayer.play();
    return;
  }

  // Background (Android): show native overlay + ringtone from service
  await showAndroidIncomingOverlay(callerId, callId, callType);
};
```

### 5. Start a Call

```dart
// Start a video call
await VideoSDK.startVideoCall("recipient_user_id");

// Start an audio-only call
await VideoSDK.startAudioCall("recipient_user_id");
```

## Installation

The SDK is distributed via pub.dev and supports Flutter 3.10+ with Dart 3.0+.

```bash
flutter pub add flutter_ipstack_videocall
```

### Dependencies

The SDK automatically includes these dependencies:

- **livekit_client** - WebRTC media handling
- **firebase_messaging** - Push notifications
- **flutter_callkit_incoming** - iOS CallKit
- **web_socket_channel** - Signaling
- **uuid** - Unique identifiers

## iOS Configuration Required

Add the following to your iOS Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for audio calls</string>
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
  <string>remote-notification</string>
</array>
```

## Android Configuration Required

Add permissions to AndroidManifest.xml:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
```

## Configuration

Configure the SDK with your license key and API endpoint. You can obtain these from the developer dashboard.

### Environment Variables

```dart
// Recommended: Use environment variables
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://videocall.ipstack.online');
const String licenseKey = String.fromEnvironment('LICENSE_KEY');
```

### Configuration Options

| Option | Type    | Description                              |
|--------|---------|------------------------------------------|
| licenseKey | String | Your unique license key from dashboard |
| apiUrl    | String | Backend API base URL                     |

## SDK Initialization

The VideoSDK class provides the main entry point for SDK initialization and configuration. The SDK requires Firebase for push notifications.

### Full Initialization Example

Complete initialization with Firebase, SDK, and managers:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_ipstack_videocall/flutter_video_sdk.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase (Required)
  await Firebase.initializeApp();

  // 2. Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  runApp(const InitApp());
}

// Background message handler for push notifications
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.data}');

  final data = message.data;
  final callType = data['type'] ?? data['call_type'] ?? 'video';
  final callerId = data['caller_id'] ?? data['from'] ?? 'Unknown';
  final callId = data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

  if (callType == 'incoming_call' || data['action'] == 'incoming_call') {
    // Show CallKit incoming call UI
    await _showCallKitIncoming(callerId, callId, callType);
  }
}
```

### VideoSDK.initialize()

Initialize the SDK with your credentials. Must be called before any other SDK operations.

```dart
// Check if SDK is already initialized
if (!VideoSDK.isInitialized) {
  await VideoSDK.initialize(
    licenseKey: "YOUR_LICENSE_KEY",    // Required: Your license key
    userId: "user_123",                // Required: Current user's ID (from your database)
    serviceName: "YourAppName",       // Required: Your app name for CallKit
  );
}

// Initialize managers
CallManager.init();
PushManager.init();

// Connect WebSocket for real-time signaling
CallManager.connectWebSocket();
```

### VideoSDK Methods & Properties

| Method/Property   | Parameters                    | Returns     |
|-------------------|-------------------------------|-------------|
| initialize()      | licenseKey, userId, serviceName | Future<void> |
| startVideoCall()   | recipientId                   | Future<void> |
| startAudioCall()  | recipientId                   | Future<void> |
| isInitialized     | static property               | bool        |
| reset()           | -                            | void        |

## License Management

The LicenseManager handles license validation, activation, and status checks.

### Usage

```dart
// Check license status
final status = await LicenseManager.getStatus();
if (status.isValid) {
  print('License is valid');
}

// Validate specific license key
final isValid = await LicenseManager.validateLicense("LICENSE_KEY");
print('License valid: $isValid');
```

### LicenseManager API

| Method           | Description                    |
|-----------------|------------------------------|
| getStatus()     | Get current license status    |
| validateLicense(key) | Validate a specific license key |
| activate(licenseKey) | Activate a new license   |
| deactivate()    | Deactivate current license   |

## User Storage & Auto-Login

For background push notifications to work properly, you need to securely store user credentials so they can be used when receiving calls in the background.

### Secure Storage

Use flutter_secure_storage to save user credentials:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserStorage {
  static const String _userIdKey = 'ipstack_loginID';
  static const String _licenseKeyKey = 'videocall_licenseKey';
  static const _storage = FlutterSecureStorage();

  static Future<void> saveUserId(String userId) async {
    await _storage.write(key: _userIdKey, value: userId);
  }

  static Future<String?> getUserId() async {
    return await _storage.read(key: _userIdKey);
  }

  static Future<void> saveLicenseKey(String licenseKey) async {
    await _storage.write(key: _licenseKeyKey, value: licenseKey);
  }

  static Future<String?> getLicenseKey() async {
    return await _storage.read(key: _licenseKeyKey);
  }
}
```

### Auto-Login Implementation

```dart
// On app start, check for saved credentials
Future<void> _checkSavedUser() async {
  final userId = await UserStorage.getUserId();
  final licenseKey = await UserStorage.getLicenseKey();

  if (userId != null && licenseKey != null) {
    // Auto-login with saved credentials
    await _autoLogin(userId, licenseKey);
  }
}

Future<void> _autoLogin(String userId, String licenseKey) async {
  // Request camera/microphone permissions
  final cameraStatus = await Permission.camera.request();
  final micStatus = await Permission.microphone.request();

  // Skip if permissions denied
  if (cameraStatus.isDenied || micStatus.isDenied) {
    return;
  }

  // Initialize SDK if not already initialized
  if (!VideoSDK.isInitialized) {
    await VideoSDK.initialize(
      licenseKey: licenseKey,
      userId: userId,
      serviceName: "YourAppName",
    );
  }

  CallManager.init();
  PushManager.init();
  CallManager.connectWebSocket();

  // Set up push handlers
  PushManager.onIncomingCall = (call) {
    // Handle incoming call
  };

  // Navigate to home
  if (mounted) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => HomePage(currentUserId: userId),
      ),
    );
  }
}
```

> **Why Store Credentials?**
> When receiving a call in the background (app closed), you need to re-initialize the SDK to accept/reject the call. The stored credentials allow this without requiring the user to log in again.

## License Error Handling

Handle license errors gracefully with the onLicenseError callback.

### Setting Up Error Handler

```dart
// Set up license error callback
CallManager.onLicenseError = (error) {
  String message;
  switch (error) {
    case 'invalid':
      message = 'Invalid license key';
      break;
    case 'expired':
      message = 'License has expired';
      break;
    default:
      message = 'License error: $error';
  }

  // Show error dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('License Error'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            VideoSDK.reset();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const LoginPage()),
            );
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
};
```

> **Important**
> Always handle license errors gracefully. When an error occurs, reset the SDK with VideoSDK.reset() and redirect the user to the login screen.

## Call Management

CallManager handles all call operations including making, receiving, and managing active calls.

### Initializing CallManager

```dart
// Initialize CallManager
CallManager.init();

// Connect WebSocket for real-time signaling
CallManager.connectWebSocket();

// Set up event handlers
CallManager.onIncomingCall = (call) {
  print("Incoming call from: ${call['from']}");
  // Show incoming call screen
};

CallManager.onCallConnected = () {
  print("Call connected");
  // Update UI to show connected state
};

CallManager.onCallEnded = () {
  print("Call ended");
  Navigator.of(context).pop();
};

CallManager.onCallCancelled = () {
  print("Call cancelled by remote");
  RingtonePlayer.stop();
};

CallManager.onCallTimeout = () {
  print("Call timeout - no answer");
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('연결 실패'),
      content: const Text('상대방이 전화를 받지 않습니다.'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
          child: const Text('확인'),
        ),
      ],
    ),
  );
};

// Handle license errors
CallManager.onLicenseError = (error) {
  print("License error: $error");
};
```

### Making Calls

```dart
// Make video call
await VideoSDK.startVideoCall('recipient_user_id');

// Or use CallManager directly
await CallManager.startCall(
  recipientId: 'user_123',
  callType: 'video',  // or 'audio'
);

// Accept incoming call
CallManager.acceptCall(callerId);

// Reject incoming call
CallManager.rejectCall(callerId);

// End active call
CallManager.endCall(callerId);
```

### CallManager API

| Property/Method   | Description                              |
|-----------------|------------------------------------------|
| onIncomingCall  | Callback for incoming calls (Map)          |
| onCallConnected | Callback when call is connected          |
| onCallEnded    | Callback when call ends                 |
| onCallCancelled| Callback when call is cancelled         |
| onCallTimeout  | Callback when call times out              |
| onLicenseError | Callback for license errors              |
| init()          | Initialize CallManager                    |
| connectWebSocket() | Connect to WebSocket for signaling      |
| startCall()     | Start a new call                         |
| acceptCall()    | Accept incoming call                     |
| rejectCall()   | Reject incoming call                     |
| endCall()      | End active call                          |
| toggleVideo()  | Toggle video on/off                       |
| toggleMute()   | Toggle microphone mute                    |
| switchCamera()  | Switch front/back camera                |

## Video Calls

Video calls provide real-time video communication with camera switching, quality settings, and full call control.

### Starting a Video Call

```dart
// Start video call
await VideoSDK.startVideoCall('recipient_user_id');

// Or use CallManager directly
await CallManager.startCall(
  recipientId: 'user_123',
  callType: 'video',
);
```

### Video Controls

```dart
// Toggle video on/off
await CallManager.switchCamera();

// Switch camera (front/back)
await CallManager.switchCamera();

// Get video state
bool isVideoEnabled = CallManager.isVideoEnabled;
```

## Audio Calls

Audio-only calls work identically to video calls but without camera transmission, perfect for voice-only communication.

```dart
// Start audio call
await VideoSDK.startAudioCall('recipient_user_id');

// Or specify audio type
await CallManager.startCall(
  recipientId: 'user_123',
  callType: 'audio',
);
```

## Push Notifications

The SDK integrates with Firebase Cloud Messaging (FCM) for reliable push notification delivery. This enables receiving incoming calls even when the app is in the background or closed.

### Background Push Setup

Register a background message handler to receive calls when the app is closed:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

// Background message handler (must have @pragma annotation)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.data}');

  final data = message.data;
  final callType = (data['type'] ?? data['call_type'] ?? 'video').toString();
  final callerId = (data['caller_id'] ?? data['from'] ?? 'Unknown').toString();
  final callId = (data['call_id'] ?? DateTime.now().millisecondsSinceEpoch).toString();

  // Check if this is an incoming call
  if (callType == 'incoming_call' || data['action'] == 'incoming_call') {
    await showCallKitIncoming(callerId, callId, callType);
  }
}

// Show CallKit incoming call UI
Future<void> showCallKitIncoming(String callerId, String callId, String callType) async {
  final isVideoCall = callType == 'video';
  final callTypeText = isVideoCall ? 'VideoCall' : 'AudioCall';

  final params = CallKitParams(
    id: callId,
    nameCaller: '$callTypeText\nCaller: $callerId',
    appName: 'VideoCall',
    avatar: '',
    handle: callerId,
    type: isVideoCall ? 1 : 0,  // 1 = video, 0 = audio
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: <String, dynamic>{
      'call_type': callType,
      'from': callerId,
      'call_id': callId,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: true,
      ringtonePath: 'ringtone',
      backgroundColor: '#0955fa',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
    ),
    ios: const IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: true,
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
```

### PushManager Setup

```dart
// Initialize PushManager
PushManager.init();

// Foreground: show Flutter incoming screen + ringtone
PushManager.onIncomingCall = (call) async {
  final callerId = (call['from'] ?? call['caller_id'] ?? 'Unknown').toString();
  final callType = (call['call_type'] ?? 'video').toString();
  final callId = (call['call_id'] ?? DateTime.now().millisecondsSinceEpoch).toString();

  showIncomingCallUI(callerId, callType, callId);
  RingtonePlayer.play();
};

// When the call ends/cancels: stop ringtone and close UI/overlay
PushManager.onCallEnded = (call) {
  RingtonePlayer.stop();
  _returnToHomeAfterCallTerminated();
};
```

### PushManager API

| Method/Property   | Description                    |
|-----------------|------------------------------|
| init()          | Initialize push notification service |
| onIncomingCall  | Callback for incoming calls (Map) |
| onCallEnded     | Callback when call ends       |
| onAccepted     | Callback when call is accepted  |

## CallKit Integration

On iOS, the SDK integrates with CallKit and PushKit for native VoIP calling experience with lock screen call UI. On Android, it uses custom notification with foreground service.

### Showing Incoming Call

```dart
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

// Show CallKit incoming call
Future<void> showCallKitIncoming(
    String callerId, String callId, String callType) async {
  final isVideoCall = callType == 'video';

  final params = CallKitParams(
    id: callId,
    nameCaller: isVideoCall ? 'VideoCall' : 'AudioCall',
    appName: 'YourAppName',
    avatar: '',
    handle: callerId,
    type: isVideoCall ? 1 : 0,  // 1 = video, 0 = audio
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: <String, dynamic>{
      'call_type': callType,
      'from': callerId,
      'call_id': callId,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: true,
      ringtonePath: 'ringtone',
      backgroundColor: '#0955fa',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
    ),
    ios: const IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: true,
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
```

### Handling CallKit Events

```dart
// Listen to CallKit events
FlutterCallkitIncoming.onEvent.listen((event) async {
  print('CallKit event: ${event?.event}');

  if (event?.event == Event.actionCallAccept) {
    final extra = event?.body?['extra'] as Map<String, dynamic>?;
    final callerId = (extra?['from'] ?? extra?['caller_id'] ?? 'Unknown').toString();

    final savedUserId = await UserStorage.getUserId();
    final savedLicenseKey = await UserStorage.getLicenseKey();

    if (savedUserId != null && savedLicenseKey != null) {
      if (!VideoSDK.isInitialized) {
        await VideoSDK.initialize(
          licenseKey: savedLicenseKey,
          userId: savedUserId,
          serviceName: "IPSTACK_VideoCall_V2",
        );
      }
      CallManager.init();
      CallManager.acceptCall(callerId);
    }
  } else if (event?.event == Event.actionCallDecline) {
    final extra = event?.body?['extra'] as Map<String, dynamic>?;
    final callerId = (extra?['from'] ?? extra?['caller_id'] ?? 'Unknown').toString();
    CallManager.rejectCall(callerId);
  }
});
```

### Required iOS Setup

Add to Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for audio calls</string>
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
  <string>remote-notification</string>
</array>
```

### Required Android Setup

Add to AndroidManifest.xml:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.VIBRATE" />
```

### CallKit API

| Method           | Description                 |
|-----------------|----------------------------|
| showCallkitIncoming() | Show incoming call UI |
| startCall()     | Start outgoing call         |
| endCall()       | End active call            |
| onEvent        | Listen to CallKit events   |

## Security

The SDK implements multiple layers of security to protect your video communications.

### End-to-End Encryption

All video and audio streams are encrypted using industry-standard protocols:

- **SRTP** (Secure Real-time Transport Protocol)
- **TLS 1.3** for signaling
- **DTLS-SRTP** for key exchange

### License-Based Access Control

Each SDK instance must be activated with a valid license key. License validation happens:

- On SDK initialization
- On app foreground (configurable)
- Before starting each call

### Best Practices

- Never expose your license key in client-side code (use server-side validation)
- Implement certificate pinning for production apps
- Regularly update the SDK to get security patches
- Use HTTPS for all API communications

## Troubleshooting

Common issues and their solutions when integrating the SDK.

### iOS: "Pods_Runner.framework not found"

Solution: Run CocoaPods and build from Runner.xcworkspace (not Runner.xcodeproj).

```bash
cd ios
pod install --no-repo-update
```

### iOS: Blank screen on startup

Solution: Ensure Firebase is configured and GoogleService-Info.plist is included in the Runner target. If Firebase initialization fails, the app will not show main UI.

### Error: "License key invalid"

Solution: Verify your license key in the developer dashboard. Check that it matches your app's bundle ID/package name.

### Error: "Camera/Microphone permission denied"

Solution: Ensure you've added the required permissions to Info.plist (iOS) and AndroidManifest.xml (Android).

### Error: "WebSocket connection failed"

Solution: Check your network connection and ensure the API URL is correct. Verify firewall rules allow WebSocket connections.

### No incoming call notifications

Solution: Ensure PushManager is initialized and you've requested notification permissions. Check Firebase configuration.

## Changelog

### v2.0.0 (Latest Release)

- Complete rewrite with new architecture
- Video/Audio calling with WebRTC
- Push notifications via FCM
- CallKit support for iOS
- Custom VoIP notification for Android
- Background push handling
- User credential storage for auto-login
- License error handling
