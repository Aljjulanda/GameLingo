package dev.gamelingo.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper

internal object DiscoveryCandidate {
    fun matches(fingerprint: String, name: String): Boolean =
        fingerprint.matches(Regex("[0-9a-f]{64}")) &&
            name.matches(Regex("GameLingo-${fingerprint.take(12)}(?: \\([0-9]+\\))?"))
}

/** A public mDNS hint never replaces the full saved TLS pin or token. */
internal class PinnedDiscovery(context: Context, private val found: (String,String)->Unit) {
    private val manager=context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val main=Handler(Looper.getMainLooper())
    private var listener:NsdManager.DiscoveryListener?=null
    private var epoch=0
    private var resolving=false
    fun start(fingerprint:String) {
        if(listener!=null || !fingerprint.matches(Regex("[0-9a-f]{64}"))) return
        val generation=++epoch
        val callback=object:NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type:String) {}
            override fun onDiscoveryStopped(type:String) {}
            override fun onStartDiscoveryFailed(type:String,error:Int) {main.post {if(generation==epoch) stop()}}
            override fun onStopDiscoveryFailed(type:String,error:Int) {}
            override fun onServiceLost(service:NsdServiceInfo) {}
            override fun onServiceFound(service:NsdServiceInfo) {
                main.post {
                    if(generation!=epoch || resolving || !DiscoveryCandidate.matches(fingerprint,service.serviceName)) return@post
                    resolving=true
                    @Suppress("DEPRECATION")
                    manager.resolveService(service,object:NsdManager.ResolveListener {
                        override fun onResolveFailed(info:NsdServiceInfo,error:Int) {main.post {if(generation==epoch) resolving=false}}
                        override fun onServiceResolved(info:NsdServiceInfo) {
                            main.post {
                                if(generation!=epoch) return@post
                                resolving=false
                                val host=info.host?.hostAddress ?: return@post
                                if(info.port==38443 && Pairing.privateIp(host)) found(host,fingerprint)
                            }
                        }
                    })
                }
            }
        }
        listener=callback
        try {manager.discoverServices("_gamelingo._tcp.",NsdManager.PROTOCOL_DNS_SD,callback)}
        catch(_:RuntimeException) {stop();return}
        main.postDelayed({if(generation==epoch) stop()},12000)
    }
    fun stop() {
        ++epoch;resolving=false;main.removeCallbacksAndMessages(null)
        val old=listener;listener=null
        if(old!=null) try {manager.stopServiceDiscovery(old)} catch(_:RuntimeException) {}
    }
}
