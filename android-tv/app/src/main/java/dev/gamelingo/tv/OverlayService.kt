package dev.gamelingo.tv

import android.app.*
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.provider.Settings
import android.util.Log
import android.view.*
import android.widget.TextView

class OverlayService : Service() {
    companion object { var active = false; private set }
    private lateinit var wm: WindowManager
    private var view: TextView? = null
    private val handler = Handler(Looper.getMainLooper())
    private val expire = Runnable { stopSelf() }
    private val hide = Runnable { view?.visibility = View.GONE }
    private var receiver: Receiver? = null
    private var live = false
    private val prefs by lazy { getSharedPreferences("overlay", MODE_PRIVATE) }
    private fun status(message: String) { prefs.edit().putString("status",message).apply() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notifications.createNotificationChannel(NotificationChannel("overlay", "ترجمة الألعاب", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "overlay")
            .setContentTitle("GameLingo TV").setContentText("طبقة الترجمة قيد التشغيل")
            .setContentIntent(open).setSmallIcon(R.drawable.logo).setOngoing(true).build()
        startForeground(1, notification)
    }
    private fun params(): WindowManager.LayoutParams {
        val placement = Placement.from(getSharedPreferences("overlay", MODE_PRIVATE).getString("position", null))
        val anchor = when (placement) { Placement.BOTTOM -> Gravity.BOTTOM; Placement.TOP -> Gravity.TOP; Placement.CENTER -> Gravity.CENTER_VERTICAL }
        return WindowManager.LayoutParams(-2, -2, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL or anchor
            y = if (placement == Placement.CENTER) 0 else (resources.displayMetrics.heightPixels * 0.08).toInt()
            setTitle("GameLingo subtitle")
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Settings.canDrawOverlays(this)) { Log.w("GameLingo", "Overlay permission absent"); stopSelf(); return START_NOT_STICKY }
        try {
            val existing = view
            if (existing == null) {
                val label = TextView(this).apply {
                    text = SAMPLE; textSize = 25f; setTextColor(Color.WHITE)
                    setShadowLayer(2f, 0f, 1f, Color.BLACK)
                    textDirection = View.TEXT_DIRECTION_RTL; gravity = Gravity.CENTER
                    setPadding(dp(18), dp(6), dp(18), dp(6))
                    background = GradientDrawable().apply { setColor(0xc923292b.toInt()); cornerRadius = dp(9).toFloat() }
                    maxWidth = (resources.displayMetrics.widthPixels * 0.88).toInt()
                }
                label.visibility = View.GONE
                wm.addView(label, params()); view = label; active = true
                Log.i("GameLingo", "Overlay attached")
            } else { wm.updateViewLayout(existing, params()) }
            when (intent?.action) {
                "move" -> Unit
                "connect" -> {
                    handler.removeCallbacks(expire); receiver?.stop(); live = true
                    receiver = Receiver(this, { message ->
                        handler.removeCallbacks(hide)
                        val label = view
                        if (message == null || label == null) hide.run() else {
                            label.text = message.getString("translated")
                            label.textSize = message.optDouble("font_sp",25.0).toFloat().coerceIn(14f,48f)
                            label.maxLines = 5
                            label.visibility = View.VISIBLE
                            wm.updateViewLayout(label,params())
                            handler.postDelayed(hide,message.getLong("remaining_ms"))
                            Log.i("GameLingo","Rendered sequence " + message.optLong("seq"))
                        }
                    }, ::status).also { it.start(intent.getStringExtra("host") ?: "", intent.getStringExtra("code") ?: "") }
                }
                else -> {
                    receiver?.stop(); receiver = null; live = false; handler.removeCallbacks(hide)
                    view?.apply { text = SAMPLE; visibility = View.VISIBLE }
                    status("اختبار الطبقة · ١٠ دقائق")
                    handler.removeCallbacks(expire); handler.postDelayed(expire, 600_000)
                }
            }
        } catch (e: RuntimeException) { Log.e("GameLingo", "Overlay unavailable", e); stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        receiver?.stop(); receiver = null
        handler.removeCallbacksAndMessages(null)
        view?.let { if (it.isAttachedToWindow) wm.removeViewImmediate(it) }; view = null; active = false
        Log.i("GameLingo", "Overlay service stopped")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
}
