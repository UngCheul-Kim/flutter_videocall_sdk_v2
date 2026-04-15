import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_ipstack_videocall/flutter_ipstack_videocall.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Global NavigatorKey - Allows displaying screens even when the app is in the background
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

String? _lastIncomingUiCallId;
DateTime? _lastIncomingUiAt;
AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
Route<dynamic>? _incomingCallRoute;
String? _incomingCallRouteCallId;

void _updateAppForegroundState(AppLifecycleState state) {
  if (_appLifecycleState != state) {
    _appLifecycleState = state;
    print('=== App lifecycle state: $_appLifecycleState ===');
  }
}

bool _canShowFlutterIncomingUi() {
  return _appLifecycleState != AppLifecycleState.paused &&
      _appLifecycleState != AppLifecycleState.detached;
}

void _dismissIncomingCallUi() {
  final state = navigatorKey.currentState;
  final route = _incomingCallRoute;
  if (state != null && route != null) {
    try {
      state.removeRoute(route);
    } catch (_) {}
  }
  _incomingCallRoute = null;
  _incomingCallRouteCallId = null;
}

Future<void> _hideIncomingCallOverlay() async {
  try {
    const platform = MethodChannel('online.ipstack.videocall/incoming_call');
    await platform.invokeMethod('hideIncomingCallOverlay');
  } catch (_) {}
}

void _returnToHomeAfterCallTerminated() {
  RingtonePlayer.stop();
  _dismissIncomingCallUi();
  unawaited(_hideIncomingCallOverlay());
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
}

// User ID save/load utility (using flutter_secure_storage)
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

// Handler for receiving push notifications in the background
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  print('=== Background message received: ${message.data} ===');

  final data = message.data;
  final callType = data['type'] ?? data['call_type'] ?? 'video';
  final callerId = data['caller_id'] ?? data['from'] ?? 'Unknown';
  final callId =
      data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

  if (callType == 'incoming_call' || data['action'] == 'incoming_call') {
    print('=== Incoming call in background - showing CallKit ===');
    await _showCallKitIncoming(callerId, callId, callType, playSound: true);
  }
}

// Handler called when an incoming call arrives in the foreground
Future<bool> _handleForegroundIncomingCall(
    String callerId, String callId, String callType) async {
  print('=== Foreground incoming call: $callerId, $callType ===');

  try {
    const platform = MethodChannel('online.ipstack.videocall/incoming_call');
    await platform.invokeMethod('showIncomingCallOverlay', {
      'callerId': callerId,
      'callId': callId,
      'callType': callType,
    });
    return true;
  } catch (e) {
    print('=== Error showing overlay: $e ===');
    return false;
  }
}

// Function to display the incoming call screen globally (displays screen even when app is in the background)
void showIncomingCallUI(String callerId, String callType, String callId) {
  print(
      "=== showIncomingCallUI called: callerId=$callerId, callType=$callType ===");

  if (!_canShowFlutterIncomingUi()) {
    print(
        "=== showIncomingCallUI: app not active/resumed ($_appLifecycleState), skipping ===");
    return;
  }

  final now = DateTime.now();
  final lastAt = _lastIncomingUiAt;
  if (_lastIncomingUiCallId == callId &&
      lastAt != null &&
      now.difference(lastAt) < const Duration(seconds: 2)) {
    print("=== showIncomingCallUI: duplicate callId, skipping ===");
    return;
  }

  _lastIncomingUiCallId = callId;
  _lastIncomingUiAt = now;
  _showIncomingCallScreenDirect(callerId, callType, callId, attempt: 0);
}

// Attempt to display the screen directly
void _showIncomingCallScreenDirect(
    String callerId, String callType, String callId,
    {required int attempt}) {
  print("=== _showIncomingCallScreenDirect: Starting ===");

  final state = navigatorKey.currentState;
  if (state == null) {
    print("=== _showIncomingCallScreenDirect: Navigator state is null ===");
    if (attempt < 15) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _showIncomingCallScreenDirect(callerId, callType, callId,
            attempt: attempt + 1);
      });
    }
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    print("=== _showIncomingCallScreenDirect: In postFrameCallback ===");

    final state = navigatorKey.currentState;
    if (state == null) {
      print("=== _showIncomingCallScreenDirect: Navigator state is null ===");
      if (attempt < 15) {
        Future.delayed(const Duration(milliseconds: 200), () {
          _showIncomingCallScreenDirect(callerId, callType, callId,
              attempt: attempt + 1);
        });
      }
      return;
    }

    print(
        "=== _showIncomingCallScreenDirect: About to push IncomingCallScreen ===");

    if (_incomingCallRoute != null) {
      if (_incomingCallRouteCallId == callId) {
        return;
      }
      _dismissIncomingCallUi();
    }

    final route = MaterialPageRoute(
      builder: (_) => IncomingCallScreen(
        callerId: callerId,
        callType: callType,
      ),
    );
    _incomingCallRoute = route;
    _incomingCallRouteCallId = callId;

    state.push(route).then((result) {
      print(
          "=== _showIncomingCallScreenDirect: Push completed, result=$result ===");
      if (_incomingCallRoute == route) {
        _incomingCallRoute = null;
        _incomingCallRouteCallId = null;
      }
    }).catchError((error) {
      print("=== _showIncomingCallScreenDirect: Push error: $error ===");
      if (_incomingCallRoute == route) {
        _incomingCallRoute = null;
        _incomingCallRouteCallId = null;
      }
    });

    print("=== _showIncomingCallScreenDirect: Push called ===");
  });
}

// Set up CallKit event listener globally
void _setupCallKitListener() {
  FlutterCallkitIncoming.onEvent.listen((event) async {
    print('=== CallKit event: ${event?.event} ===');

    if (event?.event == Event.actionCallAccept) {
      final extra = event?.body?['extra'] as Map<String, dynamic>?;
      final callerId = extra?['from'] ?? extra?['caller_id'] ?? 'Unknown';
      print('=== Call accepted ===');
      _dismissIncomingCallUi();

      final savedUserId = await UserStorage.getUserId();
      final savedLicenseKey = await UserStorage.getLicenseKey();

      if (savedUserId != null && savedLicenseKey != null) {
        try {
          if (!VideoSDK.isInitialized) {
            await VideoSDK.initialize(
              licenseKey: savedLicenseKey,
              userId: savedUserId,
              serviceName: "IPSTACK_VideoCall_V2",
            );
          }
          CallManager.init();
          CallManager.acceptCall(callerId);
          print('=== Call accepted and SDK initialized ===');
        } catch (e) {
          print('=== Error initializing SDK on accept: $e ===');
        }
      }
    } else if (event?.event == Event.actionCallDecline) {
      final extra = event?.body?['extra'] as Map<String, dynamic>?;
      final callerId = extra?['from'] ?? extra?['caller_id'] ?? 'Unknown';
      print('=== Call declined ===');
      _dismissIncomingCallUi();
      CallManager.rejectCall(callerId);
    }
  });
}

// Handle events received from the native overlay service
const MethodChannel _nativeOverlayChannel =
    MethodChannel('online.ipstack.videocall/incoming_call');

void _setupNativeOverlayListener() {
  _nativeOverlayChannel.setMethodCallHandler((call) async {
    if (call.method == "onAcceptCall") {
      final callerId = (call.arguments["callerId"] ?? "Unknown").toString();
      final callType = (call.arguments["callType"] ?? "video").toString();
      print('=== Native overlay call accepted: $callerId ===');

      RingtonePlayer.stop();
      CallManager.acceptCall(callerId);
      _dismissIncomingCallUi();

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ActiveCallScreen(
            callType: callType,
            callerId: callerId,
          ),
        ),
      );
    } else if (call.method == "onDeclineCall") {
      final callerId = (call.arguments["callerId"] ?? "Unknown").toString();
      print('=== Native overlay call declined: $callerId ===');
      RingtonePlayer.stop();
      _dismissIncomingCallUi();
      CallManager.rejectCall(callerId);
    }
    return null;
  });
}

// Receive VoIP Push token (iOS)
const MethodChannel _voipChannel =
    MethodChannel('online.ipstack.videocall/voip');

void _setupVoIPChannel() {
  _voipChannel.setMethodCallHandler((call) async {
    if (call.method == "updateVoipToken") {
      final token = call.arguments as String?;
      print('=== VoIP Token received: $token ===');
      if (token != null && token.isNotEmpty) {
        // Register VoIP token directly to the server (when SDK initialization is complete)
        // Register via SDK's PushManager
        try {
          final savedUserId = await UserStorage.getUserId();
          final savedLicenseKey = await UserStorage.getLicenseKey();
          if (savedUserId != null && savedLicenseKey != null) {
            await _registerVoIPToken(token, savedUserId, savedLicenseKey);
          }
        } catch (e) {
          print('=== Error registering VoIP token: $e ===');
        }
      }
    }
    return null;
  });
}

// Register VoIP token to the server
Future<void> _registerVoIPToken(
    String token, String userId, String licenseKey) async {
  try {
    final url = 'https://videocall.ipstack.online/api/push/register';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_user_id': userId,
        'service_name': 'IPSTACK_VideoCall_V2',
        'device_id': VideoSDK.deviceId,
        'push_token': token,
        'platform': 'ios_voip',
        'license_key': licenseKey,
      }),
    );
    if (response.statusCode == 200) {
      print('=== VoIP token registered successfully ===');
    } else {
      print('=== VoIP token registration failed: ${response.statusCode} ===');
    }
  } catch (e) {
    print('=== Error registering VoIP token: $e ===');
  }
}

// Display CallKitIncoming screen in the background
Future<void> _showCallKitIncoming(
    String callerId, String callId, String callType,
    {bool playSound = true}) async {
  try {
    final isVideoCall = callType == 'video';
    final callTypeText = isVideoCall ? 'VideoCall' : 'AudioCall';

    final params = CallKitParams(
      id: callId,
      nameCaller: '$callTypeText\nCaller: $callerId',
      appName: 'VideoCall',
      avatar: '',
      handle: callerId,
      type: isVideoCall ? 1 : 0,
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
    print('=== CallKit incoming shown: $callTypeText from $callerId ===');
  } catch (e) {
    print('=== Error showing CallKit: $e ===');
  }
}

class RingtonePlayer {
  static final AudioPlayer _player = AudioPlayer();
  static bool _isPlaying = false;

  static Future<void> play() async {
    if (_isPlaying) return;
    _isPlaying = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    try {
      await _player.play(AssetSource('ringtone.mp3'));
    } catch (e) {
      print('=== Error playing ringtone: $e ===');
    }
  }

  static Future<void> stop() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    await _player.stop();
  }

  static bool isPlaying() => _isPlaying;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseInitError;
  try {
    await Firebase.initializeApp();
  } catch (e) {
    firebaseInitError = e.toString();
    print('=== Firebase.initializeApp failed: $firebaseInitError ===');
  }

  if (firebaseInitError == null) {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) async {
      print('=== Foreground message received: ${message.data} ===');
      final data = message.data;
      final action = data['action'] ?? data['type'];
      if (action == 'incoming_call') {
        final callerId =
            (data['caller_id'] ?? data['from'] ?? 'Unknown').toString();
        final callType = (data['call_type'] ?? 'video').toString();
        final callId =
            (data['call_id'] ?? DateTime.now().millisecondsSinceEpoch)
                .toString();

        showIncomingCallUI(callerId, callType, callId);
        if (!RingtonePlayer.isPlaying()) {
          RingtonePlayer.play();
        }
      }
    });
  }

  // Set up CallKit event listener globally
  _setupCallKitListener();

  // Native overlay service event listener (Android)
  _setupNativeOverlayListener();

  // VoIP Push token listener (iOS)
  _setupVoIPChannel();

  runApp(InitApp(firebaseInitError: firebaseInitError));
}

class InitApp extends StatefulWidget {
  final String? firebaseInitError;

  const InitApp({super.key, required this.firebaseInitError});

  @override
  State<InitApp> createState() => _InitAppState();
}

class _InitAppState extends State<InitApp> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _savedUserId;
  String? _savedLicenseKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateAppForegroundState(AppLifecycleState.resumed);
    _checkSavedUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateAppForegroundState(state);
  }

  Future<void> _checkSavedUser() async {
    final userId = await UserStorage.getUserId();
    final licenseKey = await UserStorage.getLicenseKey();

    if (userId != null &&
        userId.isNotEmpty &&
        licenseKey != null &&
        licenseKey.isNotEmpty) {
      setState(() {
        _savedUserId = userId;
        _savedLicenseKey = licenseKey;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (widget.firebaseInitError != null) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Firebase init failed:\n${widget.firebaseInitError}'),
            ),
          ),
        ),
      );
    }

    // If a saved user exists, automatically initialize SDK and go to main
    if (_savedUserId != null && _savedLicenseKey != null) {
      return _AutoLoginApp(
          savedUserId: _savedUserId!, savedLicenseKey: _savedLicenseKey!);
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IPStack VideoSDK Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

// Auto-login widget
class _AutoLoginApp extends StatefulWidget {
  final String savedUserId;
  final String savedLicenseKey;

  const _AutoLoginApp(
      {required this.savedUserId, required this.savedLicenseKey});

  @override
  State<_AutoLoginApp> createState() => _AutoLoginAppState();
}

class _AutoLoginAppState extends State<_AutoLoginApp> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _autoLogin();
  }

  Future<void> _autoLogin() async {
    try {
      // If no saved info exists, go to login page
      if (widget.savedUserId.isEmpty || widget.savedLicenseKey.isEmpty) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
        return;
      }

      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isDenied || micStatus.isDenied) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
        return;
      }

      // Skip initialization if SDK is already initialized
      if (!VideoSDK.isInitialized) {
        await VideoSDK.initialize(
          licenseKey: widget.savedLicenseKey,
          userId: widget.savedUserId,
          serviceName: "IPSTACK_VideoCall_V2",
        );
      }

      CallManager.init();
      PushManager.init();

      // WebSocket connection
      CallManager.connectWebSocket();

      // Set up PushManager's incoming call handler
      PushManager.onIncomingCall = (call) async {
        print('=== PushManager onIncomingCall (auto login): $call ===');

        final callerId =
            (call['from'] ?? call['caller_id'] ?? 'Unknown').toString();
        final callType = (call['call_type'] ?? 'video').toString();
        final callId =
            (call['call_id'] ?? DateTime.now().millisecondsSinceEpoch)
                .toString();

        if (_canShowFlutterIncomingUi()) {
          showIncomingCallUI(callerId, callType, callId);
          if (!RingtonePlayer.isPlaying()) {
            RingtonePlayer.play();
          }
          return;
        }

        final overlayShown =
            await _handleForegroundIncomingCall(callerId, callId, callType);
        if (!overlayShown) {
          await _showCallKitIncoming(callerId, callId, callType);
        }
      };

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomePage(currentUserId: widget.savedUserId),
          ),
        );
      }
    } catch (e) {
      print('=== Auto login error: $e ===');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Auto login as ${widget.savedUserId}...'),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userIdController = TextEditingController();
  bool _isInitializing = false;
  String? _error;

  static const String _apiUrl = "https://videocall.ipstack.online";
  static const String _licenseKey = "Your License Key";

  @override
  void initState() {
    super.initState();
    // If a saved userId exists, auto-fill it
    _loadSavedUserId();
  }

  Future<void> _loadSavedUserId() async {
    final savedUserId = await UserStorage.getUserId();
    if (savedUserId != null && savedUserId.isNotEmpty) {
      if (mounted) {
        _userIdController.text = savedUserId;
        // If a saved ID exists, attempt auto-login
        _initializeSDK();
      }
    }
  }

  Future<void> _initializeSDK() async {
    final userId = _userIdController.text.trim();

    if (userId.isEmpty) {
      return; // Wait if empty (may be in the middle of auto-login attempt)
    }

    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isDenied || micStatus.isDenied) {
        setState(() {
          _error = "Camera and microphone permissions are required";
          _isInitializing = false;
        });
        return;
      }

      await VideoSDK.initialize(
        licenseKey: _licenseKey,
        userId: userId,
        serviceName: "IPSTACK_VideoCall_V2",
      );

      CallManager.init();
      PushManager.init();

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
        setState(() {
          _error = message;
          _isInitializing = false;
        });
        _showLicenseErrorDialog(message);
      };

      _setupPushHandlers();

      CallManager.connectWebSocket();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomePage(currentUserId: userId),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = "Initialization failed: $e";
        _isInitializing = false;
      });
    }
  }

  void _setupPushHandlers() {
    PushManager.onIncomingCall = (call) async {
      print('=== PushManager onIncomingCall: $call ===');

      final callerId =
          (call['from'] ?? call['caller_id'] ?? 'Unknown').toString();
      final callType = (call['call_type'] ?? 'video').toString();
      final callId =
          (call['call_id'] ?? DateTime.now().millisecondsSinceEpoch).toString();

      if (_canShowFlutterIncomingUi()) {
        showIncomingCallUI(callerId, callType, callId);
        if (!RingtonePlayer.isPlaying()) {
          RingtonePlayer.play();
        }
        return;
      }

      final overlayShown =
          await _handleForegroundIncomingCall(callerId, callId, callType);
      if (!overlayShown) {
        await _showCallKitIncoming(callerId, callId, callType);
      }
    };

    PushManager.onCallEnded = (call) {
      RingtonePlayer.stop();
      CallManager.onCallEnded?.call();
    };

    PushManager.onCallAccepted = (call) {
      print('=== Push call accepted: $call ===');
    };
  }

  void _showLicenseErrorDialog(String message) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video SDK V2 - Login'),
        backgroundColor: Colors.blue.shade100,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.video_call, size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                const Text(
                  'Video SDK V2 Example',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Offline Push Support Enabled',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _userIdController,
                  decoration: const InputDecoration(
                    labelText: 'User ID (DB ID or Email)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    hintText: 'Enter your user ID (e.g., 1, 2, user@test.com)',
                  ),
                  onSubmitted: (_) => _initializeSDK(),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton.icon(
                  onPressed: _isInitializing ? null : _initializeSDK,
                  icon: _isInitializing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(_isInitializing ? 'Initializing...' : 'Start'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String currentUserId;

  const HomePage({super.key, required this.currentUserId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _userIdController = TextEditingController();
  bool _isInCall = false;
  String _callType = 'video';

  @override
  void initState() {
    super.initState();

    CallManager.onIncomingCall = (call) {
      final callerId =
          (call['from'] ?? call['caller_id'] ?? 'Unknown').toString();
      final callType = (call['call_type'] ?? 'video').toString();
      final callId =
          (call['call_id'] ?? DateTime.now().millisecondsSinceEpoch).toString();
      if (_canShowFlutterIncomingUi()) {
        showIncomingCallUI(callerId, callType, callId);
        RingtonePlayer.play();
        return;
      }

      unawaited(() async {
        final overlayShown =
            await _handleForegroundIncomingCall(callerId, callId, callType);
        if (!overlayShown) {
          await _showCallKitIncoming(callerId, callId, callType);
        }
      }());
    };

    CallManager.onCallCancelled = () {
      unawaited(_hideIncomingCallOverlay());
      _returnToHomeAfterCallTerminated();
    };

    CallManager.onCallEnded = () {
      unawaited(_hideIncomingCallOverlay());
      _returnToHomeAfterCallTerminated();
    };

    // Call connection timeout (when the other party does not answer)
    CallManager.onCallTimeout = () {
      print('=== Call timeout - showing error dialog ===');
      RingtonePlayer.stop();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Connection Failed'),
          content: const Text('The other party is not answering.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video SDK V2 Example'),
        backgroundColor: Colors.blue.shade100,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              VideoSDK.reset();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.green),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My User ID',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        widget.currentUserId,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Push notifications enabled - Receive calls offline',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter User ID to call',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'User ID to call',
                border: OutlineInputBorder(),
                hintText: 'Enter user ID',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                if (_userIdController.text.isNotEmpty) {
                  await VideoSDK.startVideoCall(_userIdController.text);
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ActiveCallScreen(
                          callType: 'video',
                          callerId: _userIdController.text,
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.videocam),
              label: const Text('Video Call'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                if (_userIdController.text.isNotEmpty) {
                  await VideoSDK.startAudioCall(_userIdController.text);
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ActiveCallScreen(
                          callType: 'audio',
                          callerId: _userIdController.text,
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.call),
              label: const Text('Audio Call'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IncomingCallScreen extends StatelessWidget {
  final String callerId;
  final String callType;

  const IncomingCallScreen({
    super.key,
    required this.callerId,
    required this.callType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'Incoming $callType call',
              style: const TextStyle(fontSize: 24),
            ),
            Text('From: $callerId'),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  onPressed: () {
                    CallManager.acceptCall(callerId);
                    RingtonePlayer.stop();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ActiveCallScreen(
                          callType: callType,
                          callerId: callerId,
                        ),
                      ),
                    );
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.call),
                ),
                const SizedBox(width: 32),
                FloatingActionButton(
                  onPressed: () {
                    CallManager.rejectCall(callerId);
                    RingtonePlayer.stop();
                    Navigator.of(context).pop();
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ActiveCallScreen extends StatefulWidget {
  final String callType;
  final String callerId;

  const ActiveCallScreen({
    super.key,
    required this.callType,
    required this.callerId,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _isConnected = false;
  bool _isVideoEnabled = true;
  bool _isMuted = false;
  RemoteVideoTrack? _remoteVideoTrack;
  VideoTrack? _localVideoTrack;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    CallManager.onCallConnected = () {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _localVideoTrack = LiveKitManager.localVideoTrack;
        });
      }
      _startVideoRefresh();
    };
    CallManager.onCallEnded = () {
      _refreshTimer?.cancel();
      try {
        LiveKitManager.disconnect();
      } catch (e) {
        print('=== Error disconnecting LiveKit: $e ===');
      }
      _returnToHomeAfterCallTerminated();
    };
    CallManager.onCallCancelled = () {
      _refreshTimer?.cancel();
      try {
        LiveKitManager.disconnect();
      } catch (e) {
        print('=== Error disconnecting LiveKit: $e ===');
      }
      _returnToHomeAfterCallTerminated();
    };
    CallManager.onCallTimeout = () {
      _refreshTimer?.cancel();
      try {
        LiveKitManager.disconnect();
      } catch (e) {
        print('=== Error disconnecting LiveKit: $e ===');
      }
      _returnToHomeAfterCallTerminated();
    };
  }

  void _startVideoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || !_isConnected) {
        timer.cancel();
        return;
      }
      final remoteTrack = LiveKitManager.remoteVideoTrack;
      if (remoteTrack != null &&
          (_remoteVideoTrack == null || _remoteVideoTrack != remoteTrack)) {
        if (mounted) {
          setState(() {
            _remoteVideoTrack = remoteTrack;
          });
        }
      }
      final localTrack = LiveKitManager.localVideoTrack;
      if (localTrack != null && _localVideoTrack != localTrack) {
        if (mounted) {
          setState(() {
            _localVideoTrack = localTrack;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    CallManager.onCallConnected = null;
    CallManager.onCallEnded = null;
    CallManager.onCallCancelled = null;
    CallManager.onCallTimeout = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.callType == 'video' ? 'Video Call' : 'Audio Call',
          style: const TextStyle(color: Colors.white),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            onPressed: () {
              unawaited(CallManager.endCall(widget.callerId));
              _returnToHomeAfterCallTerminated();
            },
          ),
        ],
      ),
      body: _isConnected && widget.callType == 'video'
          ? _buildVideoView()
          : (widget.callType == 'video'
              ? _buildConnectingView()
              : _buildAudioView()),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red,
        onPressed: () {
          unawaited(CallManager.endCall(widget.callerId));
          _returnToHomeAfterCallTerminated();
        },
        child: const Icon(Icons.call_end, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildVideoView() {
    return Stack(
      children: [
        if (_remoteVideoTrack != null)
          Positioned.fill(
            child: VideoTrackRenderer(
              _remoteVideoTrack!,
              fit: VideoViewFit.cover,
            ),
          )
        else
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam, size: 80, color: Colors.white54),
                    SizedBox(height: 16),
                    Text(
                      'Waiting for video...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 100,
          right: 16,
          child: Container(
            width: 120,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _localVideoTrack != null
                  ? VideoTrackRenderer(
                      _localVideoTrack!,
                      fit: VideoViewFit.cover,
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person, color: Colors.white54, size: 40),
                          SizedBox(height: 8),
                          Text(
                            'You',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Row(
            children: [
              _buildControlButton(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                label: _isMuted ? 'Mute' : 'Mic',
                onPressed: () async {
                  await CallManager.toggleMute();
                  setState(() {
                    _isMuted = !_isMuted;
                  });
                },
                isActive: !_isMuted,
              ),
              const SizedBox(width: 16),
              _buildControlButton(
                icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                label: _isVideoEnabled ? 'Video On' : 'Video Off',
                onPressed: () async {
                  await CallManager.toggleVideo();
                  setState(() {
                    _isVideoEnabled = !_isVideoEnabled;
                  });
                },
                isActive: _isVideoEnabled,
              ),
              const SizedBox(width: 16),
              _buildControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onPressed: () async {
                  await CallManager.switchCamera();
                },
                isActive: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isActive,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        iconSize: 24,
        padding: const EdgeInsets.all(12),
      ),
    );
  }

  Widget _buildAudioView() {
    return Stack(
      children: [
        const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.call, size: 80, color: Colors.green),
              SizedBox(height: 16),
              Text(
                'Voice Call Connected',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text('During the call...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Center(
            child: _buildControlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Unmute' : 'Mute',
              onPressed: () async {
                await CallManager.toggleMute();
                setState(() {
                  _isMuted = !_isMuted;
                });
              },
              isActive: !_isMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('Connecting...', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
