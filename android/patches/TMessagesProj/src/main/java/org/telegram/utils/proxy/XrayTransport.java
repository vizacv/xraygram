package org.telegram.utils.proxy;

import android.net.Uri;
import android.os.SystemClock;
import android.text.TextUtils;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;
import org.telegram.messenger.FileLog;
import org.telegram.tgnet.RequestTimeDelegate;

import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

import libXray.LibXray;

/**
 * Xraygram: runs an in-process Xray-core (via libXray) with a SOCKS5 inbound on
 * 127.0.0.1 and lets tgnet use it as an ordinary SOCKS5 proxy.
 *
 * Only one Xray instance can live in the process (libXray limitation), so this
 * class keeps a single running config keyed by its share link.
 */
public final class XrayTransport {

    private static final int API_VERSION = 3;
    private static final Object lock = new Object();

    private static String runningLink;
    private static int runningPort;

    private XrayTransport() {
    }

    public static boolean isSupportedLink(String link) {
        if (TextUtils.isEmpty(link)) {
            return false;
        }
        String lower = link.trim().toLowerCase(Locale.US);
        return lower.startsWith("vless://")
                || lower.startsWith("vmess://")
                || lower.startsWith("trojan://")
                || lower.startsWith("ss://")
                || lower.startsWith("hysteria2://")
                || lower.startsWith("hy2://");
    }

    /**
     * Starts (or reuses) Xray for the given share link.
     *
     * @return local SOCKS5 port, or 0 on failure.
     */
    public static int start(String link) {
        if (!isSupportedLink(link)) {
            return 0;
        }
        synchronized (lock) {
            if (link.equals(runningLink) && runningPort != 0 && isRunning()) {
                return runningPort;
            }
            stopInternal();
            try {
                int port = findFreePort();
                String config = buildConfig(link, port);
                JSONObject payload = new JSONObject().put("xrayJson", config);
                JSONObject response = invoke("runXray", payload);
                if (!response.optBoolean("success")) {
                    FileLog.e("xraygram: runXray failed: " + response.optString("error"));
                    return 0;
                }
                runningLink = link;
                runningPort = port;
                FileLog.d("xraygram: xray started on 127.0.0.1:" + port);
                return port;
            } catch (Throwable e) {
                FileLog.e(e);
                stopInternal();
                return 0;
            }
        }
    }

    public static void stop() {
        synchronized (lock) {
            stopInternal();
        }
    }

    /** Local SOCKS port if Xray is currently running this exact link, else 0. */
    public static int getPortIfRunning(String link) {
        synchronized (lock) {
            return link != null && link.equals(runningLink) && isRunning() ? runningPort : 0;
        }
    }

    public static String version() {
        try {
            return invoke("xrayVersion", null).optJSONObject("data").optString("version");
        } catch (Throwable e) {
            return "";
        }
    }

    /**
     * Rough reachability check for a link that is not the running one:
     * measures TCP connect time to the remote server (does not prove the
     * protocol handshake works).
     */
    public static void checkTcp(String host, int port, RequestTimeDelegate delegate) {
        new Thread(() -> {
            long result = -1;
            if (!TextUtils.isEmpty(host) && port > 0) {
                try (Socket socket = new Socket()) {
                    long start = SystemClock.elapsedRealtime();
                    socket.connect(new InetSocketAddress(host, port), 5000);
                    result = Math.max(1, SystemClock.elapsedRealtime() - start);
                } catch (Throwable ignore) {
                }
            }
            delegate.run(result);
        }, "xraygram-check").start();
    }

    /** Extracts {host, port} from a share link for display; never throws. */
    public static Object[] parseServer(String link) {
        String host = null;
        int port = 0;
        try {
            String trimmed = link.trim();
            if (trimmed.toLowerCase(Locale.US).startsWith("vmess://")) {
                String body = trimmed.substring(8);
                int hash = body.indexOf('#');
                if (hash >= 0) {
                    body = body.substring(0, hash);
                }
                JSONObject json = new JSONObject(new String(Base64.decode(body, Base64.DEFAULT | Base64.URL_SAFE), StandardCharsets.UTF_8));
                host = json.optString("add", null);
                port = json.optInt("port", 0);
            } else {
                Uri uri = Uri.parse(trimmed);
                host = uri.getHost();
                port = uri.getPort();
            }
        } catch (Throwable ignore) {
        }
        return new Object[]{host != null ? host : "", Math.max(port, 0)};
    }

    private static boolean isRunning() {
        try {
            JSONObject data = invoke("getXrayState", null).optJSONObject("data");
            return data != null && data.optBoolean("running");
        } catch (Throwable e) {
            return false;
        }
    }

    private static void stopInternal() {
        if (runningLink != null) {
            try {
                invoke("stopXray", null);
            } catch (Throwable e) {
                FileLog.e(e);
            }
        }
        runningLink = null;
        runningPort = 0;
    }

    private static String buildConfig(String link, int socksPort) throws Exception {
        JSONObject convertPayload = new JSONObject().put("text", link.trim());
        JSONObject converted = invoke("convertShareLinksToXrayJson", convertPayload);
        if (!converted.optBoolean("success")) {
            throw new IllegalArgumentException("convertShareLinksToXrayJson: " + converted.optString("error"));
        }
        Object data = converted.opt("data");
        JSONObject outboundsDoc = data instanceof JSONObject ? (JSONObject) data : new JSONObject(String.valueOf(data));
        JSONArray outbounds = outboundsDoc.optJSONArray("outbounds");
        if (outbounds == null || outbounds.length() == 0) {
            throw new IllegalArgumentException("no outbounds in link");
        }
        // Keep only the first outbound and make it the default route.
        JSONObject proxy = outbounds.getJSONObject(0);
        proxy.put("tag", "proxy");

        JSONObject socksSettings = new JSONObject()
                .put("auth", "noauth")
                .put("udp", false);
        JSONObject inbound = new JSONObject()
                .put("tag", "tg-in")
                .put("listen", "127.0.0.1")
                .put("port", socksPort)
                .put("protocol", "socks")
                .put("settings", socksSettings);

        JSONObject config = new JSONObject()
                .put("log", new JSONObject().put("loglevel", "warning"))
                .put("inbounds", new JSONArray().put(inbound))
                .put("outbounds", new JSONArray().put(proxy));
        return config.toString();
    }

    private static int findFreePort() throws Exception {
        try (ServerSocket socket = new ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))) {
            socket.setReuseAddress(true);
            return socket.getLocalPort();
        }
    }

    private static JSONObject invoke(String method, JSONObject payload) throws Exception {
        JSONObject request = new JSONObject()
                .put("apiVersion", API_VERSION)
                .put("method", method);
        if (payload != null) {
            request.put("payload", payload);
        }
        return new JSONObject(LibXray.invoke(request.toString()));
    }
}
