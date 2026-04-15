import 'dart:async';
import 'package:livekit_client/livekit_client.dart';

class LiveKitManager {
  static Room? _room;
  static LocalVideoTrack? _localVideoTrack;
  static LocalAudioTrack? _localAudioTrack;
  static bool _isFrontCamera = true;

  static RemoteVideoTrack? _remoteVideoTrack;
  static RemoteAudioTrack? _remoteAudioTrack;

  static Room? get room => _room;
  static bool get isFrontCamera => _isFrontCamera;
  static LocalVideoTrack? get localVideoTrack => _localVideoTrack;
  static LocalAudioTrack? get localAudioTrack => _localAudioTrack;
  static RemoteVideoTrack? get remoteVideoTrack => _remoteVideoTrack;
  static RemoteAudioTrack? get remoteAudioTrack => _remoteAudioTrack;

  static Future<void> connectToRoom(String url, String token) async {
    _room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );

    _room!.events.on<TrackSubscribedEvent>(_onTrackSubscribed);
    _room!.events.on<TrackUnsubscribedEvent>(_onTrackUnsubscribed);

    await _room!.connect(url, token);

    _localVideoTrack = await LocalVideoTrack.createCameraTrack();
    _localAudioTrack = await LocalAudioTrack.create();

    await _room!.localParticipant?.publishVideoTrack(_localVideoTrack!);
    await _room!.localParticipant?.publishAudioTrack(_localAudioTrack!);

    await _room!.localParticipant?.setCameraEnabled(true);
    await _room!.localParticipant?.setMicrophoneEnabled(true);
  }

  static void _onTrackSubscribed(TrackSubscribedEvent event) {
    print('=== TrackSubscribedEvent: ${event.track} ===');
    if (event.track is RemoteVideoTrack) {
      _remoteVideoTrack = event.track as RemoteVideoTrack;
    } else if (event.track is RemoteAudioTrack) {
      _remoteAudioTrack = event.track as RemoteAudioTrack;
    }
  }

  static void _onTrackUnsubscribed(TrackUnsubscribedEvent event) {
    print('=== TrackUnsubscribedEvent: ${event.track} ===');
    if (event.track is RemoteVideoTrack) {
      _remoteVideoTrack = null;
    } else if (event.track is RemoteAudioTrack) {
      _remoteAudioTrack = null;
    }
  }

  static Future<void> disconnect() async {
    await _room?.disconnect();
    _room = null;
    _localVideoTrack = null;
    _localAudioTrack = null;
    _remoteVideoTrack = null;
    _remoteAudioTrack = null;
  }

  static List<RemoteParticipant> get remoteParticipants {
    if (_room == null) return [];
    return _room!.remoteParticipants.values.toList();
  }

  static RemoteParticipant? get firstRemoteParticipant {
    final participants = remoteParticipants;
    return participants.isNotEmpty ? participants.first : null;
  }

  static RemoteVideoTrack? get firstRemoteVideoTrack {
    final participant = firstRemoteParticipant;
    if (participant == null) return null;

    final videoTracks = participant.videoTrackPublications;
    for (final pub in videoTracks) {
      if (pub.track != null) {
        return pub.track;
      }
    }
    return null;
  }

  static Future<void> toggleMute() async {
    final enabled = _room?.localParticipant?.isMicrophoneEnabled() ?? false;
    await _room?.localParticipant?.setMicrophoneEnabled(!enabled);
  }

  static Future<void> toggleCamera() async {
    final enabled = _room?.localParticipant?.isCameraEnabled() ?? false;
    await _room?.localParticipant?.setCameraEnabled(!enabled);
  }

  static Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;

    try {
      final devices = await Hardware.instance.enumerateDevices();
      final cameras = devices.where((d) => d.kind == 'videoinput').toList();

      if (cameras.isEmpty) {
        print('No cameras found');
        return;
      }

      String? targetDeviceId;
      for (final camera in cameras) {
        final label = camera.label.toLowerCase();
        final isFrontCamera =
            label.contains('front') || label.contains('facing front');

        if (_isFrontCamera && isFrontCamera) {
          targetDeviceId = camera.deviceId;
          break;
        } else if (!_isFrontCamera && !isFrontCamera) {
          targetDeviceId = camera.deviceId;
          break;
        }
      }

      targetDeviceId ??= cameras.first.deviceId;

      if (_localVideoTrack != null) {
        await _localVideoTrack!.switchCamera(targetDeviceId, fastSwitch: true);
        print('Camera switched to: ${_isFrontCamera ? "front" : "back"}');
      } else {
        print('Local video track not available');
      }
    } catch (e) {
      print('Error switching camera: $e');
    }
  }

  static Future<void> toggleSpeaker() async {
    await Hardware.instance.setSpeakerphoneOn(true);
  }

  static Future<void> setAudioEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  static Future<void> setVideoEnabled(bool enabled) async {
    await _room?.localParticipant?.setCameraEnabled(enabled);
  }

  static void resetTracks() {
    _localVideoTrack = null;
    _localAudioTrack = null;
    _remoteVideoTrack = null;
    _remoteAudioTrack = null;
  }
}
