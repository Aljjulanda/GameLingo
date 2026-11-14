package dev.gamelingo.tv

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.Bundle
import android.os.SystemClock
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Runs the real Receiver/AndroidKeyStore/OkHttp against a LAN Windows fixture.
 * Isolated preferences: never changes the user's saved host, token or styling.
 * Input code is a newly generated fixture secret; never included in output. */
class NetworkRunner : Instrumentation() {
    private lateinit var inputs: Bundle
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); inputs = arguments ?: Bundle(); start() }
    override fun onStart() {
        val output = Bundle()
        var resultCode = Activity.RESULT_CANCELED
        var receiver: Receiver? = null
        val prefs = targetContext.getSharedPreferences("network_test_fixture",Context.MODE_PRIVATE)
        val isolated = object : ContextWrapper(targetContext) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                if (name == "overlay") prefs else super.getSharedPreferences(name,mode)
        }
        try {
            val host = checkNotNull(inputs.getString("host"))
            val code = checkNotNull(inputs.getString("code"))
            val settings = CountDownLatch(1)
            val connected = CountDownLatch(1)
            val reconnect = CountDownLatch(1)
            val discovered = CountDownLatch(1)
            val documentFirst = CountDownLatch(1)
            val documentNext = CountDownLatch(1)
            val documentClosed = CountDownLatch(1)
            val afterDocument = CountDownLatch(1)
            val documents = inputs.getString("documents") == "true"
            val discovery = inputs.getString("discovery") == "true"
            runOnMainSync {
                prefs.edit().clear().putString("host","192.168.255.254")
                    .putString("token",Pairing.encrypt("stale-windows-fixture-token-not-used"))
                    .putString("fingerprint","0".repeat(64)).putLong("settings_revision",999999).commit()
                receiver = Receiver(isolated, { message ->
                    if (message?.optString("type") == "settings_sync") settings.countDown()
                    when(message?.optString("type")) {
                        "document_show" -> if(message.optInt("page")==1) documentFirst.countDown() else if(message.optInt("page")==2) documentNext.countDown()
                        "document_hide" -> documentClosed.countDown()
                        "subtitle_show" -> if(message.optString("id")=="after-document") {
                            receiver?.acknowledge("after-document") // Must be withheld for legacy Windows.
                            afterDocument.countDown()
                        }
                    }
                }, { text -> if (text.startsWith("متصل")) connected.countDown() })
                receiver!!.start(host,code)
            }
            check(connected.await(12,TimeUnit.SECONDS)) { "LAN pairing failed" }
            check(settings.await(5,TimeUnit.SECONDS)) { "New source settings were ignored" }
            check(prefs.getLong("settings_revision",0)==1L) { "Stale Windows revision was not replaced" }
            check(prefs.getString("host","")==host) { "New pairing host not saved" }
            val encrypted = checkNotNull(prefs.getString("token",null))
            check(Pairing.decrypt(encrypted).length in 32..128) { "Token encryption round trip failed" }
            if(documents) {
                check(documentFirst.await(8,TimeUnit.SECONDS)) { "First document page missing" }
                check(documentNext.await(8,TimeUnit.SECONDS)) { "Next document page missing" }
                check(documentClosed.await(8,TimeUnit.SECONDS)) { "Document close missing" }
                check(afterDocument.await(8,TimeUnit.SECONDS)) { "Dialogue did not resume" }
            }
            SystemClock.sleep(7000) // Real Android OkHttp RFC6455 ping/pong.
            check(!(prefs.getString("connection_diagnostics","") ?: "").contains("[retry]")) { "Legacy server connection unexpectedly retried" }
            runOnMainSync { receiver!!.stop() }
            SystemClock.sleep(400)
            runOnMainSync {
                receiver = Receiver(isolated, {}, { text -> if (text.startsWith("متصل")) reconnect.countDown() })
                receiver!!.start(host,"")
            }
            check(reconnect.await(12,TimeUnit.SECONDS)) { "Saved token reconnect failed" }
            if(discovery) {
                runOnMainSync { receiver!!.stop() }
                SystemClock.sleep(400)
                val fingerprint=prefs.getString("fingerprint","")
                val obsolete="192.168.255.254"
                runOnMainSync {
                    prefs.edit().putString("host",obsolete).commit()
                    receiver=Receiver(isolated,{}, {text -> if(text.startsWith("متصل")) discovered.countDown()})
                    receiver!!.start(obsolete,"")
                }
                check(discovered.await(40,TimeUnit.SECONDS)) { "Pinned discovery recovery timed out" }
                check(prefs.getString("host","")==host) { "Discovered host not authenticated and saved" }
                check(prefs.getString("fingerprint","")==fingerprint) { "Discovery changed the full saved TLS pin" }
                check(prefs.getString("token","")==encrypted) { "Discovery replaced the saved authentication token" }
                check((prefs.getString("connection_diagnostics","") ?: "").contains("[discovery.found]")) { "Recovery did not use discovery" }
            }
            val lines = prefs.getString("connection_diagnostics","") ?: ""
            check(!lines.contains(code) && !lines.contains(Pairing.decrypt(encrypted))) { "Secret in diagnostics" }
            output.putString("result","PASS: physical Android LAN TLS/pinning, encrypted token, source/revision replacement, settings, ping/pong, saved-token reconnect" +
                (if(documents) ", document pages/close and resumed dialogue" else "") + (if(discovery) ", obsolete-host recovery through mDNS preserving full pin/token" else ""))
            resultCode = Activity.RESULT_OK
        } catch (_: Throwable) {
            // Only fixed states, not arguments or throwable contents.
            output.putString("error","Network fixture failed; inspect sanitized connection stages")
            output.putString("stages",prefs.getString("connection_diagnostics",""))
        } finally {
            runOnMainSync { receiver?.stop(); prefs.edit().clear().commit() }
        }
        // finish() terminates the instrumented process. Clean fixtures before it.
        finish(resultCode,output)
    }
}
