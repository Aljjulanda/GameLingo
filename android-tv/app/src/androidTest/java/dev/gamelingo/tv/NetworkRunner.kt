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
            runOnMainSync {
                prefs.edit().clear().putString("host","192.168.255.254")
                    .putString("token",Pairing.encrypt("stale-windows-fixture-token-not-used"))
                    .putString("fingerprint","0".repeat(64)).putLong("settings_revision",999999).commit()
                receiver = Receiver(isolated, { message ->
                    if (message?.optString("type") == "settings_sync") settings.countDown()
                }, { text -> if (text.startsWith("متصل")) connected.countDown() })
                receiver!!.start(host,code)
            }
            check(connected.await(12,TimeUnit.SECONDS)) { "LAN pairing failed" }
            check(settings.await(5,TimeUnit.SECONDS)) { "New source settings were ignored" }
            check(prefs.getLong("settings_revision",0)==1L) { "Stale Windows revision was not replaced" }
            check(prefs.getString("host","")==host) { "New pairing host not saved" }
            val encrypted = checkNotNull(prefs.getString("token",null))
            check(Pairing.decrypt(encrypted).length in 32..128) { "Token encryption round trip failed" }
            SystemClock.sleep(7000) // Real Android OkHttp RFC6455 ping/pong.
            runOnMainSync { receiver!!.stop() }
            SystemClock.sleep(400)
            runOnMainSync {
                receiver = Receiver(isolated, {}, { text -> if (text.startsWith("متصل")) reconnect.countDown() })
                receiver!!.start(host,"")
            }
            check(reconnect.await(12,TimeUnit.SECONDS)) { "Saved token reconnect failed" }
            val lines = prefs.getString("connection_diagnostics","") ?: ""
            check(!lines.contains(code) && !lines.contains(Pairing.decrypt(encrypted))) { "Secret in diagnostics" }
            output.putString("result","PASS: physical Android LAN TLS/pinning, pairing, encrypted token, source/revision replacement, settings, ping/pong and saved-token reconnect")
            finish(Activity.RESULT_OK,output)
        } catch (_: Throwable) {
            // Only fixed states, not arguments or throwable contents.
            output.putString("error","Network fixture failed; inspect sanitized connection stages")
            output.putString("stages",prefs.getString("connection_diagnostics",""))
            finish(Activity.RESULT_CANCELED,output)
        } finally {
            runOnMainSync { receiver?.stop(); prefs.edit().clear().commit() }
        }
    }
}
