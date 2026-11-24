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
    companion object {
        var active = false; private set
        var connected = false; private set
        var connecting = false; private set
        var previewing = false; private set
    }
    private lateinit var wm: WindowManager
    private var view: SubtitleCanvas? = null
    private val handler = Handler(Looper.getMainLooper())
    private val expire = Runnable { stopSelf() }
    private val hide = Runnable { view?.visibility = View.GONE }
    private var receiver: Receiver? = null
    private var live = false
    private val prefs by lazy { getSharedPreferences("overlay", MODE_PRIVATE) }
    private fun status(message: String) {
        connected = active && live && receiver?.authenticated == true
        connecting = active && live && receiver?.connecting == true
        previewing = active && !live
        prefs.edit().putString("status",message).apply()
    }
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
        return WindowManager.LayoutParams(-1, -1, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            y = 0
            setTitle("GameLingo subtitle")
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Settings.canDrawOverlays(this)) { Log.w("GameLingo", "Overlay permission absent"); stopSelf(); return START_NOT_STICKY }
        try {
            val existing = view
            if (existing == null) {
                val label = SubtitleCanvas(this, ::status).apply {
                    onControl={message->receiver?.control(message)}
                    onEditingChanged={editing->
                        val options=params()
                        if(editing) options.flags=WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        view?.let { wm.updateViewLayout(it,options);it.isFocusableInTouchMode=editing;if(editing)it.requestFocus() }
                    }
                    onRendered={ id -> receiver?.acknowledge(id) }
                    onRenderedTrace={ id,trace -> receiver?.acknowledge(id,trace) }
                    val saved=prefs.getString("display_settings",null)
                    if(saved!=null) style=org.json.JSONObject(saved)
                }
                label.visibility = View.GONE
                wm.addView(label, params()); view = label; active = true
                Log.i("GameLingo", "Overlay attached")
            } else { wm.updateViewLayout(existing, params()) }
            when (intent?.action) {
                "editRegion" -> {receiver?.control(org.json.JSONObject().put("type","roi_edit_request"))}
                "move" -> {
                    val place=Placement.from(prefs.getString("position",null))
                    val settings=view?.style ?: org.json.JSONObject()
                    val offset=when(place) { Placement.BOTTOM -> 0; Placement.CENTER -> -(resources.displayMetrics.heightPixels*.42).toInt(); Placement.TOP -> -(resources.displayMetrics.heightPixels*.78).toInt() }
                    settings.put("x",0).put("y",offset)
                    view?.message(org.json.JSONObject().put("type","settings_sync").put("settings",settings))
                    prefs.edit().putString("display_settings",settings.toString()).apply()
                }
                "connect" -> {
                    handler.removeCallbacks(expire); receiver?.stop(); live = true
                    receiver = Receiver(this, { message ->
                        view?.visibility = View.VISIBLE
                        view?.message(message)
                        if(message!=null) Log.i("GameLingo","Applied " + message.optString("type") + " sequence " + message.optLong("seq"))
                    }, ::status)
                    receiver?.start(intent.getStringExtra("host") ?: "", intent.getStringExtra("code") ?: "")
                    status(prefs.getString("status", "جارٍ الاتصال بالمصدر") ?: "جارٍ الاتصال بالمصدر")
                }
                else -> {
                    receiver?.stop(); receiver = null; live = false; handler.removeCallbacks(hide)
                    view?.apply { visibility = View.VISIBLE; message(org.json.JSONObject().put("type","subtitle_preview_show")) }
                    status("معاينة مستمرة · أوقفها من التطبيق")
                    handler.removeCallbacks(expire)
                }
            }
        } catch (e: RuntimeException) { Log.e("GameLingo", "Overlay unavailable", e); stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        receiver?.stop(); receiver = null
        handler.removeCallbacksAndMessages(null)
        view?.let { if (it.isAttachedToWindow) wm.removeViewImmediate(it) }; view = null; active = false
        status("استقبال الترجمة متوقف")
        Log.i("GameLingo", "Overlay service stopped")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
}
