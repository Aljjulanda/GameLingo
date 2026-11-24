package dev.gamelingo.tv

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.*

class MainActivity : Activity() {
    private enum class Page(val title: String, val viewId: Int) {
        HOME("الرئيسية", R.id.tv_nav_home), CONNECTION("الاتصال", R.id.tv_nav_connection),
        APPEARANCE("المظهر", R.id.tv_nav_appearance), HELP("المساعدة", R.id.tv_nav_help)
    }
    private val prefs by lazy { getSharedPreferences("overlay", MODE_PRIVATE) }
    private lateinit var status: TextView
    private lateinit var detail: TextView
    private lateinit var panel: LinearLayout
    private var page = Page.HOME
    private var primary: Button? = null
    private var position: Button? = null
    private var reconnect: Button? = null
    private var permissionAction: Button? = null
    private var preview: Button? = null
    private var endPreview: Button? = null
    private var region: Button? = null
    private var savedSource: TextView? = null
    private var connectionDetail: TextView? = null
    private val navigation = mutableListOf<Button>()
    private var qrServer: QRPairingServer? = null
    private val liveStatus = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key in setOf("status", "host", "token", "position")) refresh()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun shape(color: Int, border: Boolean = false) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(12).toFloat()
        if (border) setStroke(dp(3), Color.WHITE)
    }
    private fun style(button: Button) = button.apply {
        isAllCaps = false; textSize = 26f; minHeight = dp(68)
        setTextColor(Color.WHITE); setPadding(dp(18), dp(12), dp(18), dp(12))
        isFocusable = true; isFocusableInTouchMode = true
        backgroundTintList = null
        background = StateListDrawable().apply {
            addState(intArrayOf(-android.R.attr.state_enabled), shape(0xff283b40.toInt()))
            addState(intArrayOf(android.R.attr.state_focused), shape(0xff006d77.toInt(), true))
            addState(intArrayOf(android.R.attr.state_pressed), shape(0xff006d77.toInt(), true))
            addState(intArrayOf(android.R.attr.state_selected), shape(0xff31585f.toInt()))
            addState(intArrayOf(), shape(0xff214047.toInt()))
        }
        setOnFocusChangeListener { _, focused -> alpha = if (isEnabled || focused) 1f else .5f }
    }
    private fun text(value: String, heading: Boolean = false): TextView = TextView(this).apply {
        text = value; textSize = if (heading) 28f else 22f
        setTextColor(if (heading) Color.WHITE else 0xffc5dadd.toInt())
        gravity = Gravity.START; setPadding(dp(4), dp(10), dp(4), dp(10))
        if (heading) setTypeface(typeface, Typeface.BOLD)
        panel.addView(this, LinearLayout.LayoutParams(-1, -2))
    }
    private fun button(title: String, viewId: Int = View.NO_ID, action: () -> Unit): Button = style(Button(this)).apply {
        text = title; id = if (viewId == View.NO_ID) View.generateViewId() else viewId; setOnClickListener { action() }
        panel.addView(this, LinearLayout.LayoutParams(-1, -2).apply { setMargins(0, dp(6), 0, dp(6)) })
    }
    private fun paired() = prefs.contains("token") && Pairing.privateIp(prefs.getString("host", "") ?: "")
    private fun homeState() = TvHomeState.describe(Settings.canDrawOverlays(this), paired(), OverlayService.active,
        OverlayService.connected, OverlayService.connecting, OverlayService.previewing)
    private fun connectSaved() {
        if (!Settings.canDrawOverlays(this)) { permission(); return }
        if (!paired()) { showPage(Page.CONNECTION); return }
        startForegroundService(Intent(this, OverlayService::class.java).setAction("connect")
            .putExtra("host", prefs.getString("host", "")).putExtra("code", ""))
    }
    private fun permission() {
        try { startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + packageName))) }
        catch (_: ActivityNotFoundException) { detail.text = "افتح إعدادات التطبيقات ← وصول خاص ← الظهور فوق التطبيقات." }
    }
    private fun stopReception() { stopService(Intent(this, OverlayService::class.java)); refresh() }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        page = Page.values().firstOrNull { it.name == savedInstanceState?.getString("page") } ?: Page.HOME
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(28), dp(20), dp(28), dp(20))
        }
        val outer = FrameLayout(this).apply {
            setBackgroundColor(0xff102529.toInt())
            addView(root, FrameLayout.LayoutParams(minOf(resources.displayMetrics.widthPixels, dp(1200)), -1, Gravity.CENTER))
        }
        root.addView(TextView(this).apply {
            text = "GameLingo TV · ${packageManager.getPackageInfo(packageName, 0).versionName}"; textSize = 27f; setTextColor(Color.WHITE)
            gravity = Gravity.CENTER; setPadding(0, 0, 0, dp(12))
        })
        val tabs = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for (destination in Page.values()) {
            val tab = style(Button(this)).apply {
                id = destination.viewId; text = destination.title; setOnClickListener { showPage(destination) }
            }
            navigation.add(tab)
            tabs.addView(tab, LinearLayout.LayoutParams(0, -2, 1f).apply { setMargins(dp(3), 0, dp(3), 0) })
        }
        navigation.forEachIndexed { index, tab ->
            tab.nextFocusLeftId = navigation[(index + 1).coerceAtMost(navigation.lastIndex)].id
            tab.nextFocusRightId = navigation[(index - 1).coerceAtLeast(0)].id
        }
        root.addView(tabs)
        status = TextView(this).apply {
            id = R.id.tv_status; textSize = 32f; setTextColor(Color.WHITE); gravity = Gravity.START
            setTypeface(typeface, Typeface.BOLD); setPadding(dp(4), dp(18), dp(4), dp(6))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        detail = TextView(this).apply { id = R.id.tv_detail; textSize = 22f; setTextColor(0xffc5dadd.toInt()); setPadding(dp(4), 0, dp(4), dp(12)) }
        root.addView(status); root.addView(detail)
        panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(ScrollView(this).apply { isFillViewport = true; addView(panel) }, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(outer); showPage(page)
        if (page == Page.HOME) primary?.requestFocus()
        // Preserve the existing saved-source reconnect on opening the TV app.
        if (!OverlayService.active && Settings.canDrawOverlays(this) && paired()) connectSaved()
        val link = intent.data
        if (intent.action == Intent.ACTION_VIEW && link?.scheme == "gamelingo" && link.host == "pair") {
            showPage(Page.CONNECTION); connectionDialog(link.getQueryParameter("host"), link.getQueryParameter("code"))
        }
    }
    private fun showPage(destination: Page) {
        page = destination; panel.removeAllViews()
        primary = null; position = null; reconnect = null; preview = null; endPreview = null; region = null
        permissionAction = null
        savedSource = null; connectionDetail = null
        navigation.forEach { it.isSelected = it.id == page.viewId; it.contentDescription = if (it.isSelected) "${page.title}، القسم الحالي" else it.text }
        when (page) {
            Page.HOME -> {
                primary = button("", R.id.tv_primary) {
                    when (homeState().action) {
                        TvHomeAction.PERMISSION -> permission()
                        TvHomeAction.PAIR -> showPage(Page.CONNECTION)
                        TvHomeAction.CONNECT -> connectSaved()
                        TvHomeAction.STOP -> stopReception()
                    }
                }
                text("الترجمة تبدأ من المصدر", true)
                text("هذا التطبيق يستقبل العربية ويعرضها. لا يغيّر صورة اللعب الأصلية عبر HDMI.")
                text("بعد الاتصال اختر مدخل PlayStation بالريموت. لا يلزم إبقاء شاشة إعدادات GameLingo TV مفتوحة.")
            }
            Page.CONNECTION -> {
                text("مصدر الترجمة", true)
                savedSource = text("").apply { id = R.id.tv_saved_source }
                reconnect = button("الاتصال بالمصدر المحفوظ") { connectSaved() }
                permissionAction = button("السماح بالظهور فوق التطبيقات") { permission() }
                button("اقتران الآيفون عبر QR مؤقت") { qrPairing() }
                button("إدخال العنوان ورمز الاقتران") { connectionDialog() }
                text("بيانات الاقتران المحفوظة تبقى بعد التحديث؛ لا تحتاج رمزًا جديدًا عند الاتصال بالمصدر نفسه.")
                connectionDetail = text("")
            }
            Page.APPEARANCE -> {
                text("معاينة مظهر العربية", true)
                text("اضبط الخط واللون ومحاذاة القوائم من الآيفون أو Windows. تصل الإعدادات إلى التلفزيون عند الاتصال.")
                preview = button("تشغيل معاينة دون اتصال") {
                    if (Settings.canDrawOverlays(this)) startForegroundService(Intent(this, OverlayService::class.java))
                }
                text("المعاينة عينة نص مستمرة وتوقف استقبال المصدر حتى تبدأ الاستقبال من الرئيسية.")
                endPreview = button("إيقاف المعاينة") { stopReception() }
                position = button("", R.id.tv_position) {
                    val place = Placement.from(prefs.getString("position", null)).next()
                    prefs.edit().putString("position", place.name).apply()
                    if (OverlayService.active) startService(Intent(this, OverlayService::class.java).setAction("move"))
                    refresh()
                }
                region = button("تحديد منطقة الحوار بالريموت") {
                    if (OverlayService.connected) startService(Intent(this, OverlayService::class.java).setAction("editRegion"))
                }
                text("تحديد منطقة الحوار يحتاج مصدرًا متصلًا يدعم المحرر. في المحرر: الأسهم للتحريك والقياس، OK للخيارات، وBack للإلغاء.")
            }
            Page.HELP -> {
                text("إذا لم تظهر العربية", true)
                text("تأكد من إذن الظهور فوق التطبيقات، واتصال المصدر، وبدء الترجمة عليه. افتح قائمة اللعبة ثم اطلب «ترجمة القائمة الحالية» من الآيفون؛ أغلق القراءة عند العودة للحوار.")
                text("القوائم وقراءة المستندات تصل من المصدر. لا يتطلب تحديث التلفزيون إعادة الاقتران أو شراء نموذج.")
                button("تشخيص الاتصال") { diagnostics() }
                text("سجل ADB اختياري. لا يتغير اختياره عند فتح هذه الصفحة، ولا تتضمن صفحة التشخيص رموز الاقتران.")
            }
        }
        refresh()
    }
    private fun diagnostics() {
        val log = TextView(this).apply {
            text = prefs.getString("connection_diagnostics", "لم تُسجل محاولة اتصال بعد")
            textSize = 17f; setPadding(dp(16), dp(12), dp(16), dp(12)); setTextIsSelectable(true)
        }
        AlertDialog.Builder(this).setTitle("تشخيص الاتصال · بلا رموز سرية")
            .setView(ScrollView(this).apply { addView(log) }).setPositiveButton("إغلاق", null)
            .setNeutralButton(if (prefs.getBoolean("diagnostics_enabled", false)) "إيقاف سجل ADB" else "تفعيل سجل ADB") { _, _ ->
                prefs.edit().putBoolean("diagnostics_enabled", !prefs.getBoolean("diagnostics_enabled", false)).apply()
            }.show()
    }
    private fun connectionDialog(suggestedHost: String? = null, suggestedCode: String? = null) {
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; layoutDirection = View.LAYOUT_DIRECTION_RTL; setPadding(dp(22), dp(8), dp(22), 0) }
        fun field(hintText: String) = EditText(this).apply {
            hint = hintText; isSingleLine = true; minHeight = dp(56)
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            textDirection = View.TEXT_DIRECTION_LTR; form.addView(this)
        }
        val ip = field("عنوان الآيفون أو Windows · 192.168.x.x").apply { setText(suggestedHost ?: prefs.getString("host", "")) }
        val code = field("رمز الاقتران · فارغ للمصدر المحفوظ").apply { setText(suggestedCode ?: "") }
        val dialog = AlertDialog.Builder(this).setTitle("الاتصال بمصدر الترجمة").setView(form)
            .setNegativeButton("إلغاء", null).setPositiveButton("اتصال", null).create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val host = ip.text.toString().trim(); val pin = code.text.toString().trim()
                if (!Pairing.privateIp(host)) { ip.error = "أدخل عنوان IP محليًا صحيحًا"; return@setOnClickListener }
                if (pin.isEmpty() && !(paired() && host == prefs.getString("host", ""))) {
                    code.error = "أدخل رمز الاقتران الظاهر على المصدر"; return@setOnClickListener
                }
                if (!Settings.canDrawOverlays(this)) { permission(); return@setOnClickListener }
                startForegroundService(Intent(this, OverlayService::class.java).setAction("connect").putExtra("host", host).putExtra("code", pin))
                dialog.dismiss()
            }
        }
        dialog.show()
    }
    private fun qrPairing() {
        qrServer?.stop()
        val host=QRPairingServer.localHost()
        if(host==null) {status.text="اتصل بشبكة محلية أولًا";return}
        if(!Settings.canDrawOverlays(this)) {status.text="فعّل إذن الظهور فوق التطبيقات أولًا";return}
        val dialog=android.app.AlertDialog.Builder(this).setTitle("QR لمرة واحدة · دقيقتان").setNegativeButton("إلغاء",null).create()
        val server=QRPairingServer({ body,answer -> runOnUiThread {
            if(isFinishing) {answer(false);return@runOnUiThread}
            val device=body.optString("name","iPhone").take(80)
            val fingerprint=body.optString("code").substringBefore('-').takeLast(12)
            android.app.AlertDialog.Builder(this).setTitle("تأكيد هوية الآيفون")
                .setMessage("هل تقرن $device؟\nبصمة المصدر: $fingerprint\nقارنها بما يظهر على الآيفون.")
                .setPositiveButton("اقتران") {_,_->answer(true)}.setNegativeButton("رفض") {_,_->answer(false)}.setOnCancelListener{answer(false)}.show()
        } },{ phone,code -> runOnUiThread {
            startForegroundService(Intent(this,OverlayService::class.java).setAction("connect").putExtra("host",phone).putExtra("code",code))
            dialog.dismiss()
        } })
        qrServer=server
        Thread {
            try {
                val payload=server.start(host)
                val matrix=com.google.zxing.MultiFormatWriter().encode(payload,com.google.zxing.BarcodeFormat.QR_CODE,640,640)
                val pixels=IntArray(640*640){ index->if(matrix[index%640,index/640]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
                val bitmap=android.graphics.Bitmap.createBitmap(pixels,640,640,android.graphics.Bitmap.Config.ARGB_8888)
                runOnUiThread {
                    if(isFinishing || qrServer!==server) {server.stop();return@runOnUiThread}
                    val form=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER}
                    form.addView(ImageView(this).apply{setImageBitmap(bitmap)},LinearLayout.LayoutParams(dp(320),dp(320)))
                    form.addView(TextView(this).apply{text="امسح من GameLingo على iPhone. تأكد من اسم التلفزيون ثم وافق على الجهاز هنا. لا تُشارك صورة الرمز.";textSize=17f;setPadding(18,8,18,8)})
                    dialog.setView(form);dialog.setOnDismissListener{server.stop();if(qrServer===server)qrServer=null};dialog.show()
                    android.os.Handler(mainLooper).postDelayed({if(qrServer===server){dialog.dismiss();status.text="انتهت صلاحية QR؛ أنشئ رمزًا جديدًا"}},120000)
                }
            } catch(_:Exception) {server.stop();runOnUiThread{status.text="تعذر إنشاء جلسة QR المحلية؛ استخدم الإدخال اليدوي"}}
        }.start()
    }
    override fun onSaveInstanceState(outState: Bundle) { outState.putString("page", page.name); super.onSaveInstanceState(outState) }
    override fun onBackPressed() {
        if (page != Page.HOME) { showPage(Page.HOME); primary?.requestFocus() } else super.onBackPressed()
    }
    override fun onDestroy() { qrServer?.stop(); qrServer = null; super.onDestroy() }
    override fun onResume() { super.onResume(); prefs.registerOnSharedPreferenceChangeListener(liveStatus); refresh() }
    override fun onPause() { prefs.unregisterOnSharedPreferenceChangeListener(liveStatus); super.onPause() }
    private fun refresh() {
        val state = homeState(); val allowed = Settings.canDrawOverlays(this)
        status.text = state.title; detail.text = state.detail; primary?.text = state.button
        position?.text = "موضع العربية · " + Placement.from(prefs.getString("position", null)).title
        reconnect?.isEnabled = allowed && paired()
        permissionAction?.visibility = if (allowed) View.GONE else View.VISIBLE
        preview?.isEnabled = allowed; endPreview?.isEnabled = OverlayService.previewing
        region?.isEnabled = OverlayService.connected
        savedSource?.text = if (paired()) "المصدر محفوظ · ${prefs.getString("host", "")}" else "لا يوجد مصدر محفوظ بعد"
        connectionDetail?.text = if (OverlayService.active) prefs.getString("status", "") else "الاستقبال متوقف؛ ابدأه من الرئيسية أو اختر المصدر هنا."
        val first = (0 until panel.childCount).map { panel.getChildAt(it) }
            .firstOrNull { it is Button && it.isEnabled && it.visibility == View.VISIBLE }
        if (first != null) {
            first.nextFocusUpId = page.viewId
            navigation.forEach { it.nextFocusDownId = first.id }
        }
    }
}
