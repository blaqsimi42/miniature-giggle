# Authentication Setup (Google, Facebook, TikTok)

This document contains configuration snippets and platform setup notes for Google and Facebook sign-in, and a sample TikTok backend exchange flow.

## Google Sign-In (Android)

1. In Firebase Console, enable Google provider and create OAuth 2.0 client IDs for Android. Add your app's SHA-1 and SHA-256 to the Firebase project settings.
2. Add the following to `android/app/src/main/AndroidManifest.xml` inside `<application>` (replace `com.google.android.gms.auth.api.signin.RevocationBoundService` if present):

```xml
<!-- Google Sign-In metadata (if needed) -->
<meta-data android:name="com.google.android.gms.version" android:value="@integer/google_play_services_version" />
```

3. Ensure `google-services.json` is placed in `android/app/`.

## Google Sign-In (iOS)

1. In Firebase Console, add an iOS OAuth client ID and configure the reversed client id in `Info.plist`.
2. Add the following to `ios/Runner/Info.plist` (replace with your reversed client id):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

## Facebook (Android)

1. In Facebook Developer Console, create an app and add Android platform. Provide your package name and key hashes.
2. Add the Facebook App ID to `android/app/src/main/res/values/strings.xml`:

```xml
<string name="facebook_app_id">YOUR_FACEBOOK_APP_ID</string>
<string name="fb_login_protocol_scheme">fbYOUR_FACEBOOK_APP_ID</string>
```

3. Add the following inside `<application>` of `AndroidManifest.xml`:

```xml
<meta-data android:name="com.facebook.sdk.ApplicationId" android:value="@string/facebook_app_id" />
<activity android:name="com.facebook.FacebookActivity" android:configChanges="keyboard|keyboardHidden|screenLayout|screenSize|orientation" android:label="@string/app_name" />
```

## Facebook (iOS)

1. In Facebook Developer Console, add iOS platform and set the Bundle ID.
2. Add the following to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>fbYOUR_FACEBOOK_APP_ID</string>
    </array>
  </dict>
</array>
<key>FacebookAppID</key>
<string>YOUR_FACEBOOK_APP_ID</string>
<key>FacebookDisplayName</key>
<string>YOUR_APP_NAME</string>
```

## TikTok → Firebase Flow (overview)

TikTok does not provide a direct Firebase integration. The recommended approach:

1. Perform the OAuth flow on the client to obtain an authorization code (we use `flutter_web_auth`).
2. Send the code to a secure backend service.
3. Backend exchanges the code for TikTok access tokens and retrieves a stable TikTok user id.
4. Backend uses Firebase Admin SDK to create a Firebase Custom Token for that TikTok user id and returns it to the client.
5. Client signs in with `FirebaseAuth.signInWithCustomToken()`.

See `tools/tiktok_backend/README.md` for a sample Node.js backend that performs steps 3–4.

## Next steps
- Replace placeholder IDs and URIs in the snippets above with values from your provider dashboards.
- Follow package docs for `google_sign_in` and `flutter_facebook_auth` for platform-specific steps and permissions.
