import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_ipstack_videocall/src/sdk_initializer.dart';

class PushManager {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _currentCallId;
  static String? _currentCallerId;
  static String? _currentCallType;

  static Function(dynamic)? onIncomingCall;
  static Function(dynamic)? onCallAccepted;
  static Function(dynamic)? onCallRejected;
  static Function(dynamic)? onCallEnded;

  static bool _isInitialized = false;

  static String? get currentCallId => _currentCallId;
  static String? get currentCallerId => _currentCallerId;
  static String? get currentCallType => _currentCallType;

  static Future<void> init() async {
    if (_isInitialized) return;

    if (Platform.isIOS) {
      await _messaging.requestPermission();
      await FlutterCallkitIncoming.requestFullIntentPermission();
    }

    String? token = await _messaging.getToken();
    print('FCM Token: $token');

    if (token != null && token.isNotEmpty) {
      await _registerPushToken(token);
    } else {
      print('=== No FCM token available ===');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('=== onMessage received: ${message.data} ===');
      _handleCall(message.data, isForeground: true);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('=== onMessageOpenedApp received: ${message.data} ===');
      _handleCall(message.data, isForeground: false);
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print('=== getInitialMessage received: ${message.data} ===');
        _handleCall(message.data, isForeground: false);
      }
    });

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FlutterCallkitIncoming.onEvent.listen((event) {
      print('=== CallKit event: $event ===');
      print('=== CallKit event type: ${event?.event} ===');
      print('=== CallKit event body: ${event?.body} ===');

      final eventType = event?.event;
      if (eventType == Event.actionCallAccept) {
        if (onCallAccepted != null) {
          onCallAccepted!(
              {'call_id': _currentCallId, 'from': _currentCallerId});
        }
      } else if (eventType == Event.actionCallDecline) {
        if (onCallRejected != null) {
          onCallRejected!(
              {'call_id': _currentCallId, 'from': _currentCallerId});
        }
      }
    });

    _isInitialized = true;
  }

  static Future<void> _registerPushToken(String token) async {
    try {
      final apiUrl = SDKConfig.apiUrl;
      final licenseKey = SDKConfig.licenseKey;
      final userId = SDKConfig.userId;
      final deviceId = SDKConfig.deviceId;
      final serviceName = SDKConfig.serviceName;

      if (apiUrl.isEmpty || licenseKey.isEmpty || userId.isEmpty) {
        print('=== Cannot register push token: SDK not initialized ===');
        return;
      }

      final url = apiUrl.startsWith('https://')
          ? '${apiUrl}/api/push/register'
          : 'http://${apiUrl.substring(7)}/api/push/register';

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              // service_user_id: 개발자 앱의 실제 사용자 ID (서비스를 사용하는 사람)
              'service_user_id': userId,
              'service_name': serviceName,
              'device_id': deviceId,
              'push_token': token,
              'platform': SDKConfig.platform.isNotEmpty ? SDKConfig.platform : (Platform.isIOS ? 'ios' : 'android'),
              'license_key': licenseKey,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('=== Push token registered successfully ===');
      } else {
        print('=== Push token registration failed: ${response.statusCode} ===');
      }
    } catch (e) {
      print('=== Error registering push token: $e ===');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
    print('=== Background handler called: ${message.data} ===');
    _handleCall(message.data, isForeground: false);
  }

  static void _handleCall(Map<String, dynamic> data,
      {required bool isForeground}) {
    print('=== PushManager handling call data: $data ===');

    final callType = data['type'] ?? data['call_type'] ?? 'video';
    final callerId =
        data['from'] ?? data['caller_id'] ?? data['callerId'] ?? '';
    final callId = data['call_id'] ?? data['callId'] ?? '';

    if (callType == 'incoming_call' || data['action'] == 'incoming_call') {
      _currentCallId = callId.toString();
      _currentCallerId = callerId.toString();
      _currentCallType = data['call_type'] ?? 'video';

      if (!isForeground) {
        _showCallKitIncoming(
          callerId.toString(),
          callId.toString(),
          data['call_type'] ?? 'video',
        );
      }

      if (onIncomingCall != null) {
        onIncomingCall!(data);
      }
    } else if (callType == 'call_accepted' ||
        data['action'] == 'call_accepted') {
      if (onCallAccepted != null) {
        onCallAccepted!(data);
      }
    } else if (callType == 'call_rejected' ||
        data['action'] == 'call_rejected') {
      if (onCallRejected != null) {
        onCallRejected!(data);
      }
    } else if (callType == 'call_ended' ||
        data['action'] == 'call_ended' ||
        data['action'] == 'call_cancelled') {
      _endCallKit();
      if (onCallEnded != null) {
        onCallEnded!(data);
      }
    }
  }

  static Future<void> _showCallKitIncoming(
      String callerId, String callId, String callType) async {
    try {
      final isVideoCall = callType == 'video';

      final params = CallKitParams(
        id: callId,
        nameCaller: callerId,
        appName: 'IPSTACK VideoCall',
        avatar: '',
        handle: callerId,
        type: isVideoCall ? 1 : 0,
        duration: 30000,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        extra: <String, dynamic>{
          'call_type': callType,
          'from': callerId,
          'call_id': callId,
        },
        headers: <String, dynamic>{},
        android: const AndroidParams(
          isCustomNotification: false,
          isShowLogo: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      print('=== Error showing CallKit: $e ===');
    }
  }

  static Future<void> _endCallKit() async {
    try {
      await FlutterCallkitIncoming.endCall(_currentCallId ?? '');
    } catch (e) {
      print('=== Error ending CallKit: $e ===');
    }
  }

  static Future<void> acceptCall() async {
    await _endCallKit();
    if (onCallAccepted != null) {
      onCallAccepted!({
        'call_id': _currentCallId,
        'from': _currentCallerId,
        'call_type': _currentCallType,
      });
    }
  }

  static Future<void> declineCall() async {
    await _endCallKit();
    if (onCallRejected != null) {
      onCallRejected!({'call_id': _currentCallId, 'from': _currentCallerId});
    }
  }

  static Future<void> endCurrentCall() async {
    await _endCallKit();
    if (onCallEnded != null) {
      onCallEnded!({'call_id': _currentCallId});
    }
    _currentCallId = null;
    _currentCallerId = null;
    _currentCallType = null;
  }

  static Future<void> endAllCalls() async {
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls != null) {
        for (final call in activeCalls) {
          await FlutterCallkitIncoming.endCall(call['id'] ?? '');
        }
      }
    } catch (e) {
      print('=== Error ending all calls: $e ===');
    }
    _currentCallId = null;
    _currentCallerId = null;
    _currentCallType = null;
  }

  static Future<List<dynamic>> getActiveCalls() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<String?> getDevicePushTokenVoIP() async {
    try {
      return await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    } catch (e) {
      print('=== Error getting VoIP token: $e ===');
      return null;
    }
  }

  static Future<void> sendVoIPToken(String voipToken) async {
    try {
      final apiUrl = SDKConfig.apiUrl;
      final licenseKey = SDKConfig.licenseKey;
      final userId = SDKConfig.userId;
      final deviceId = SDKConfig.deviceId;
      final serviceName = SDKConfig.serviceName;

      if (apiUrl.isEmpty || licenseKey.isEmpty || userId.isEmpty) {
        print('=== Cannot register VoIP token: SDK not initialized ===');
        return;
      }

      final url = apiUrl.startsWith('https://')
          ? '${apiUrl}/api/push/register'
          : 'http://${apiUrl.substring(7)}/api/push/register';

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'service_user_id': userId,
              'service_name': serviceName,
              'device_id': deviceId,
              'push_token': voipToken,
              'platform': 'ios_voip',
              'license_key': licenseKey,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('=== VoIP token registered successfully ===');
      } else {
        print('=== VoIP token registration failed: ${response.statusCode} ===');
      }
    } catch (e) {
      print('=== Error registering VoIP token: $e ===');
    }
  }

  static void reset() {
    _currentCallId = null;
    _currentCallerId = null;
    _currentCallType = null;
  }
}
