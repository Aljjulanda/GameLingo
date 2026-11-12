package dev.gamelingo.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import okhttp3.*
import org.json.JSONObject
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

    fun start(host: String, code: String) {
        stop()
        address = host
        val saved = prefs.getString("host", "") == host && prefs.contains("token")
        if (!Pairing.privateIp(host)) { status("عنوان الكمبيوتر غير صالح"); return }
        if (code.matches(Regex("[0-9a-fA-F]{12}-[0-9]{6}"))) {
            prefix = code.substringBefore("-").lowercase(); pin = code.substringAfter("-")
        } else if (saved && code.isEmpty()) {
            prefix = prefs.getString("fingerprint", "") ?: ""
        } else { status("أدخل رمز الاقتران كما يظهر على الكمبيوتر"); return }
        if (prefix.length !in listOf(12, 64)) { status("بصمة الشهادة غير صالحة"); return }
        connect()
    }

    private fun connect() {
        val generation = ++epoch
        fun onMain(block: () -> Unit) { main.post { if (generation == epoch) block() } }
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
            .hostnameVerifier { host, _ -> host == address }.pingInterval(6, TimeUnit.SECONDS)
            .followRedirects(false).followSslRedirects(false).connectTimeout(5, TimeUnit.SECONDS).build()
        client = http
        status("جارٍ الاتصال بالكمبيوتر…")
        socket = http.newWebSocket(Request.Builder().url("wss://$address:38443/").build(), object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) = onMain {
                try {
                    val auth = if (pin.isNotEmpty()) JSONObject().put("type","pair").put("pin",pin)
                        else JSONObject().put("type","hello").put("token", Pairing.decrypt(prefs.getString("token","")!!))
                    ws.send(auth.put("v",1).toString())
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
                        }
                        "connection_status" -> {
                            session = m.getString("session"); sequence = 0; attempts = 0
                            serverTime = m.getLong("time_ms"); syncTime = SystemClock.elapsedRealtime()
                            render(null); status("متصل · في انتظار الترجمة")
                        }
                        "subtitle_show", "subtitle_update", "subtitle_hide", "subtitle_clear", "subtitle_source_gone", "context_show", "context_present", "context_clear" -> {
                            if (session.isEmpty() || m.optString("session") != session || m.getLong("seq") <= sequence) return@onMain
                            sequence = m.getLong("seq")
                            if (m.getString("type") in listOf("subtitle_clear","subtitle_hide")) { render(null); return@onMain }
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
                                if(rev<prefs.getLong("settings_revision",0)) return@onMain
                                prefs.edit().putString("display_settings",incoming.toString()).putLong("settings_revision",rev).apply()
                                main.postDelayed({
                                    if(generation==epoch) {
                                ws.send(JSONObject().put("v",1).put("type","settings_ack").put("revision",rev)
                                    .put("width_px",contextWidth).put("height_px",contextHeight).put("anchor_x",prefs.getFloat("anchor_x",0f).toDouble()).put("anchor_y",prefs.getFloat("anchor_y",0f).toDouble()).toString())
                                    }
                                },180)

                            }
                            render(m)
                        }
                        "heartbeat" -> { serverTime = m.getLong("time_ms"); syncTime = SystemClock.elapsedRealtime() }
                        "error" -> { render(null); status("خطأ من الكمبيوتر") }
                    }
                } catch (_: Exception) { ws.close(1002,"Invalid message") }
            }
            override fun onClosing(ws: WebSocket, code: Int, reason: String) { ws.close(code, null) }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) = onMain {
                if (code == 1008 || code == 1002) { stop(); status("رُفض الاقتران. راجع الرمز على الكمبيوتر.") }
                else retry()
            }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) = onMain {
                if (t is SSLHandshakeException || t is SSLPeerUnverifiedException) { stop(); status("تعذر التحقق من شهادة الكمبيوتر. راجع الرمز.") }
                else retry()
            }
        })
    }
    private fun dispose() {
        ++epoch
        socket?.cancel(); socket = null
        client?.dispatcher?.executorService?.shutdown()
        client?.connectionPool?.evictAll(); client = null
        session = ""; sequence = 0; render(null)
    }
    private fun retry() {
        dispose(); status("الاتصال منقطع · ستتم إعادة المحاولة")
        val delay = (1000L shl attempts.coerceAtMost(4)); attempts++
        main.postDelayed({ connect() }, delay)
    }
    fun stop() { main.removeCallbacksAndMessages(null); dispose(); pin = ""; attempts = 0 }
}

