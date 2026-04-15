import Flutter
import UIKit
import PushKit
import CallKit
import flutter_callkit_incoming

@main
class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {

    var voipRegistry: PKPushRegistry!
    var flutterChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            flutterChannel = FlutterMethodChannel(
                name: "online.ipstack.videocall/voip",
                binaryMessenger: controller.binaryMessenger
            )
        }

        setupVoIPPush()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - VoIP Push Registration
    func setupVoIPPush() {
        voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
    }

    // VoIP Token 등록
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {

        let token = pushCredentials.token.map {
            String(format: "%02x", $0)
        }.joined()

        print("VoIP Token: \(token)")
        flutterChannel?.invokeMethod("updateVoipToken", arguments: token)
    }

    // VoIP Push 수신
    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      withCompletionHandler completion: @escaping () -> Void) {

        let extra: [String: Any] = payload.dictionaryPayload.reduce(into: [:]) { result, entry in
            result[String(describing: entry.key)] = entry.value
        }
        print("VoIP Push Received: \(extra)")

        let callerName = extra["caller_name"] as? String ?? extra["from"] as? String ?? "Unknown"
        let callId = (extra["call_id"] as? String) ?? "\(extra["call_id"] ?? UUID().uuidString)"
        let callType = extra["call_type"] as? String ?? "video"
        let isVideo = callType == "video"

        let callData: [String: Any] = [
            "id": callId,
            "nameCaller": callerName,
            "handle": callerName,
            "type": isVideo ? 1 : 0,
            "extra": extra
        ]

        let data = flutter_callkit_incoming.Data(args: callData as NSDictionary)
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?
            .showCallkitIncoming(data, fromPushKit: true) {
                completion()
            }

    }
}
