package online.ipstack.videocallsample

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager

class IncomingCallActivity : Activity() {
    companion object {
        fun start(context: Context, callerId: String, callType: String, callId: String) {
            val intent = Intent(context, IncomingCallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("caller_id", callerId)
                putExtra("call_type", callType)
                putExtra("call_id", callId)
            }
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 화면을 항상 켜짐으로 유지
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        
        val callerId = intent.getStringExtra("caller_id") ?: "Unknown"
        val callType = intent.getStringExtra("call_type") ?: "video"
        val callId = intent.getStringExtra("call_id") ?: "0"

        // Flutter View를 표시하는 간단한 레이아웃
        setContentView(android.widget.FrameLayout(this).apply {
            setBackgroundColor(android.graphics.Color.parseColor("#0955fa"))
            
            val callerText = android.widget.TextView(this@IncomingCallActivity).apply {
                text = if (callType == "video") "Video Call\nFrom: $callerId" else "Audio Call\nFrom: $callerId"
                setTextColor(android.graphics.Color.WHITE)
                textSize = 24f
                gravity = android.view.Gravity.CENTER
            }
            addView(callerText, android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = android.view.Gravity.CENTER
            })
        })

        // 5초 후 자동 종료 (테스트용)
        android.os.Handler(mainLooper).postDelayed({
            finish()
        }, 30000)
    }

    override fun onBackPressed() {
        // 백버튼으로 종료 방지
    }
}