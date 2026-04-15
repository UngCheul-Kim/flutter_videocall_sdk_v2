package online.ipstack.videocallsample

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra("call_id") ?: "0"
        
        when (intent.action) {
            IncomingCallService.ACTION_ACCEPT -> {
                // 통화 수락 처리
                // Flutter 앱으로 연결
                IncomingCallService.stopService(context)
                
                val mainIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("action", "accept_call")
                    putExtra("call_id", callId)
                }
                context.startActivity(mainIntent)
            }
            IncomingCallService.ACTION_REJECT -> {
                // 통화 거절 처리
                IncomingCallService.stopService(context)
            }
        }
    }
}