#  Customization

Cirruscope is designed to enable customized builds. Those are configured completely through Xcode build settings. This project is set up to honor a "Local.xcconfig" file in the project root folder during build time (if present). The following build settings must be overridden for customized builds. You can read the default values and their hierarchy in the various .xcconfig files of this project.

| Build Setting                         | Required | Description  |
|---------------------------------------|-----------|--------------|
| `CIRRUSCOPE_APPICON_NAME`             | **Yes**   | The override file name for the app icon to use. Excludes ".icon" file extension. Expects to be Icon Composer file formin the same folder as the default icon. The "CustomAppIcon.icon" is excluded from version control in this project. |
| `CIRRUSCOPE_APP_STORE_ID`             | No       | The numeric app store id of the app once its record has been created there. This is required to ask for ratings and reviews. If omitted, then the related menu item to rate the app will not be visible. |
| `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER`   | **Yes**  | The base identifier from which several identifiers for the app and its extensions are derived from. |
| `CIRRUSCOPE_BUNDLE_NAME`              | **Yes**  | The file name of the built app bundle. |
| `CIRRUSCOPE_GLOBAL_ACCENT_COLOR_NAME` | No       | The customized accent color set name to use instead of the default. |
| `CIRRUSCOPE_PRIVACY_POLICY_URL`       | No       | The address of the privacy policy web page to refer to. If omitted, then the related menu item to rate the app will not be visible. |
| `CIRRUSCOPE_SERVER_URL`               | No       | If not empty, the app does not ask the user for a server address but connects to only this server automatically. |
| `CIRRUSCOPE_SUPPORT_URL`              | No       | The address of the support web page to refer to. If omitted, then the related menu item to rate the app will not be visible. |

Everything starts with the creation of a "Local.xcconfig" file in the project root folder which, if present, is included by the [Cirruscope.xcconfig](./../Cirruscope.xcconfig). Both are Xcode build settings files. The former is optional and can be used to override settings of the latter. Here is an example of its content:

```plaintext
CIRRUSCOPE_APPICON_NAME=CustomAppIcon
CIRRUSCOPE_APP_STORE_ID=123456789
CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=org.example.cirruscope
CIRRUSCOPE_BUNDLE_NAME=Example Cloud
CIRRUSCOPE_PRIVACY_POLICY_URL = https:/$()/example.org/privacy.html
CIRRUSCOPE_SERVER_URL = https:/$()/nextcloud.example.org
CIRRUSCOPE_SUPPORT_URL = https:/$()/example.org/support.html
DEVELOPMENT_TEAM=A1B2C3D4
```

Note that `//` is the line comment delimiter in this syntax. Hence the empty substitutions in the URLs are required.

## Archiving

With this setup, there is only one Terminal command left to run.

```bash
xcodebuild archive \
  -project Cirruscope.xcodeproj \
  -scheme "Cirruscope for macOS" \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "./Example Cloud.xcarchive" \
  -allowProvisioningUpdates
```

Now you have an Xcode build archive. It is not a ready to use app bundle yet, though. This requires extra steps which depend on what distribution you aim for. The most convenient and easiest way to continue is to open the created Xcode archive with Xcode in its organizer, hit "Distribute App" and "Direct Distribution" which will guide you through the process of notarization (active Apple developer program enrollment required). It will result in a properly signed, ready to use macOS app. This does not touch distribution processes like updates, though. Typically, the App Store helps with this.
