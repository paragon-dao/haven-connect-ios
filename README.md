# Haven Connect — Web Bluetooth for iOS Health Apps

Open-source iOS companion app that brings Web Bluetooth to health PWAs on iPhone.

Your PWA works in Safari for everything — calls, breathing, AI. When a user needs to connect a BLE health device (EEG headband, heart rate monitor, pulse oximeter), they open the same URL in Haven Connect.

## Why This Exists

Apple doesn't support the Web Bluetooth API in Safari or any iOS browser. Chrome on iPhone uses WebKit too — same limitation. This means 1.5 billion iPhones can't connect BLE health devices to web apps.

Android and Chrome have supported Web Bluetooth since 2017. Without Haven Connect, the entire iOS ecosystem is excluded from web-based health device integration.

**Why we built this — and why we wish we didn't have to.** We are building global health infrastructure. Our mission is neutral access — every person, every device, every platform. We don't want to build something that greatly benefits one ecosystem over another just because one hasn't caught up yet. But that's exactly what's happening. Android and Chrome have supported Web Bluetooth since 2017. iOS has not. So we spent our valuable time and resources building Haven Connect — a bridge that shouldn't need to exist — because excluding 1.5 billion iPhone users from web-based health devices is not neutral, and waiting is not an option when lives are at stake.

## How It Works

```
Haven Connect (iOS app)
├── WKWebView (Apple's own WebKit engine)
├── CoreBluetooth bridge (Apple's own BLE framework)
├── Web Bluetooth polyfill (injected at page load)
└── Your PWA runs identically to Safari, but with BLE
```

The polyfill implements the standard [Web Bluetooth API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API). Same code that works in Chrome on Android works in Haven Connect on iOS. No code changes needed in your web app.

## Supported Devices

Any BLE (Bluetooth Low Energy) device that uses GATT:

- **MUSE EEG headband** — brain signal monitoring (4 EEG channels at 256Hz)
- **Heart rate monitors** — Polar, Garmin, generic BLE HR straps
- **Pulse oximeters** — SpO2 + heart rate
- **Blood pressure monitors** — BLE-enabled cuffs
- **Glucose monitors** — continuous glucose monitors (CGM)
- **Temperature sensors** — BLE thermometers
- **Any GATT device** — the bridge is generic

## Build & Run

### Requirements
- Xcode 15+
- iOS 16+ device (BLE doesn't work in simulator)
- Apple Developer account (free for testing on your device, $99/year for App Store)

### Steps
```bash
git clone https://github.com/paragon-dao/haven-connect-ios.git
cd haven-connect-ios
open HavenConnect.xcodeproj  # or use swift build
```

1. Open in Xcode
2. Select your iPhone as target
3. Set your signing team (free Apple ID works for testing)
4. Build & Run (Cmd+R)
5. Open any health PWA URL — Web Bluetooth now works

## For Web Developers

Your existing Web Bluetooth code works without changes:

```javascript
// This works in Chrome (Android) AND Haven Connect (iOS)
const device = await navigator.bluetooth.requestDevice({
    filters: [{ services: ['heart_rate'] }]
});
const server = await device.gatt.connect();
const service = await server.getPrimaryService('heart_rate');
const char = await service.getCharacteristic('heart_rate_measurement');
await char.startNotifications();
char.addEventListener('characteristicvaluechanged', (event) => {
    const heartRate = event.target.value.getUint8(1);
    console.log('Heart rate:', heartRate);
});
```

### Feature Detection

```javascript
if (navigator.bluetooth) {
    // Web Bluetooth available (Chrome, Haven Connect, Bluefy)
    connectDevice();
} else {
    // Safari — show "Open in Haven Connect" link
    showHavenConnectPrompt();
}
```

## Architecture

```
Web Page (your PWA)
  │
  ├── navigator.bluetooth.requestDevice()
  │     ↓ (polyfill intercepts)
  ├── window.webkit.messageHandlers.havenBLE.postMessage()
  │     ↓ (WKScriptMessageHandler)
  ├── BLEManager.requestDevice()
  │     ↓ (CoreBluetooth)
  ├── CBCentralManager.scanForPeripherals()
  │     ↓ (device found)
  ├── BLEManagerDelegate.didDiscoverDevice()
  │     ↓ (JavaScript callback)
  └── window.__havenBLE.onDeviceDiscovered()
        ↓ (resolves Promise)
      → Your code gets the BluetoothDevice object
```

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `HavenConnectApp.swift` | 11 | App entry point |
| `BrowserView.swift` | 81 | URL bar + BLE status bar + view model |
| `WebViewRepresentable.swift` | 257 | WKWebView + polyfill injection + bridge + JS escaping |
| `Bridge/BLEManager.swift` | 249 | CoreBluetooth manager + per-device targeting |
| `Bridge/WebBluetoothPolyfill.swift` | 247 | JavaScript Web Bluetooth API polyfill |
| `Tests/WebBluetoothPolyfillTests.swift` | 134 | Polyfill API surface + structure tests |
| `Tests/JSEscapeTests.swift` | 119 | XSS prevention + security boundary tests |
| `Tests/BLEManagerTests.swift` | 115 | BLE manager + view model tests |
| **Total** | **~1,213** | |

## Privacy

- **No data collection.** Haven Connect doesn't send data anywhere.
- **No analytics.** No tracking. No ads.
- **Open source.** Every line is auditable.
- **BLE data stays local.** The bridge passes data between your web page and the BLE device. Haven Connect doesn't store, intercept, or forward it.
- **Location permission:** iOS requires location permission for BLE device discovery. Haven Connect does not access your location.

## License

MIT — Use freely. Build health apps. Save lives.

## Part of the ParagonDAO Network

Haven Connect is infrastructure for the [ParagonDAO health economy](https://paragondao.org). Every builder's health PWA can use it for BLE device integration on iOS.

- [BAGLE SDK](https://github.com/paragon-dao/bagle-sdk) — Encode any biosignal to 128 coefficients
- [GLE App Template](https://github.com/paragon-dao/gle-app-template) — Clone-and-build PWA starter
- [HFTP Spec](https://github.com/paragon-dao/hftp-spec) — Network protocol specification
