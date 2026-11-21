package dev.gamelingo.tv

import android.security.keystore.*
import android.util.Base64
import org.json.JSONObject
import java.net.*
import java.io.*
import java.math.BigInteger
import java.security.*
import java.security.cert.X509Certificate
import java.util.Date
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.*
import javax.security.auth.x500.X500Principal

/** Ephemeral LAN TLS bootstrap. The phone remains the authenticated subtitle server. */
class QRPairingServer(private val confirm:(JSONObject,(Boolean)->Unit)->Unit,private val ready:(String,String)->Unit) {
    private val alias="gamelingo-qr-"+java.util.UUID.randomUUID().toString()
    private val session=java.util.UUID.randomUUID().toString()
    private val nonce=ByteArray(32).also{SecureRandom().nextBytes(it)}
    private val consumed=AtomicBoolean(false)
    private val active=AtomicBoolean(true)
    private val expires=System.currentTimeMillis()+120000
    private var server:SSLServerSocket?=null
    private var store:KeyStore?=null
    fun start(host:String):String {
        require(Pairing.privateIp(host))
        val generator=KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA,"AndroidKeyStore")
        generator.initialize(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(2048).setDigests(KeyProperties.DIGEST_SHA256,KeyProperties.DIGEST_SHA512)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1,KeyProperties.SIGNATURE_PADDING_RSA_PSS)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
            .setCertificateSubject(X500Principal("CN=GameLingo TV one-time pairing"))
            .setCertificateSerialNumber(BigInteger(128,SecureRandom()))
            .setCertificateNotBefore(Date(System.currentTimeMillis()-86400000))
            .setCertificateNotAfter(Date(System.currentTimeMillis()+86400000)).build())
        generator.generateKeyPair()
        val keys=KeyStore.getInstance("AndroidKeyStore").apply{load(null)};store=keys
        val chain=arrayOf(keys.getCertificate(alias) as X509Certificate)
        val key=keys.getKey(alias,null) as PrivateKey
        val manager=object:X509KeyManager {
            override fun getClientAliases(t:String?,i:Array<java.security.Principal>?):Array<String>?=null
            override fun chooseClientAlias(t:Array<String>?,i:Array<java.security.Principal>?,s:Socket?):String?=null
            override fun getServerAliases(t:String?,i:Array<java.security.Principal>?):Array<String>? = if(t=="RSA") arrayOf(alias) else null
            override fun chooseServerAlias(t:String?,i:Array<java.security.Principal>?,s:Socket?):String?=if(t=="RSA") alias else null
            override fun getCertificateChain(a:String?):Array<X509Certificate>? = if(a==alias) chain else null
            override fun getPrivateKey(a:String?):PrivateKey?=if(a==alias) key else null
        }
        val tls=SSLContext.getInstance("TLS").apply{init(arrayOf<KeyManager>(manager),null,SecureRandom())}
        val listener=tls.serverSocketFactory.createServerSocket(38444,2,InetAddress.getByName(host)) as SSLServerSocket
        listener.enabledProtocols=arrayOf("TLSv1.2");listener.soTimeout=1000;server=listener
        val fingerprint=MessageDigest.getInstance("SHA-256").digest(chain[0].encoded).joinToString(""){"%02x".format(it)}
        Thread({serve(listener)},"gamelingo-qr-bootstrap").start()
        return JSONObject().put("v",1).put("kind","gamelingo-tv-pair").put("host",host).put("port",38444)
            .put("session",session).put("nonce",Base64.encodeToString(nonce,Base64.NO_WRAP)).put("fingerprint",fingerprint)
            .put("name",android.os.Build.MODEL.take(80)).put("expires",expires).toString()
    }
    private fun serve(listener:SSLServerSocket) {
        var attempts=0
        while(active.get() && System.currentTimeMillis()<expires && attempts<5 && !consumed.get()) {
            try {
                val socket=listener.accept() as SSLSocket;attempts++
                socket.use { connection ->
                    connection.soTimeout=8000;connection.startHandshake()
                    val input=connection.inputStream.buffered()
                    fun line():String {
                        val bytes=ByteArrayOutputStream()
                        while(bytes.size()<2048) {val c=input.read();require(c>=0);if(c==10) return bytes.toString("UTF-8").trimEnd('\r');bytes.write(c)}
                        throw IOException("Header limit")
                    }
                    require(line()=="POST /pair HTTP/1.1")
                    val headers=mutableMapOf<String,String>();var total=0
                    while(true) {val value=line();total+=value.length;require(total<4096);if(value.isEmpty())break;val split=value.indexOf(':');require(split>0);headers[value.substring(0,split).lowercase()]=value.substring(split+1).trim()}
                    val length=headers["content-length"]?.toIntOrNull() ?: 0;require(length in 1..2048)
                    require(!headers.containsKey("transfer-encoding"))
                    val bytes=ByteArray(length);var read=0
                    while(read<length) {val count=input.read(bytes,read,length-read);require(count>0);read+=count}
                    val body=JSONObject(String(bytes,Charsets.UTF_8))
                    val supplied=Base64.decode(body.getString("nonce"),Base64.NO_WRAP)
                    require(active.get() && System.currentTimeMillis()<expires && body.getString("session")==session && MessageDigest.isEqual(supplied,nonce))
                    require(Pairing.privateIp(body.getString("host")) && body.getString("host")==connection.inetAddress.hostAddress)
                    require(body.getString("code").matches(Regex("[0-9a-f]{64}-[0-9]{6}")))
                    // Consume before confirmation: retries/replay cannot replace a pending device.
                    require(consumed.compareAndSet(false,true))
                    val latch=java.util.concurrent.CountDownLatch(1);var accepted=false
                    confirm(body) { accepted=it;latch.countDown() }
                    val answered=latch.await(45,java.util.concurrent.TimeUnit.SECONDS)
                    accepted=answered && accepted && active.get() && System.currentTimeMillis()<expires
                    val response=if(accepted) "{\"accepted\":true}" else "{\"accepted\":false}"
                    connection.outputStream.write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${response.toByteArray().size}\r\nConnection: close\r\n\r\n"+response).toByteArray())
                    connection.outputStream.flush()
                    if(accepted) ready(body.getString("host"),body.getString("code"))
                }
            } catch(_:SocketTimeoutException) {} catch(_:Exception) { /* Never log bootstrap material. */ }
        }
        stop()
    }
    fun stop() {active.set(false);try{server?.close()}catch(_:Exception){};server=null;try{store?.deleteEntry(alias)}catch(_:Exception){};nonce.fill(0)}
    companion object {
        fun localHost():String?=java.util.Collections.list(NetworkInterface.getNetworkInterfaces()).filter{it.isUp && !it.isLoopback}.flatMap{java.util.Collections.list(it.inetAddresses)}.mapNotNull{it.hostAddress}.firstOrNull{Pairing.privateIp(it)}
    }
}
