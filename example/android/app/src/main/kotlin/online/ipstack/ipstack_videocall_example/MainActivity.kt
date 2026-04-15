package online.ipstack.ipstack_videocall_example

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import online.ipstack.videocallsample.IncomingCallActivity
import online.ipstack.videocallsample.IncomingCallService

class MainActivity : FlutterActivity() {
    private val CHANNEL = "online.ipstack.videocall/incoming_call"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // IncomingCallService에 MethodChannel 전달
        IncomingCallService.methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(
            { call, result ->
                when (call.method) {
                    "showIncomingCallOverlay" -> {
                        val callerId = call.argument<String>("callerId") ?: "Unknown"
                        val callType = call.argument<String>("callType") ?: "video"
                        val callId = call.argument<String>("callId") ?: "0"
                        showIncomingCall(callerId, callType, callId)
                        result.success(true)
                    }
                    "startIncomingCallService" -> {
                        // 오버레이 권한 체크
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.error("PERMISSION_DENIED", "Overlay permission not granted", null)
                            return@setMethodCallHandler
                        }

                        val callerId = call.argument<String>("callerId") ?: "Unknown"
                        val callType = call.argument<String>("callType") ?: "video"
                        val callId = call.argument<String>("callId") ?: "0"
                        startIncomingCallService(callerId, callType, callId)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        )
    }

    private fun showIncomingCall(callerId: String, callType: String, callId: String) {
        val context = this.applicationContext
        IncomingCallActivity.start(context, callerId, callType, callId)
    }

    private fun startIncomingCallService(callerId: String, callType: String, callId: String) {
        val context = this.applicationContext
        IncomingCallService.startService(context, callerId, callType, callId)
    }
}