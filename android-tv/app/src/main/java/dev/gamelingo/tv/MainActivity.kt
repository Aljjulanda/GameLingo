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
    private val liveStatus = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "status") refresh()
    }
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
        button("الاتصال بتطبيق Windows") { connectionDialog() }
        val savedHost=prefs.getString("host","") ?: ""
        if(Settings.canDrawOverlays(this) && prefs.contains("token") && Pairing.privateIp(savedHost)) {
            startForegroundService(Intent(this,OverlayService::class.java).setAction("connect")
                .putExtra("host",savedHost).putExtra("code",""))
        }
        val link = intent.data
        if (intent.action == Intent.ACTION_VIEW && link?.scheme == "gamelingo" && link.host == "pair") {
            connectionDialog(link.getQueryParameter("host"), link.getQueryParameter("code"))
        }
    }
    private fun connectionDialog(suggestedHost: String? = null, suggestedCode: String? = null) {
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(22),dp(8),dp(22),0) }
        fun field(hintText: String) = EditText(this).apply {
            hint = hintText; isSingleLine = true
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            textDirection = View.TEXT_DIRECTION_LTR; form.addView(this)
        }
        val ip = field("عنوان الكمبيوتر 192.168.x.x").apply { setText(suggestedHost ?: prefs.getString("host","")) }
        val code = field("رمز الاقتران · اتركه فارغًا بعد الاقتران").apply { setText(suggestedCode ?: "") }
        android.app.AlertDialog.Builder(this).setTitle("GameLingo · Windows").setView(form)
            .setNegativeButton("إلغاء",null).setPositiveButton("اتصال") { _,_ ->
                if (Settings.canDrawOverlays(this)) {
                    startForegroundService(Intent(this,OverlayService::class.java).setAction("connect")
                        .putExtra("host",ip.text.toString().trim()).putExtra("code",code.text.toString().trim()))
                } else status.text = "يلزم إذن الظهور فوق التطبيقات"
            }.show()
    }
    override fun onResume() { super.onResume(); prefs.registerOnSharedPreferenceChangeListener(liveStatus); refresh() }
    override fun onPause() { prefs.unregisterOnSharedPreferenceChangeListener(liveStatus); super.onPause() }
    private fun refresh() {
        val allowed = Settings.canDrawOverlays(this)
        start.isEnabled = allowed
        position.text = "الموضع · " + Placement.from(prefs.getString("position", null)).title
        status.text = if (allowed) (if (OverlayService.active) prefs.getString("status","الإذن مفعّل") else "الإذن مفعّل") else "يلزم السماح بعرض النص فوق التطبيقات"
    }
}
