# cordova-plugin-app-deeplink

Generic Cordova plugin that opens your app from HTTPS links:

* **Android** – [App Links](https://developer.android.com/training/app-links) (`https` intent filter with `autoVerify`)
* **iOS** – [Universal Links](https://developer.apple.com/documentation/xcode/supporting-associated-domains) (`applinks:` associated domain)

The domain and the path prefix are **plugin variables**, so the same plugin can be
reused in any project. Nothing is hard coded: you supply `DEEPLINK_HOST` and
`DEEPLINK_PATH_PREFIX` from your app's `config.xml`.

Incoming URLs are forwarded to JavaScript for both cold starts (app launched by
the link) and warm starts (app already running).

---

## Requirements

| | |
|---|---|
| `cordova-android` | `>= 10.0.0` |
| `cordova-ios` | `>= 6.0.0` (entitlements files must exist, see [iOS notes](#ios-notes)) |
| Node / Cordova CLI | Cordova 9 or newer (plugin variables in `config.xml`) |

---

## Installation

### Option A – declare the plugin in `config.xml` (recommended)

Add the plugin and its variables to your project's `config.xml`, then run
`cordova prepare`. Cordova installs the plugin and passes the variables to it:

```xml
<widget id="com.example.myapp" version="1.0.0" ...>

    ...

    <plugin name="cordova-plugin-app-deeplink" spec="^1.0.0">
        <variable name="DEEPLINK_HOST" value="www.example.com" />
        <variable name="DEEPLINK_PATH_PREFIX" value="/product/" />
    </plugin>

</widget>
```

```bash
# at least one platform must already be added, e.g.
cordova platform add android ios
cordova prepare
```

`cordova prepare` (and `cordova platform add`) discovers the plugin in
`config.xml` and installs it with the `<variable>` values above. `cordova
prepare` on a project without platforms does nothing.

> `spec` must resolve to something Cordova can install. Use `^1.0.0` once the
> package is published to npm; before that use a Git URL or a local path, e.g.
> `spec="/absolute/path/to/cordova-plugin-deeplink"`.

### Option B – install from the CLI

```bash
cordova plugin add cordova-plugin-app-deeplink \
    --variable DEEPLINK_HOST=www.example.com \
    --variable DEEPLINK_PATH_PREFIX=/product/
```

Cordova persists the plugin together with its variables (`package.json` on
Cordova 12+, `config.xml` on older versions), so future `cordova prepare` runs
restore it with the same values.

Installing from a Git repository or a local folder works the same way:

```bash
cordova plugin add https://github.com/mohamedrafiqp/cordova-plugin-deeplink.git \
    --variable DEEPLINK_HOST=www.example.com \
    --variable DEEPLINK_PATH_PREFIX=/product/
```


### Install variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `DEEPLINK_HOST` | **yes** | – | Domain that should open the app, **without** scheme, path or trailing slash. Example: `www.example.com`. |
| `DEEPLINK_PATH_PREFIX` | no | `/` | Only links under this path open/are forwarded to the app. Must start with `/`. Example: `/product/`. Use `/` to accept every path on the host. |

`DEEPLINK_HOST` has no default on purpose: installation fails with
`Variable(s) missing: DEEPLINK_HOST` when it is not supplied, instead of
silently registering the wrong domain.

Both values are read from `config.xml` at install time and baked into:

* the Android `AndroidManifest.xml` intent filter,
* the iOS `Entitlements-Debug.plist` / `Entitlements-Release.plist`
  associated domains, and
* the app `config.xml` as `DeepLinkHost` / `DeepLinkPathPrefix`, which the
  native code uses to apply the same filter before handing the URL to
  JavaScript.

You do **not** need to add `DeepLinkHost` / `DeepLinkPathPrefix` yourself.

---

## What the plugin changes in your project

### Android

* `res/xml/config.xml` – registers the `DeepLink` feature (`onload`) and the
  `DeepLinkHost` / `DeepLinkPathPrefix` preferences.
* `AndroidManifest.xml` – adds, to the main activity:

  ```xml
  <intent-filter android:autoVerify="true">
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="https"
            android:host="www.example.com"
            android:pathPrefix="/product/" />
  </intent-filter>
  ```

* `src/cordova/plugins/deeplink/DeepLinkPlugin.java` – captures the launch
  intent and every new intent, filters scheme/host/path, and pushes matching
  URLs to JavaScript.

### iOS

* `config.xml` – registers the `DeepLink` feature (`onload`) and the
  `DeepLinkHost` / `DeepLinkPathPrefix` preferences.
* `Entitlements-Debug.plist` and `Entitlements-Release.plist` – adds
  `com.apple.developer.associated-domains` with `applinks:www.example.com`.
* `CDVDeepLink` – hooks `CDVPluginContinueUserActivityNotification` and
  intercepts `scene:willConnectToSession:options:` so Universal Links that
  arrive on a cold start are not lost before JavaScript subscribes.

---

## Server configuration (required by the OS)

The plugin configures the app side only. The OS still verifies the domain, so
host these files on the domain you passed as `DEEPLINK_HOST`.

### Android – `/.well-known/assetlinks.json`

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.example.myapp",
    "sha256_cert_fingerprints": ["AA:BB:CC:..."]
  }
}]
```

Serve it over `https` with `Content-Type: application/json`, no redirects and
no authentication. Get the fingerprint with:

```bash
keytool -list -v -keystore my-release-key.keystore
```

### iOS – `/.well-known/apple-app-site-association`

```json
{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "TEAMID.com.example.myapp",
      "paths": ["/product/*"]
    }]
  }
}
```

Serve it without a `.json` extension requirement (both work) using
`Content-Type: application/json`, and enable the **Associated Domains**
capability (`applinks`) for your App ID / provisioning profile.

---

## JavaScript API

```js
document.addEventListener('deviceready', function () {
    cordova.plugins.deepLink.subscribe(function (url) {
        // cold start and warm start URLs arrive here
        console.log('Deep link:', url);
        // e.g. https://www.example.com/product/123?ref=email
    });
}, false);
```

* `subscribe(listener)` – registers a listener; it may be called more than once
  to add more listeners.
* URLs captured before `subscribe()` (app started by the link) are delivered
  immediately after the subscription is registered.
* The plugin stays subscribed (the native callback is kept alive) until the
  WebView reloads.
* Exceptions thrown inside a listener are swallowed so later listeners still
  receive the URL.

Parse query strings, fragments and slugs in your application layer – the plugin
only decides *which* URLs belong to the app.

---

## Changing variables or uninstalling

Variable values are substituted when the plugin is installed, so editing
`config.xml` alone does nothing for an already-installed plugin. Re-install it:

```bash
cordova plugin rm cordova-plugin-app-deeplink
cordova prepare
```

`DEEPLINK_HOST` is mandatory, and Cordova only auto-fills variables from a
`<plugin>` element in `config.xml`. If your plugin was installed from the CLI
(variables stored in `package.json`), pass them again on removal:

```bash
cordova plugin rm cordova-plugin-app-deeplink \
    --variable DEEPLINK_HOST=www.example.com \
    --variable DEEPLINK_PATH_PREFIX=/product/
```

> Cordova checks the variables *before* uninstalling. Running
> `cordova plugin rm` without them fails **and** deletes `plugins/<id>`, which
> leaves the generated platform files behind. If that happened, remove the
> leftovers by hand (or re-add the plugin and remove it again with variables).

Then verify the result:

* `platforms/android/app/src/main/AndroidManifest.xml` → `android:host` /
  `android:pathPrefix`
* `platforms/ios/App/Entitlements-*.plist` (cordova-ios 8+) or
  `platforms/ios/<ProjectName>/Entitlements-*.plist` (cordova-ios 6/7) →
  `applinks:<host>`
* `platforms/android/app/src/main/res/xml/config.xml` → `DeepLinkHost` /
  `DeepLinkPathPrefix`

---

## Testing

Install a release/development build signed with a certificate that matches your
`assetlinks.json` (Android does not verify links for debug builds signed with
the default debug key on some devices).

```bash
# Android
adb shell am start -a android.intent.action.VIEW \
    -d "https://www.example.com/product/123"
```

On iOS, use Safari/Notes to tap a link on a real device (Universal Links do not
work in the iOS Simulator in every configuration).

In the browser console you should see the URL printed by your `subscribe`
listener.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Variable(s) missing: DEEPLINK_HOST` | The plugin was installed without `DEEPLINK_HOST`. Add it to the `<plugin>` element in `config.xml` (or pass `--variable`) and re-install. The same message on `cordova plugin rm` means you have to pass the variables again – see [Changing variables or uninstalling](#changing-variables-or-uninstalling). |
| `config file .../Entitlements-Debug.plist requested for changes not found, ignoring` | The iOS project has no entitlements file (see [iOS notes](#ios-notes)). Universal Links are not configured until the file exists. |
| Link opens the browser instead of the app | Domain not verified: check `assetlinks.json` / `apple-app-site-association`, the exact host (scheme excluded) and the path prefix. On Android 12+ unverified links always show a disambiguation dialog. |
| Link opens the app but no JS callback | You called `cordova.plugins.deepLink.subscribe()` after the URL was already handled elsewhere, or a listener threw – see [JavaScript API](#javascript-api). |
| Wrong domain after editing `config.xml` | Variables are baked at install time – re-install the plugin (see above). |

### iOS notes

The entitlements targets use the wildcard path `*/Entitlements-*.plist`, which
matches both project layouts:

* cordova-ios 6/7 → `platforms/ios/<ProjectName>/Entitlements-*.plist`
* cordova-ios 8+ → `platforms/ios/App/Entitlements-*.plist`

Both files ship with the standard `cordova-ios` templates. If your project uses
a custom template without them, create them (an empty `<dict/>` is enough) –
otherwise Cordova prints the "config file not found, ignoring" warning above
and the associated domain is never added.

---

## Migrating from `cordova-plugin-annai-deeplink`

This plugin is the generic version of the previously hard-coded
Annai Jewellers plugin.

| Before | Now |
|---|---|
| `cordova-plugin-annai-deeplink` | `cordova-plugin-app-deeplink` |
| Host `www.annaijewellers.com`, prefix `/product/` hard coded | `DEEPLINK_HOST` / `DEEPLINK_PATH_PREFIX` variables |
| `cordova.plugins.annaiDeeplink.subscribe(...)` | `cordova.plugins.deepLink.subscribe(...)` |
| Feature / service `AnnaiDeepLink` | `DeepLink` |
| Java package `com.annai.jewellers.deeplink` | Java package `cordova.plugins.deeplink` |
| iOS class `CDVAnnaiDeepLink` | iOS class `CDVDeepLink` |

```bash
cordova plugin rm cordova-plugin-annai-deeplink
```

```xml
<plugin name="cordova-plugin-app-deeplink" spec="^1.0.0">
    <variable name="DEEPLINK_HOST" value="www.annaijewellers.com" />
    <variable name="DEEPLINK_PATH_PREFIX" value="/product/" />
</plugin>
```

```bash
cordova prepare
```

Update the JavaScript namespace in your app, then rebuild.

---

## License

MIT
