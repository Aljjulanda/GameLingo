import okhttp3.*;
import org.json.JSONObject;
import java.io.*;
import java.security.*;
import java.security.cert.*;
import java.util.concurrent.*;
import javax.net.ssl.*;

/** Same TLS pinning, OkHttp version and wire messages as the shipped TV receiver.
 * Fixture secrets travel through stdin/HTTP in memory; stdout is consumed by the
 * test bridge and never copied into CI logs. Not a production connection tool. */
public final class OkHttpProbe {
    static final BlockingQueue<Object> events = new LinkedBlockingQueue<>();
    static JSONObject next() throws Exception {
        Object event = events.poll(12, TimeUnit.SECONDS);
        if (event instanceof JSONObject) return (JSONObject)event;
        if (event instanceof Throwable) throw new Exception("client failed: " + event.getClass().getSimpleName());
        throw new Exception("missing protocol message");
    }
    static void require(boolean value, String message) throws Exception { if (!value) throw new Exception(message); }
    public static void main(String[] args) throws Exception {
        JSONObject input = new JSONObject(new BufferedReader(new InputStreamReader(System.in)).readLine());
        final String expected = input.getString("prefix"), host = input.getString("host"), mode = input.getString("mode");
        X509TrustManager trust = new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] chain, String type) throws CertificateException { throw new CertificateException(); }
            public void checkServerTrusted(X509Certificate[] chain, String type) throws CertificateException {
                chain[0].checkValidity();
                try {
                    byte[] bytes = MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded());
                    StringBuilder fp = new StringBuilder();
                    for (byte b : bytes) fp.append(String.format("%02x", b));
                    if (!fp.toString().startsWith(expected)) throw new CertificateException("Fingerprint mismatch");
                } catch (NoSuchAlgorithmException e) { throw new CertificateException("SHA-256 unavailable"); }
            }
        };
        SSLContext tls = SSLContext.getInstance("TLS"); tls.init(null,new TrustManager[]{trust},new SecureRandom());
        OkHttpClient client = new OkHttpClient.Builder().sslSocketFactory(tls.getSocketFactory(),trust)
            .hostnameVerifier((name,session) -> name.equals(host)).pingInterval(1,TimeUnit.SECONDS)
            .connectTimeout(5,TimeUnit.SECONDS).readTimeout(10,TimeUnit.SECONDS)
            .followRedirects(false).followSslRedirects(false).build();
        CountDownLatch closed = new CountDownLatch(1);
        JSONObject result = new JSONObject();
        final boolean[] opened = {false};
        WebSocket socket = client.newWebSocket(new Request.Builder().url("wss://"+host+":38443/").build(),new WebSocketListener() {
            public void onOpen(WebSocket ws, Response response) {
                opened[0] = true;
                result.put("tls",response.handshake().tlsVersion().javaName());
                JSONObject auth = new JSONObject().put("v",1);
                if (mode.equals("hello") || mode.equals("bad-token")) auth.put("type","hello").put("token",input.getString("token"));
                else auth.put("type","pair").put("pin",input.optString("pin")).put("padding",new String(new char[10000]).replace('\0','x'));
                ws.send(auth.toString());
            }
            public void onMessage(WebSocket ws,String text) { events.add(new JSONObject(text)); }
            public void onClosing(WebSocket ws,int code,String reason) { result.put("close_code",code); ws.close(code,null); }
            public void onClosed(WebSocket ws,int code,String reason) { closed.countDown(); }
            public void onFailure(WebSocket ws,Throwable error,Response response) { events.add(error); closed.countDown(); }
        });
        try {
            if (mode.equals("bad-fingerprint")) {
                Object event = events.poll(12,TimeUnit.SECONDS);
                require(!opened[0] && event instanceof SSLHandshakeException,"wrong fingerprint was not rejected by TLS");
                result.put("fingerprint_rejected",true);
            } else if (mode.equals("bad-pin") || mode.equals("bad-token")) {
                require(closed.await(12,TimeUnit.SECONDS),"authentication rejection timed out");
                require(result.optInt("close_code") == 1008,"expected policy rejection 1008");
                require(events.isEmpty(),"unauthenticated peer received data");
                result.put("authentication_rejected",true);
            } else {
                if (mode.equals("pair")) {
                    JSONObject paired = next(); require(paired.getString("type").equals("paired"),"expected paired");
                    String token = paired.getString("token"); require(token.length() >=32 && token.length()<=128,"token size");
                    result.put("token",token);
                }
                JSONObject connected = next(); require(connected.getString("type").equals("connection_status"),"expected connected");
                JSONObject settings = next(); require(settings.getString("type").equals("settings_sync"),"expected settings");
                require(settings.getInt("v")==1 && settings.getString("session").equals(connected.getString("session")),"session mismatch");
                result.put("session",connected.getString("session"));
                socket.send(new JSONObject().put("v",1).put("type","settings_ack").put("revision",settings.getJSONObject("settings").getLong("revision"))
                    .put("width_px",1920).put("height_px",1080).toString());
                socket.send("{\"v\":1,\"type\":\"heartbeat\"}");
                require(next().getString("type").equals("heartbeat"),"expected heartbeat; stale subtitle replayed");
                // Stay through multiple RFC 6455 ping/pong cycles (Android pingInterval).
                Thread.sleep(2400);
                require(closed.getCount()==1,"connection lost during ping/pong");
                result.put("heartbeat",true);
                if (input.optBoolean("abort")) { socket.cancel(); closed.await(3,TimeUnit.SECONDS); }
                else { socket.close(1000,null); require(closed.await(5,TimeUnit.SECONDS),"close handshake"); }
            }
            result.put("ok",true);
            System.out.println(result.toString());
        } finally {
            socket.cancel(); client.dispatcher().executorService().shutdownNow(); client.connectionPool().evictAll();
        }
    }
}
