package online.ipstack.videocallsample

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.view.WindowManager
import android.view.WindowManager.LayoutParams
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

class IncomingCallService : Service() {
    companion object {
        const val CHANNEL_ID = "incoming_call_channel"
        const val CHANNEL_NAME = "Incoming Calls"
        const val NOTIFICATION_ID = 1001
        const val ACTION_ACCEPT = "ACTION_ACCEPT"
        const val ACTION_REJECT = "ACTION_REJECT"
        
        // Flutter로 이벤트를 전달하기 위한 MethodChannel
        var methodChannel: MethodChannel? = null
        
        fun startService(context: Context, callerId: String, callType: String, callId: String) {
            val intent = Intent(context, IncomingCallService::class.java).apply {
                putExtra("caller_id", callerId)
                putExtra("call_type", callType)
                putExtra("call_id", callId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, IncomingCallService::class.java)
            context.stopService(intent)
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: android.view.View? = null
    private var ringtone: Ringtone? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callerId = intent?.getStringExtra("caller_id") ?: "Unknown"
        val callType = intent?.getStringExtra("call_type") ?: "video"
        val callId = intent?.getStringExtra("call_id") ?: "0"

        showIncomingCallNotification(callerId, callType, callId)
        showOverlayView(callerId, callType, callId)
        startRingtone()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        removeOverlayView()
        stopRingtone()
    }

    private fun startRingtone() {
        try {
            if (ringtone?.isPlaying == true) return
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val r = RingtoneManager.getRingtone(applicationContext, uri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                r.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }
            ringtone = r
            r.play()
        } catch (_: Exception) {
        }
    }

    private fun stopRingtone() {
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        } finally {
            ringtone = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call notifications"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun showIncomingCallNotification(callerId: String, callType: String, callId: String) {
        val acceptIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = ACTION_ACCEPT
            putExtra("call_id", callId)
            putExtra("caller_id", callerId)
            putExtra("call_type", callType)
        }
        val rejectIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = ACTION_REJECT
            putExtra("call_id", callId)
            putExtra("caller_id", callerId)
            putExtra("call_type", callType)
        }

        val acceptPending = PendingIntent.getBroadcast(
            this, 0, acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val rejectPending = PendingIntent.getBroadcast(
            this, 1, rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(if (callType == "video") "Video Call" else "Audio Call")
            .setContentText("Incoming call from $callerId")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .addAction(android.R.drawable.ic_menu_call, "Accept", acceptPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", rejectPending)
            .setAutoCancel(false)
            .setOngoing(true)

        val notification = builder.build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun showOverlayView(callerId: String, callType: String, callId: String) {
        removeOverlayView()

        val params = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                LayoutParams.TYPE_PHONE
            },
            LayoutParams.FLAG_NOT_FOCUSABLE or
            LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        )

        overlayView = android.widget.FrameLayout(this).apply {
            setBackgroundColor(android.graphics.Color.parseColor("#E6000000"))
            
            val container = android.widget.LinearLayout(context).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                gravity = android.view.Gravity.CENTER
                setPadding(0, 200, 0, 0)
                
                val titleText = android.widget.TextView(context).apply {
                    text = if (callType == "video") "Video Call" else "Audio Call"
                    setTextColor(android.graphics.Color.WHITE)
                    textSize = 32f
                    gravity = android.view.Gravity.CENTER
                }
                addView(titleText)
                
                val callerText = android.widget.TextView(context).apply {
                    text = "From: $callerId"
                    setTextColor(android.graphics.Color.WHITE)
                    textSize = 24f
                    gravity = android.view.Gravity.CENTER
                    setPadding(0, 40, 0, 80)
                }
                addView(callerText)
                
                val buttonContainer = android.widget.LinearLayout(context).apply {
                    orientation = android.widget.LinearLayout.HORIZONTAL
                    gravity = android.view.Gravity.CENTER
                    
                    val acceptButton = android.widget.Button(context).apply {
                        text = "Accept"
                        textSize = 20f
                        setBackgroundColor(android.graphics.Color.parseColor("#4CAF50"))
                        setTextColor(android.graphics.Color.WHITE)
                        setPadding(60, 30, 60, 30)
                        setOnClickListener {
                            // Flutter에 Accept 이벤트 전달
                            methodChannel?.invokeMethod("onAcceptCall", mapOf(
                                "callerId" to callerId,
                                "callType" to callType,
                                "callId" to callId
                            ))
                            removeOverlayView()
                            stopSelf()
                        }
                    }
                    addView(acceptButton)
                    
                    val spacer = android.view.View(context).apply {
                        layoutParams = android.widget.LinearLayout.LayoutParams(40, 1)
                    }
                    addView(spacer)
                    
                    val declineButton = android.widget.Button(context).apply {
                        text = "Decline"
                        textSize = 20f
                        setBackgroundColor(android.graphics.Color.parseColor("#F44336"))
                        setTextColor(android.graphics.Color.WHITE)
                        setPadding(60, 30, 60, 30)
                        setOnClickListener {
                            // Flutter에 Decline 이벤트 전달
                            methodChannel?.invokeMethod("onDeclineCall", mapOf(
                                "callerId" to callerId,
                                "callId" to callId
                            ))
                            removeOverlayView()
                            stopSelf()
                        }
                    }
                    addView(declineButton)
                }
                addView(buttonContainer)
            }
            addView(container, android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT
            ))
        }

        try {
            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun removeOverlayView() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            overlayView = null
        }
    }
}
