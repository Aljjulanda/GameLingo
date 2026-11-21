package dev.gamelingo.tv

import android.app.Instrumentation
import android.os.Bundle
import org.json.JSONObject
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.ssl.*

/** Dedicated lab app: no production preferences, TV tokens or PS5 activity. */
class BootstrapRunner: Instrumentation() {
    private var ui=false
    override fun onCreate(arguments:Bundle?) {ui=arguments?.getString("ui")=="true";super.onCreate(arguments);start()}
    override fun onStart() {
        var server:QRPairingServer?=null
        val diagnostics=java.util.concurrent.CopyOnWriteArrayList<String>()
        try {
            val host=requireNotNull(QRPairingServer.localHost())
            var confirmed=0;var connected=0
            val ready=CountDownLatch(1)
            server=QRPairingServer({_,answer->confirmed++;answer(true)},{_,_->connected++;ready.countDown()},{diagnostics.add(it)})
            val qr=JSONObject(server.start(host))
            fun exchange(nonce:String,fingerprint:String=qr.getString("fingerprint")):String {
                val trust=object:X509TrustManager {
                    override fun getAcceptedIssuers():Array<X509Certificate> = emptyArray()
                    override fun checkClientTrusted(c:Array<X509Certificate>,a:String){throw CertificateException()}
                    override fun checkServerTrusted(c:Array<X509Certificate>,a:String) {
                        c[0].checkValidity()
                        val actual=MessageDigest.getInstance("SHA-256").digest(c[0].encoded).joinToString(""){"%02x".format(it)}
                        if(actual!=fingerprint)throw CertificateException("Identity mismatch")
                    }
                }
                val tls=SSLContext.getInstance("TLS").apply{init(null,arrayOf<TrustManager>(trust),SecureRandom())}
                val socket=tls.socketFactory.createSocket() as SSLSocket
                socket.connect(java.net.InetSocketAddress(host,38444),3000);socket.soTimeout=5000
                socket.use {
                    it.startHandshake()
                    val body=JSONObject().put("session",qr.getString("session")).put("nonce",nonce).put("host",host)
                        .put("code","a".repeat(64)+"-123456").put("name","GameLingo lab test").toString().toByteArray()
                    it.outputStream.write("POST /pair HTTP/1.1\r\nHost: $host\r\nContent-Length: ${body.size}\r\nContent-Type: application/json\r\n\r\n".toByteArray());it.outputStream.write(body);it.outputStream.flush()
                    return it.inputStream.bufferedReader().readText()
                }
            }
            var rejected=false
            try {exchange(qr.getString("nonce"),"0".repeat(64))}catch(_:Exception){rejected=true}
            check(rejected && confirmed==0 && connected==0)
            try {exchange(android.util.Base64.encodeToString(ByteArray(32),android.util.Base64.NO_WRAP))}catch(_:Exception){}
            check(confirmed==0 && connected==0)
            val response=exchange(qr.getString("nonce"));check(response.contains("\"accepted\":true"))
            check(ready.await(3,TimeUnit.SECONDS));check(confirmed==1 && connected==1)
            try {exchange(qr.getString("nonce"))}catch(_:Exception){}
            check(confirmed==1 && connected==1)
            server.stop();server=null
            if(ui) testOverlayKeys()
            finish(0,Bundle().apply{putString("stream","PASS: native AndroidKeyStore certificate/TLS, wrong fingerprint rejection, wrong nonce rejection, one-time acceptance, replay rejection"+(if(ui) ", focusable overlay DPAD move and save" else "")+"; no production pairing changes")})
        } catch(error:Throwable) {finish(1,Bundle().apply{putString("stream","FAIL: "+error.javaClass.simpleName+": "+error.message?.take(120)+" server="+diagnostics.joinToString(" | "))})}
        finally {server?.stop()}
    }
    private fun testOverlayKeys() {
        check(android.provider.Settings.canDrawOverlays(targetContext))
        val window=targetContext.getSystemService(android.content.Context.WINDOW_SERVICE) as android.view.WindowManager
        var view:SubtitleCanvas?=null
        val result=CountDownLatch(1);var saved:JSONObject?=null
        try {
            runOnMainSync {
                view=SubtitleCanvas(targetContext){}.apply {
                    isFocusableInTouchMode=true
                    onControl={saved=it;result.countDown()}
                }
                val params=android.view.WindowManager.LayoutParams(-1,-1,android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,android.graphics.PixelFormat.TRANSLUCENT)
                window.addView(view,params)
                view!!.message(JSONObject().put("type","roi_edit_start").put("ticket","native-tv-lab").put("box",JSONObject().put("x",.1).put("y",.6).put("w",.7).put("h",.2)))
                check(view!!.requestFocus())
            }
            waitForIdleSync();Thread.sleep(700)
            for(code in listOf(android.view.KeyEvent.KEYCODE_DPAD_CENTER,android.view.KeyEvent.KEYCODE_DPAD_RIGHT,android.view.KeyEvent.KEYCODE_DPAD_DOWN,
                android.view.KeyEvent.KEYCODE_DPAD_CENTER,android.view.KeyEvent.KEYCODE_DPAD_RIGHT,android.view.KeyEvent.KEYCODE_DPAD_RIGHT,
                android.view.KeyEvent.KEYCODE_DPAD_RIGHT,android.view.KeyEvent.KEYCODE_DPAD_CENTER)) {sendKeyDownUpSync(code);Thread.sleep(80)}
            check(result.await(3,TimeUnit.SECONDS))
            val value=requireNotNull(saved);check(value.getBoolean("save") && value.getString("ticket")=="native-tv-lab")
            check(kotlin.math.abs(value.getJSONObject("box").getDouble("x")-.105)<.0001)
            check(kotlin.math.abs(value.getJSONObject("box").getDouble("y")-.605)<.0001)
        } finally {runOnMainSync{view?.let{if(it.isAttachedToWindow)window.removeViewImmediate(it)}}}
    }
}
