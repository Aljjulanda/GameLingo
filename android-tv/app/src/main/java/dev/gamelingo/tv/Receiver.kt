package dev.gamelingo.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import okhttp3.*
import org.json.JSONObject
import org.json.JSONArray
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.*

object Pairing {
    fun privateIp(s: String): Boolean {
        if (s.any { it !in "0123456789." }) return false
        val a = s.split(".").map { it.toIntOrNull() ?: return false }
        return a.size == 4 && a.all { it in 0..255 } && (a[0] == 10 ||
            (a[0] == 192 && a[1] == 168) || (a[0] == 172 && a[1] in 16..31))
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("gamelingo-tv", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder("gamelingo-tv", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }
    fun encrypt(s: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        return Base64.encodeToString(c.iv + c.doFinal(s.toByteArray()), Base64.NO_WRAP)
    }
    fun decrypt(s: String): String {
        val data = Base64.decode(s, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0,12)))
        return String(c.doFinal(data.copyOfRange(12,data.size)), Charsets.UTF_8)
    }
}

class Receiver(context: Context, private val render: (JSONObject?) -> Unit, private val status: (String) -> Unit) {
    private val contextWidth = context.resources.displayMetrics.widthPixels
    private val contextHeight = context.resources.displayMetrics.heightPixels
    private val prefs = context.getSharedPreferences("overlay", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private var socket: WebSocket? = null
    private var client: OkHttpClient? = null
    private var pin = ""
    private var address = ""
    private var prefix = ""
    private var epoch = 0
    private var attempts = 0
    private var session = ""
    private var sequence = 0L
    private var serverTime = 0L
    private var syncTime = 0L
    private var observedFingerprint = ""
    private var stage = "TCP"
    private var settingsRevision = -1L
    private var lastFailure = ""
    private var displayAcknowledgement = false
    private var wantedConnection = false
    private val discovery = PinnedDiscovery(context) { host,fingerprint ->
        if(wantedConnection && pin.isEmpty() && prefix==fingerprint && session.isEmpty() && host!=address) {
            main.removeCallbacksAndMessages(null);dispose();address=host
            diagnostic("discovery.found","اكتُشف عنوان جديد للمصدر المقترن؛ جارٍ التحقق الآمن")
            connect()
        }
    }
    fun acknowledge(id: String, renderedTrace: String? = null) {
        if (displayAcknowledgement && session.isNotEmpty()) {
            val ack=JSONObject().put("v",1).put("type","subtitle_ack").put("id",id)
            if(renderedTrace != null && renderedTrace.length <= 1024) ack.put("render_signature",renderedTrace)
            socket?.send(ack.toString())
        }
    }
    private fun diagnostic(code: String, text: String, show: Boolean = true) {
        val line = "${System.currentTimeMillis()} [$code] $text"
        val old = prefs.getString("connection_diagnostics", "") ?: ""
        prefs.edit().putString("connection_diagnostics", (old.lines().filter { it.isNotEmpty() } + line).takeLast(60).joinToString("\n")).apply()
        if (prefs.getBoolean("diagnostics_enabled",false)) Log.i("GameLingoNetwork",line)
        if (show) status(text)
    }

    fun start(host: String, code: String) {
        stop()
        lastFailure = ""
        address = host
        val saved = prefs.getString("host", "") == host && prefs.contains("token")
        if (!Pairing.privateIp(host)) { diagnostic("input.ip", "عنوان IP محلي غير صالح"); return }
        if (code.matches(Regex("(?:[0-9a-fA-F]{12}|[0-9a-fA-F]{64})-[0-9]{6}"))) {
            prefix = code.substringBefore("-").lowercase(); pin = code.substringAfter("-")
        } else if (saved && code.isEmpty()) {
            prefix = prefs.getString("fingerprint", "") ?: ""
        } else { diagnostic("input.code", "أدخل رمز الاقتران كما يظهر على المصدر"); return }
        if (prefix.length !in listOf(12, 64)) { status("بصمة الشهادة غير صالحة"); return }
        wantedConnection = true
        connect()
    }

    private fun connect() {
        val generation = ++epoch
        fun onMain(block: () -> Unit) { main.post { if (generation == epoch) block() } }
        stage = "TCP"; observedFingerprint = ""
        val expected = prefix
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) { throw CertificateException() }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                val cert = chain.firstOrNull() ?: throw CertificateException("Missing certificate")
                cert.checkValidity()
                val fp = MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it) }
                if (!fp.startsWith(expected)) throw CertificateException("Fingerprint mismatch")
                observedFingerprint = fp
            }
        }
        val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), SecureRandom()) }
        val http = OkHttpClient.Builder().sslSocketFactory(tls.socketFactory, trust)
            .eventListener(object : EventListener() {
                override fun secureConnectStart(call: Call) = onMain {
                    stage = "TLS"; diagnostic("tcp.ok", "نجح TCP؛ جارٍ تفاوض TLS")
                }
                override fun secureConnectEnd(call: Call, handshake: Handshake?) = onMain {
                    stage = "WebSocket"; diagnostic("tls.ok", "نجح TLS وتحققت بصمة الشهادة؛ جارٍ ترقية WebSocket")
                }
            })
            .hostnameVerifier { host, _ -> host == address }.pingInterval(6, TimeUnit.SECONDS)
            .followRedirects(false).followSslRedirects(false).connectTimeout(5, TimeUnit.SECONDS).build()
        client = http
        diagnostic("tcp.start", "جارٍ الاتصال بـ $address:38443" + (if (attempts > 0) " · محاولة ${attempts + 1}" else "") + (if (lastFailure.isNotEmpty()) "\nآخر خطأ: $lastFailure" else ""))
        main.postDelayed({
            if (generation == epoch && session.isEmpty()) retry("انتهت مهلة الاتصال عند $stage")
        }, 20000)
        socket = http.newWebSocket(Request.Builder().url("wss://$address:38443/").build(), object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) = onMain {
                stage = "المصادقة"; diagnostic("websocket.ok", "تم إنشاء WebSocket؛ جارٍ الاقتران / المصادقة")
                try {
                    val auth = if (pin.isNotEmpty()) JSONObject().put("type","pair").put("pin",pin)
                        else JSONObject().put("type","hello").put("token", Pairing.decrypt(prefs.getString("token","")!!))
                    ws.send(auth.put("v",1).put("features",JSONArray(listOf("document_v1","speaker_v1","display_ack","menu_v1","roi_edit_v1","persistent_preview_v1"))).toString())
                } catch (_: Exception) { stop(); status("أعد الاقتران من إعدادات GameLingo") }
            }
            override fun onMessage(ws: WebSocket, text: String) = onMain {
                try {
                    require(text.length <= 16384)
                    val m = JSONObject(text); require(m.getInt("v") == 1)
                    when (m.getString("type")) {
                        "paired" -> {
                            require(pin.isNotEmpty())
                            val token = m.getString("token"); require(token.length in 32..128)
                            prefs.edit().putString("host",address).putString("token",Pairing.encrypt(token))
                                .putString("fingerprint",observedFingerprint).apply()
                            pin = ""; prefix = observedFingerprint
                            diagnostic("pair.accepted", "قُبل الاقتران وحُفظ رمز المصادقة بأمان")
                        }
                        "connection_status" -> {
                            session = m.getString("session"); sequence = 0; attempts = 0
                            settingsRevision = -1L; stage = "متصل"
                            displayAcknowledgement = m.optJSONArray("capabilities")?.let { a -> (0 until a.length()).any { a.optString(it)=="subtitle_ack" } } ?: false
                            lastFailure = ""
                            discovery.stop()
                            // Persist a discovered address only after TLS pinning and token authentication.
                            if(pin.isEmpty() && observedFingerprint==prefix) prefs.edit().putString("host",address).apply()
                            serverTime = m.getLong("time_ms"); syncTime = SystemClock.elapsedRealtime()
                            render(null); diagnostic("auth.ok", "متصل · في انتظار الترجمة")
                        }
                        "subtitle_show", "subtitle_update", "subtitle_hide", "subtitle_clear", "subtitle_source_gone", "context_show", "context_present", "context_clear" -> {
                            if (session.isEmpty() || m.optString("session") != session || m.getLong("seq") <= sequence) return@onMain
                            sequence = m.getLong("seq")
                            if (m.getString("type") in listOf("subtitle_clear","subtitle_hide")) { render(m); return@onMain }
                            if(m.getString("type")=="subtitle_source_gone") { render(m); return@onMain }
                            if(m.getString("type").startsWith("context_")) { render(m); return@onMain }
                            val left = m.optLong("expires_at",Long.MAX_VALUE) - (serverTime + SystemClock.elapsedRealtime() - syncTime)
                            if (left <= 0) return@onMain
                            require(m.getString("translated").length <= 2400 && m.getString("target_lang") == "ar")
                            render(m)
                        }
                        "settings_sync", "subtitle_style_update", "subtitle_position_update", "subtitle_timing_update",
                        "subtitle_preview_show", "subtitle_preview_hide" -> {
                            if(m.optString("session")!=session || m.getLong("seq")<=sequence) return@onMain
                            sequence=m.getLong("seq")
                            if(m.has("settings")) {
                                val incoming=m.getJSONObject("settings")
                                val rev=incoming.optLong("revision",0)
                                // Revisions belong to this authenticated session, not the previous Windows source.
                                if(rev<settingsRevision) return@onMain
                                settingsRevision = rev
                                prefs.edit().putString("display_settings",incoming.toString()).putLong("settings_revision",rev).apply()
                                main.postDelayed({
                                    if(generation==epoch) {
                                ws.send(JSONObject().put("v",1).put("type","settings_ack").put("revision",rev)
                                    .put("width_px",contextWidth).put("height_px",contextHeight).put("anchor_x",prefs.getFloat("anchor_x",0f).toDouble()).put("anchor_y",prefs.getFloat("anchor_y",0f).toDouble()).toString())
                                diagnostic("settings.ack", "تمت مزامنة إعدادات العرض", false)
                                    }
                                },180)

                            }
                            render(m)
                        }
                        "heartbeat" -> { serverTime = m.getLong("time_ms"); syncTime = SystemClock.elapsedRealtime() }
                        "menu_snapshot", "menu_clear", "roi_edit_start", "roi_edit_end" -> {
                            if(session.isEmpty() || m.optString("session")!=session || m.getLong("seq")<=sequence) return@onMain
                            sequence=m.getLong("seq"); render(m)
                        }
                        "document_show", "document_hide" -> {
                            if(session.isEmpty() || m.optString("session")!=session || m.getLong("seq")<=sequence) return@onMain
                            sequence=m.getLong("seq")
                            if(m.getString("type")=="document_show") {
                                require(m.getString("translated").length in 1..2400)
                                require(m.getInt("page") in 1..64 && m.getInt("pages") in 1..64 && m.getInt("page")<=m.getInt("pages"))
                            }
                            render(m)
                        }
                        "error" -> { render(null); diagnostic("server.error", "رفض المصدر الطلب") }
                    }
                } catch (_: Exception) { diagnostic("protocol.invalid", "رسالة بروتوكول غير صالحة"); ws.close(1002,"Invalid message") }
            }
            override fun onClosing(ws: WebSocket, code: Int, reason: String) { ws.close(code, null) }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) = onMain {
                if (code == 1008 || code == 1002) { stop(); diagnostic("auth.rejected", "رُفض الاقتران أو البروتوكول؛ تحقق من صلاحية رمز المصدر.") }
                else retry("انقطع الاتصال بعد إغلاق WebSocket · $code")
            }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) = onMain {
                val failure = ConnectionFailure.classify(t,stage,response?.code)
                if (failure.terminal) { stop(); diagnostic(failure.code,failure.text) }
                else { diagnostic(failure.code,failure.text,false); retry(failure.text) }
            }
        })
    }
    fun control(message: JSONObject) {
        if(session.isNotEmpty()) { message.put("v",1).put("session",session); socket?.send(message.toString()) }
    }
    private fun dispose() {
        ++epoch
        socket?.cancel(); socket = null
        client?.dispatcher?.executorService?.shutdown()
        client?.connectionPool?.evictAll(); client = null
        session = ""; sequence = 0; render(null)
        displayAcknowledgement = false
    }
    private fun retry(reason: String) {
        lastFailure = reason
        main.removeCallbacksAndMessages(null)
        dispose(); diagnostic("retry", "$reason · ستتم إعادة المحاولة")
        if(attempts>=1 && pin.isEmpty() && prefix.length==64) discovery.start(prefix)
        val delay = listOf(2000L,4000L,8000L,15000L,30000L)[attempts.coerceIn(0,4)] + (Math.random()*500).toLong(); attempts++
        val generation = epoch
        main.postDelayed({ if (generation == epoch) connect() }, delay)
    }
    fun stop() { wantedConnection=false;discovery.stop();main.removeCallbacksAndMessages(null); dispose(); pin = ""; attempts = 0 }
}

