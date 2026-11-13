package dev.gamelingo.tv

import org.junit.Assert.*
import org.junit.Test
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.ProtocolException
import java.io.EOFException
import java.security.cert.CertificateException
import javax.net.ssl.SSLHandshakeException

class ConnectionFailureTest {
    @Test fun wrappedCertificateFailureStopsRetriesWithoutLeakingMessages() {
        val secret = "secret-fixture-pin-token"
        val failure = SSLHandshakeException(secret).apply { initCause(CertificateException(secret)) }
        val result = ConnectionFailure.classify(failure,"TLS")
        assertEquals("tls.certificate",result.code)
        assertTrue(result.terminal); assertFalse(result.text.contains(secret))
    }
    @Test fun refusedTcpIsRetryableAndSpecific() {
        val result = ConnectionFailure.classify(ConnectException("credential"),"TCP")
        assertEquals("tcp.failed",result.code); assertFalse(result.terminal)
    }
    @Test fun timeoutKeepsStage() {
        assertTrue(ConnectionFailure.classify(SocketTimeoutException(),"TLS").text.contains("TLS"))
    }
    @Test fun upgradeFailureIsTerminal() {
        assertEquals("websocket.http",ConnectionFailure.classify(ProtocolException(),"WebSocket",403).code)
        assertTrue(ConnectionFailure.classify(ProtocolException(),"WebSocket",403).terminal)
    }
    @Test fun abruptCloseKeepsStageWithoutLeakingPeerData() {
        val result = ConnectionFailure.classify(EOFException("private-token"),"المصادقة")
        assertTrue(result.text.contains("المصادقة")); assertFalse(result.text.contains("private-token"))
    }
}
