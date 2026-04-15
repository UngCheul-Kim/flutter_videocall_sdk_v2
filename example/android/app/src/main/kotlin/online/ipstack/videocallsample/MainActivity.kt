package online.ipstack.videocallsample

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.net.Uri
import android.provider.Settings

class MainActivity: FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "online.ipstack.videocall/incoming_call")
        IncomingCallService.methodChannel = channel

        channel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showIncomingCallOverlay" -> {
                        val callerId = call.argument<String>("callerId") ?: "Unknown"
                        val callId = call.argument<String>("callId") ?: "0"
                        val callType = call.argument<String>("callType") ?: "video"

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.error("PERMISSION_DENIED", "Overlay permission not granted", null)
                            return@setMethodCallHandler
                        }

                        IncomingCallService.startService(this, callerId, callType, callId)
                        result.success(true)
                    }
                    "startIncomingCallService" -> {
                        val callerId = call.argument<String>("callerId") ?: "Unknown"
                        val callId = call.argument<String>("callId") ?: "0"
                        val callType = call.argument<String>("callType") ?: "video"

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.error("PERMISSION_DENIED", "Overlay permission not granted", null)
                            return@setMethodCallHandler
                        }

                        IncomingCallService.startService(this, callerId, callType, callId)
                        result.success(true)
                    }
                    "hideIncomingCallOverlay" -> {
                        IncomingCallService.stopService(this)
                        result.success(true)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
    
    private fun handleCallIntent(intent: Intent) {
        println("=== MainActivity handleCallIntent: ${intent.action} ===")
    }
}
