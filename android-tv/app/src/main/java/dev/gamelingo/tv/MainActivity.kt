package dev.gamelingo.tv

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.*

class MainActivity : Activity() {
    private val prefs by lazy { getSharedPreferences("overlay", MODE_PRIVATE) }
    private lateinit var status: TextView
    private lateinit var position: Button
    private lateinit var start: Button
    private lateinit var panel: LinearLayout
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun button(title: String, action: () -> Unit) = Button(this).apply {
        text = title
        setOnClickListener { action() }
        panel.addView(this, LinearLayout.LayoutParams(dp(370), -2))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(34), dp(20), dp(34), dp(20))
            setBackgroundColor(0xff102529.toInt())
        }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(panel) }
        setContentView(scroll)
        panel.addView(TextView(this).apply { text = "GameLingo TV"; textSize = 34f; gravity = Gravity.CENTER })
        status = TextView(this).apply { textSize = 18f; gravity = Gravity.CENTER; panel.addView(this) }
        button("إذن الظهور فوق التطبيقات") {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + packageName)))
            } catch (_: ActivityNotFoundException) { status.text = "افتح إعدادات التطبيقات ← وصول خاص ← الظهور فوق التطبيقات." }
        }
        position = button("") {
            val place = Placement.from(prefs.getString("position", null)).next()
            prefs.edit().putString("position", place.name).apply()
            if (OverlayService.active) startService(Intent(this, OverlayService::class.java).setAction("move"))
            refresh()
        }
        start = button("عرض نص الاختبار لمدة ١٠ دقائق") {
            if (Settings.canDrawOverlays(this)) {
                startForegroundService(Intent(this, OverlayService::class.java))
                status.text = "اختر مدخل PlayStation بالريموت وتحقق من ظهور النص."
            }
        }
        button("إخفاء النص وإيقاف الخدمة") { stopService(Intent(this, OverlayService::class.java)); refresh() }
    }
    override fun onResume() { super.onResume(); refresh() }
    private fun refresh() {
        val allowed = Settings.canDrawOverlays(this)
        start.isEnabled = allowed
        position.text = "الموضع · " + Placement.from(prefs.getString("position", null)).title
        status.text = if (allowed) "الإذن مفعّل" else "يلزم السماح بعرض النص فوق التطبيقات"
    }
}
