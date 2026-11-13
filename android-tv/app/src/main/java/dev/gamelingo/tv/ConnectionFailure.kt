package dev.gamelingo.tv

import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.ProtocolException
import java.security.cert.CertificateException
import javax.net.ssl.SSLException

// Fixed messages only: throwable.message may contain credentials or peer-controlled data.
internal object ConnectionFailure {
    data class Result(val code: String, val text: String, val terminal: Boolean = false)
    fun classify(error: Throwable, stage: String, httpCode: Int? = null): Result {
        val causes = generateSequence(error) { it.cause }.take(8).toList()
        return when {
            causes.any { it is CertificateException } -> Result("tls.certificate", "فشل التحقق من بصمة الشهادة أو صلاحيتها؛ راجع رمز المصدر وساعة التلفزيون", true)
            causes.any { it is SSLException } -> Result("tls.handshake", "فشلت مصافحة TLS الآمنة", true)
            httpCode != null -> Result("websocket.http", "فشلت ترقية WebSocket · HTTP $httpCode", true)
            causes.any { it is ConnectException || it is NoRouteToHostException } -> Result("tcp.failed", "تعذر اتصال TCP بالمصدر:38443؛ تحقق من تشغيله وبقائه مفتوحًا ومسار الشبكة")
            causes.any { it is SocketTimeoutException } -> Result("connection.timeout", "انتهت مهلة الاتصال عند $stage")
            causes.any { it is ProtocolException } -> Result("websocket.protocol", "خطأ بروتوكول WebSocket", true)
            else -> Result("connection.closed", "انقطع الاتصال عند $stage")
        }
    }
}
