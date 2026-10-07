package cordova.plugins.deeplink;

import android.content.Intent;
import android.net.Uri;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaArgs;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.PluginResult;

/**
 * Receives HTTPS App Links (Android intent filters) and forwards the incoming
 * URL to the subscribed JavaScript callback.
 *
 * - Cold start: the launch intent is captured in {@link #pluginInitialize} and
 *   kept until JavaScript subscribes.
 * - Warm start: a new intent is delivered through {@link #onNewIntent}.
 *
 * The filtered scheme, host and path prefix come from the app config.xml
 * (DeepLinkHost / DeepLinkPathPrefix), which the plugin fills from its
 * DEEPLINK_HOST / DEEPLINK_PATH_PREFIX install variables. Every remaining
 * validation (query strings, fragments, slug parsing) happens in the
 * application layer.
 */
public class DeepLinkPlugin extends CordovaPlugin {

    private static final String ACTION_SUBSCRIBE = "subscribe";
    private static final String SUPPORTED_SCHEME = "https";
    private static final String PREF_HOST = "DeepLinkHost";
    private static final String PREF_PATH_PREFIX = "DeepLinkPathPrefix";
    private static final String DEFAULT_PATH_PREFIX = "/";

    private CallbackContext subscription;
    private String pendingUrl;

    @Override
    public void pluginInitialize() {
        String launchUrl = extractUrl(cordova.getActivity().getIntent());
        if (launchUrl != null) {
            pendingUrl = launchUrl;
        }
    }

    @Override
    public boolean execute(String action, CordovaArgs args, CallbackContext callbackContext) {
        if (ACTION_SUBSCRIBE.equals(action)) {
            subscription = callbackContext;
            if (pendingUrl != null) {
                String url = pendingUrl;
                pendingUrl = null;
                deliver(url);
            }
            return true;
        }
        return false;
    }

    @Override
    public void onNewIntent(Intent intent) {
        String url = extractUrl(intent);
        if (url != null) {
            deliver(url);
        }
    }

    @Override
    public void onReset() {
        subscription = null;
    }

    private void deliver(String url) {
        if (subscription != null) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, url);
            result.setKeepCallback(true);
            subscription.sendPluginResult(result);
        } else {
            pendingUrl = url;
        }
    }

    private String extractUrl(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
            return null;
        }
        Uri data = intent.getData();
        if (data == null) {
            return null;
        }
        if (!SUPPORTED_SCHEME.equalsIgnoreCase(data.getScheme())) {
            return null;
        }
        if (!matchesConfiguredFilter(data)) {
            return null;
        }
        return data.toString();
    }

    private boolean matchesConfiguredFilter(Uri data) {
        String host = preferences.getString(PREF_HOST, "");
        if (host.length() > 0 && !host.equalsIgnoreCase(data.getHost())) {
            return false;
        }
        String pathPrefix = preferences.getString(PREF_PATH_PREFIX, DEFAULT_PATH_PREFIX);
        if (pathPrefix.length() == 0) {
            pathPrefix = DEFAULT_PATH_PREFIX;
        }
        String path = data.getPath();
        return path != null && path.startsWith(pathPrefix);
    }
}
