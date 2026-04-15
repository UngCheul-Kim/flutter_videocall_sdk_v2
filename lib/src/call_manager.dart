import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_ipstack_videocall/src/sdk_initializer.dart';
import 'package:flutter_ipstack_videocall/src/livekit_manager.dart';

enum CallState { idle, calling, ringing, connected, ended }

class CallManager {
  static WebSocketChannel? _channel;
  static String? _currentUserId;
  static CallState _state = CallState.idle;
  static String? _roomName;
  static String? _token;
  static String? _livekitUrl;
  static String? _currentCallerId;
  static String? _currentCalleeId;
  static int? _currentCallId;
  static bool _isCaller = false;
  static Timer? _callTimeoutTimer;

  static Function(dynamic)? onIncomingCall;
  static Function()? onCallConnected;
  static Function()? onCallEnded;
  static Function()? onCallCancelled;
  static Function(String)? onLicenseError;

  /// Call connection timeout (occurs when the other party does not answer)
  static Function()? onCallTimeout;

  static const int _callTimeoutSeconds = 30; // If a connection cannot be established within 30 seconds, the connection will be terminated.

  static CallState get state => _state;
  static String? get currentCallerId => _currentCallerId;
  static bool get isCaller => _isCaller;
  static String? get currentCallId => _currentCallId?.toString();

  static void init() {
    _currentUserId = SDKConfig.userId;
  }

  static Future<void> toggleVideo() async {
    await LiveKitManager.toggleCamera();
  }

  static Future<void> toggleMute() async {
    await LiveKitManager.toggleMute();
  }

  static Future<void> switchCamera() async {
    await LiveKitManager.switchCamera();
  }

  static bool get isVideoEnabled =>
      LiveKitManager.room?.localParticipant?.isCameraEnabled() ?? false;

  static Future<void> connectWebSocket() async {
    if (_channel != null) {
      print('=== WebSocket already exists ===');
      return;
    }

    String url = SDKConfig.apiUrl;
    if (url.startsWith('https://')) {
      url = 'wss://' + url.substring(8);
    } else if (url.startsWith('http://')) {
      url = 'ws://' + url.substring(7);
    }
    url =
        '$url/ws/$_currentUserId?license_key=${SDKConfig.licenseKey}&device_id=${SDKConfig.deviceId}&app_id=${SDKConfig.appId}&platform=${SDKConfig.platform}';
    print('=== Connecting WebSocket to: $url ===');
    _channel = WebSocketChannel.connect(Uri.parse(url));

    await Future.delayed(const Duration(milliseconds: 500));
    print('=== WebSocket connected ===');

    _channel!.stream.listen(
      (message) {
        print('=== WebSocket received: $message ===');
        final data = jsonDecode(message);
        print('=== Parsed action: ${data['action']} ===');
        _handleMessage(data);
      },
      onError: (error) {
        print('=== WebSocket error: $error ===');
        _channel = null;
      },
      onDone: () {
        print('=== WebSocket done ===');
        _channel = null;
      },
    );
  }

  static void _handleMessage(Map<String, dynamic> data) {
    final action = data['action'];

    switch (action) {
      case 'license_error':
        final error = data['error'] ?? 'invalid';
        print('=== License error: $error ===');
        if (onLicenseError != null) {
          onLicenseError!(error);
        }
        break;
      case 'incoming_call':
        _state = CallState.ringing;
        _currentCallerId = data['from'];
        _currentCallId = data['call_id'];
        print(
          '=== Incoming call from: $_currentCallerId, call_id: $_currentCallId ===',
        );
        if (onIncomingCall != null) {
          onIncomingCall!(data);
        }
        break;
      case 'call_accepted':
        _roomName = data['room'];
        _token = data['token'];
        _livekitUrl = data['url'];
        _currentCallId = data['call_id'];
        print(
          '=== LiveKit URL Received: $_livekitUrl, call_id: $_currentCallId ===',
        );
        _state = CallState.connected;
        _clearCallTimeoutOnConnect(); // Timeout cancelled upon successful connection.
        _connectToLiveKit();
        if (onCallConnected != null) {
          onCallConnected!();
        }
        break;
      case 'call_rejected':
      case 'call_ended':
      case 'call_cancelled':
        final from = data['from'];
        print('=== Call ended by: $from ===');
        print(
          '=== _isCaller: $_isCaller, _currentCalleeId: $_currentCalleeId, _currentCallerId: $_currentCallerId ===',
        );

        if (_isCaller && from == _currentCalleeId) {
          print('=== We initiated call, callee cancelled/rejected ===');
          _state = CallState.ended;
          _isCaller = false;
          _currentCalleeId = null;
          _disconnectLiveKit();
          if (onCallEnded != null) {
            print('=== Calling onCallEnded for caller ===');
            onCallEnded!();
          }
          if (onCallCancelled != null) {
            onCallCancelled!();
          }
        } else if (!_isCaller && from == _currentCallerId) {
          print('=== We received call, caller cancelled ===');
          _state = CallState.ended;
          _currentCallerId = null;
          _disconnectLiveKit();
          if (onCallEnded != null) {
            print('=== Calling onCallEnded for receiver ===');
            onCallEnded!();
          }
          if (onCallCancelled != null) {
            onCallCancelled!();
          }
        } else {
          print('=== Ignoring call end - not our call ===');
        }
        break;
    }
  }

  static Future<void> _connectToLiveKit() async {
    if (_roomName != null && _token != null && _livekitUrl != null) {
      print('=== Connecting to LiveKit ===');
      print('URL: $_livekitUrl');
      print('Room: $_roomName');
      print('Token: ${_token!.substring(0, 20)}...');
      try {
        await LiveKitManager.connectToRoom(_livekitUrl!, _token!);
        print('=== LiveKit connected ===');
      } catch (e, stack) {
        print('=== LiveKit connection failed: $e ===');
        print(stack);
        _handleCallFailure('LiveKit connection failed');
      }
    } else {
      print('=== Missing LiveKit params ===');
      print('URL: $_livekitUrl');
      print('Room: $_roomName');
      print('Token: ${_token != null ? "present" : "null"}');
      _handleCallFailure('Missing LiveKit params');
    }
  }

  static void _handleCallFailure(String reason) {
    _state = CallState.ended;
    _isCaller = false;
    _currentCallerId = null;
    _currentCalleeId = null;
    _roomName = null;
    _token = null;
    _livekitUrl = null;
    _disconnectLiveKit();
    if (onCallEnded != null) {
      onCallEnded!();
    }
    if (onCallCancelled != null) {
      onCallCancelled!();
    }
  }

  static void _disconnectLiveKit() async {
    try {
      await LiveKitManager.disconnect();
    } catch (e) {
      print('=== Error disconnecting LiveKit: $e ===');
    }
  }

  static Future<void> startCall(
    String targetUserId, {
    bool isVideo = true,
  }) async {
    print('=== startCall called: target=$targetUserId, isVideo=$isVideo ===');
    print('=== startCall: current channel: ${_channel != null} ===');

    try {
      await connectWebSocket();
      print('=== startCall: after connect, channel: ${_channel != null} ===');

      _state = CallState.calling;
      _isCaller = true;
      _currentCalleeId = targetUserId;

      // Initiate the call timeout timer.
      _startCallTimeoutTimer();

      // Include the `service_name` in the search (so that only users with the same `service_name` are found on the backend).
      final message = jsonEncode({
        'action': 'call',
        'to': targetUserId,
        'call_type': isVideo ? 'video' : 'audio',
        'service_name': SDKConfig.serviceName, // The name of the app developed by the developer.
      });
      print('=== Sending message: $message ===');

      _channel!.sink.add(message);
      print('=== Message sent successfully ===');
    } catch (e, stack) {
      print('=== startCall error: $e ===');
      print('=== Stack: $stack ===');
    }
  }

  /// Initiate the call timeout timer.
  static void _startCallTimeoutTimer() {
    _cancelCallTimeoutTimer();
    _callTimeoutTimer = Timer(Duration(seconds: _callTimeoutSeconds), () {
      if (_state == CallState.calling || _state == CallState.ringing) {
        print('=== Call timeout: ${_callTimeoutSeconds} seconds elapsed ===');
        _state = CallState.ended;
        if (onCallTimeout != null) {
          onCallTimeout!();
        }
        if (onCallEnded != null) {
          onCallEnded!();
        }
      }
    });
  }

  /// Cancel timeout timer
  static void _cancelCallTimeoutTimer() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  /// If the connection is successful, the timeout timer will be cancelled.
  static void _clearCallTimeoutOnConnect() {
    _cancelCallTimeoutTimer();
  }

  static Future<void> acceptCall(String callerId) async {
    _isCaller = false;
    _currentCallerId = callerId;
    _channel?.sink.add(
      jsonEncode({
        'action': 'accept',
        'to': callerId,
        'call_id': _currentCallId,
      }),
    );
  }

  static Future<void> rejectCall(String callerId) async {
    _channel?.sink.add(
      jsonEncode({
        'action': 'reject',
        'to': callerId,
        'call_id': _currentCallId,
      }),
    );
    _state = CallState.ended;
    _currentCallerId = null;
    _currentCallId = null;
  }

  static Future<void> endCall(String? calleeId) async {
    if (calleeId != null) {
      _channel?.sink.add(
        jsonEncode({
          'action': 'end',
          'to': calleeId,
          'call_id': _currentCallId,
        }),
      );
    }

    try {
      await LiveKitManager.disconnect().timeout(const Duration(seconds: 2));
    } catch (e) {
      print('=== LiveKit disconnect error on endCall: $e ===');
    }
    _state = CallState.idle;
    _roomName = null;
    _token = null;
    _livekitUrl = null;
    _isCaller = false;
    _currentCallerId = null;
    _currentCalleeId = null;
    _currentCallId = null;
  }

  static void resetState() {
    _state = CallState.idle;
    _roomName = null;
    _token = null;
    _livekitUrl = null;
    _isCaller = false;
    _currentCallerId = null;
    _currentCalleeId = null;
    _currentCallId = null;
  }

  static void disconnectWebSocket() {
    _channel?.sink.close();
    _channel = null;
    print('=== WebSocket disconnected ===');
  }
}
