# Haven Connect — Bluetooth Health Device Companion for iOS

Native iOS companion app for Bluetooth health devices. Connects BLE medical devices to guided health experiences and syncs data to Apple Health automatically.

## What It Does

Haven Connect is a **Bluetooth health device companion**. It connects BLE medical devices — heart rate straps, pulse oximeters, EEG headbands, motion sensors — to guided health experiences on iOS, with automatic Apple Health sync.

Every experience in Haven Connect requires a Bluetooth device. If it works without one, it belongs in Safari, not here.

- **BLE bridge** — Connects Bluetooth health devices to guided health experiences on iOS (Safari can't do this).
- **HealthKit sync** — Heart rate, HRV, and SpO2 from your BLE devices automatically written to Apple Health.
- **GATT intelligence** — Knows how to parse data from standard health devices (HR straps, pulse oximeters).
- **Guided experiences** — Heart rate monitoring, gait analysis, breathing coherence, SpO2 tracking — each requiring a paired device.
- **Privacy-first** — No data collection. No analytics. BLE data stays on-device.

## Why This Exists

Apple doesn't support the Web Bluetooth API in Safari. This means 1.5 billion iPhones can't connect BLE health devices to web-based health experiences. Haven Connect bridges that gap with native CoreBluetooth — and goes further by adding HealthKit integration and GATT device intelligence that web apps can't do alone.

**If Safari adds Web Bluetooth**, Haven Connect still has value: automatic HealthKit write-through, GATT device profiles, and (coming in v2) on-device biosignal encoding via GLE.

## Architecture

```
Haven Connect (iOS)
├── LauncherView         — Health experiences that require BLE devices
├── AppWebView           — Opens a health experience with BLE bridge active
├── WhitelistedWebView   — WKWebView + polyfill (whitelisted domains only)
├── BLEManager           — CoreBluetooth bridge (scan, connect, GATT ops)
├── GATTProfiles         — Parses HR, HRV, SpO2 from standard BLE services
├── HealthKitManager     — Writes BLE health data to Apple Health
├── DevicesView          — Native device management screen
├── HealthSummaryView    — Native health data summary screen
└── AppRegistry          — Whitelist of approved health experience URLs
```

### Three Tabs

1. **Apps** — Health experiences, each requiring a paired BLE device.
2. **Devices** — Connected BLE devices. Status, disconnect controls.
3. **Health** — Recent readings written to HealthKit from your BLE devices.

### Security Model

- URL whitelist enforced at the native layer — polyfill only injects on approved domains.
- Non-whitelisted URLs open in Safari, not in the app.
- JavaScript string escaping prevents XSS from malicious BLE device names.
- No arbitrary URL navigation. No URL bar.

## Supported Devices

Any BLE (Bluetooth Low Energy) device using standard GATT health services:

- **Heart rate monitors** — Polar H10, Movesense, generic BLE HR straps
- **Pulse oximeters** — SpO2 + heart rate (GATT 0x1822)
- **EEG headbands** — Muse 2/S (custom GATT)
- **Any GATT device** — generic BLE bridge works for all

## Build & Run

### Requirements
- Xcode 15+
- iOS 16+ device (BLE doesn't work in simulator)
- Apple Developer account (free for testing, $99/year for App Store)

### Steps
```bash
git clone https://github.com/paragon-dao/haven-connect-ios.git
cd haven-connect-ios
open Package.swift  # Opens in Xcode
```

1. Open in Xcode
2. Select your iPhone as target
3. Set your signing team
4. Enable HealthKit capability in Signing & Capabilities
5. Build & Run (Cmd+R)

## Files

| Directory | Files | Purpose |
|-----------|-------|---------|
| `HavenConnect/` | `HavenConnectApp.swift` | App entry — TabView with 3 tabs |
| `Views/` | `LauncherView.swift` | Health experiences requiring BLE devices |
| | `AppWebView.swift` | Full-screen web view for launched apps |
| | `DevicesView.swift` | Native BLE device management |
| | `HealthSummaryView.swift` | Native health data summary |
| `Bridge/` | `BLEManager.swift` | CoreBluetooth manager |
| | `WebBluetoothPolyfill.swift` | JavaScript Web Bluetooth API polyfill |
| | `WhitelistedWebView.swift` | WKWebView with whitelist + HealthKit auto-write |
| `Health/` | `HealthKitManager.swift` | HealthKit read/write for HR, HRV, SpO2 |
| | `GATTProfiles.swift` | BLE GATT parsing for health devices |
| `Models/` | `HealthApp.swift` | Health app data model |
| | `AppRegistry.swift` | Whitelist of approved Paragon network apps |
| `Tests/` | 3 test files | BLE, polyfill, security, GATT, registry tests |

## For Web Developers

Your existing Web Bluetooth code works without changes in Haven Connect:

```javascript
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

**Bonus**: Heart rate data is automatically written to Apple Health — no extra code needed.

## Roadmap

- **v1** (current): BLE device companion + HealthKit write + native device/health screens
- **v1.1**: On-device GLE encoding (Swift port). Coefficients stored in Keychain.
- **v2**: Sandboxed biometric identity. Web apps request similarity checks, never see raw coefficients. Live Activities on Dynamic Island.
- **v3**: Health intelligence features built on clinically validated GLE encoding.

## Privacy

- **No data collection.** Haven Connect doesn't send data anywhere.
- **No analytics.** No tracking. No ads.
- **Open source.** Every line is auditable.
- **BLE data stays local.** Passed between web app and BLE device. Haven Connect doesn't store or forward it.
- **HealthKit data stays on-device.** Written to Apple Health, controlled by the user.

## License

MIT — Use freely. Build health apps. Save lives.

## Part of the Paragon Network

Haven Connect is infrastructure for the [Paragon health economy](https://paragondao.org).

- [BAGLE SDK](https://github.com/paragon-dao/bagle-sdk) — Encode any biosignal to 128 coefficients
- [GLE App Template](https://github.com/paragon-dao/gle-app-template) — Clone-and-build PWA starter
- [HFTP Spec](https://github.com/paragon-dao/hftp-spec) — Network protocol specification
