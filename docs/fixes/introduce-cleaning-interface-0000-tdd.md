# BusyLight Network Scan TDD

## Task Summary
- Bug: the macOS BusyLight client can remain at `Device: Offline` and skip sending state changes when no WLED device address is configured and Bonjour discovery does not find the light.
- Expected behavior: automatic discovery must scan the local network for WLED lights because common installs have one light, with two to four at most.
- Follow-up requirement: the interface should only surface online devices. Stale offline configured devices should not remain visible, and discovery/recovery should happen as soon as the app needs to send a state.
- Follow-up evidence: app logs showed `http://192.168.86.33:80/json/info` timing out from BusyLight while the same device was reachable in a browser.

## Assumptions
- `app.wled_enable_discovery` controls automatic WLED discovery, including Bonjour and subnet scan paths.
- Manual configured addresses remain supported and should be merged with auto-discovered devices.
- A WLED device is verified by a successful `/json/info` response with WLED-like metadata.

## Target Files
- `macos-agent/Sources/BusyLightCore/Network/NetworkClient.swift`
- `macos-agent/Sources/BusyLightCore/Network/DeviceDiscovery.swift`
- `macos-agent/Sources/BusyLightCore/Network/HTTPAdapter.swift`
- `macos-agent/Sources/BusyLightCore/Network/WLEDTypes.swift`
- `macos-agent/Tests/BusyLightCoreTests/NetworkClientDiscoveryTests.swift`

## Planned Test Scope
- Red: when Bonjour/mDNS returns no devices, `NetworkClient.connect()` must use subnet scanning to find a WLED device and persist the discovered address.
- Red: after subnet discovery, `NetworkClient.sendState(_:)` must post the configured preset to the scanned WLED address instead of returning early with no devices.

## Red
- Added `NetworkClientDiscoveryTests.testConnectScansLocalNetworkWhenBonjourFindsNoDevices`.
- Added `NetworkClientDiscoveryTests.testSendStatePostsToSubnetDiscoveredDevice`.
- Added `NetworkClientDiscoveryTests.testSubnetScanReplacesStaleConfiguredAddress` for the reported stale DHCP example where the app keeps trying `192.168.86.247` while the light is at `192.168.86.33`.
- Added `NetworkClientDiscoveryTests.testConnectDoesNotExposeOfflineConfiguredAddressWhenDiscoveryFindsNothing`.
- Added `NetworkClientDiscoveryTests.testSendStateScansImmediatelyWhenNoOnlineDevicesExist`.
- Added `HTTPAdapterTests.testRawHTTPParametersBypassProxyPACResolution`.
- Added `HTTPAdapterTests.testRawHTTPResponseIsCompleteWhenContentLengthBodyHasArrived`.
- Added `HTTPAdapterTests.testRawHTTPResponseWaitsForFullContentLengthBody`.
- Added `NetworkClientDiscoveryTests.testConnectUsesVerifiedConfiguredAddressBeforeSubnetScan`.
- Added `NetworkClientDiscoveryTests.testConnectUsesProbeHTTPClientForConfiguredAddressVerification`.
- Added `NetworkClientDiscoveryTests.testSubnetScanPrioritizesConfiguredSubnetWhenConfiguredAddressIsOffline`.
- Added `NetworkClientDiscoveryTests.testSubnetScanCandidateListStartsWithPriorityAddress`.
- Added `NetworkClientDiscoveryTests.testConcurrentConnectCallsShareSingleDiscoveryWork`.
- Added callback assertion to prove `onDeviceStatusChanged` does not deliver stale offline devices to the UI.
- Added `ConfigurationManagerTests.testDefaultWledHttpTimeoutAllowsSlowEsp32Responses`.
- Added `ConfigurationManagerTests.testStoredLowWledHttpTimeoutMigratesToMinimum`.
- Added `InfoPlistNetworkPermissionTests.testAppInfoPlistDeclaresLocalNetworkAccessForWLED`.
- Expected failure: production `NetworkClient` only used Bonjour and configured addresses; it had no subnet scanner injection or local-network scan fallback.
- Expected follow-up failure: production `NetworkClient` still exposed offline manual devices and `sendState(_:)` returned immediately when no devices were known.
- Actual first focused command: `swift test --filter NetworkClientDiscoveryTests`.
- Actual failure summary: the local Swift toolchain failed while compiling existing XCTest-based tests with `no such module 'XCTest'`, so the test runner could not reach the intended production-code failure in this environment.

## Green
- Added injectable network seams:
  - `WLEDHTTPClient`
  - `WLEDDeviceDiscovering`
  - `WLEDDeviceScanning`
- Added `LocalNetworkScanner`, which enumerates active non-loopback private IPv4 interfaces and probes each local `/24` candidate for WLED `/json/info`.
- Updated `NetworkClient.connect()` to:
  - run Bonjour discovery first,
  - run subnet scan whenever WLED discovery is enabled,
  - replace stale configured addresses with discovered live WLED addresses,
  - fall back to manual configured addresses only when discovery finds nothing.
- Updated `NetworkClient.sendState(_:)` and health checks to use the injectable HTTP client.
- Updated `NetworkClient` to keep `devices` online-only:
  - stale configured addresses are verified before use,
  - failed sends remove devices from the published list,
  - health checks prune offline devices instead of surfacing them.
- Added forced send-time recovery: if no online devices are known, `sendState(_:)` runs discovery immediately before giving up.
- Reduced background rediscovery throttle from 60 seconds to 5 seconds and made health monitoring run an immediate first check.
- Updated the menu wiring so it displays only an online device address; otherwise it shows `Searching` rather than stale configured or offline device text.
- Raised the app WLED HTTP timeout default/minimum to 2500ms and normalize saved lower values upward.
- Raised Bonjour WLED verification to a 2500ms one-shot probe and gave resolved services 3 seconds before early completion.
- Raised subnet scan probes from 250ms to 1000ms.
- Added `NSLocalNetworkUsageDescription` and `NSBonjourServices` to the app `Info.plist` so macOS can authorize LAN HTTP and Bonjour access from the bundled app.
- Updated raw WLED HTTP connections to use `NWParameters.tcp` with `preferNoProxies = true`; a local Swift probe showed the same WLED request spent about 5.3 seconds in proxy/PAC resolution without this flag and about 50ms with it.
- Updated raw HTTP reads to complete as soon as `Content-Length` bytes or a terminating chunked body has arrived, instead of waiting for TCP EOF.
- Updated numeric IP handling to create explicit `NWEndpoint.Host.ipv4` or `.ipv6` endpoints before falling back to hostname resolution.
- Updated `NetworkClient.connect()` to verify configured addresses before Bonjour/subnet scans and skip the broad scan when a configured device is online.
- Split WLED GET probes from state POST sends in `NetworkClient` so configured-address and health checks use a one-attempt probe client while state sends keep the normal HTTP client.
- Added `NetworkClient.connect()` coalescing so startup discovery and the first state send share one active connection attempt instead of launching parallel discovery work.
- Updated subnet scan candidate ordering so a configured priority address is tested first and its subnet is searched before other local subnets.
- Deferred the global-hotkey accessibility prompt and switched it to the native non-blocking `AXIsProcessTrustedWithOptions` prompt so a rebuilt app cannot block WLED networking before initialization.

## Refactor Notes
- `HTTPAdapter` now accepts configurable retry count so subnet scan can use a short timeout with one attempt per candidate.
- `HTTPAdapter.makeRawHTTPParameters()` exists for regression coverage of the proxy/PAC bypass setting.
- `DeviceDiscovery` now conforms to `WLEDDeviceDiscovering` without changing its Bonjour behavior.
- Deduplication keeps one device per WLED MAC address or address.

## Verification
- `swift test --filter NetworkClientDiscoveryTests`
  - Result: blocked by local Command Line Tools-only Swift environment with `no such module 'XCTest'`.
- `swift build`
  - Result: passed.
- `swift test --filter NetworkClientDiscoveryTests` after online-only tests were added
  - Result: still blocked by local Command Line Tools-only Swift environment with `no such module 'XCTest'`.
- `./build.sh test`
  - Result: passed by following repo policy and skipped tests because full Xcode is not installed.
- `./build.sh`
  - Result: passed; built debug binary, assembled `BusyLight.app`, converted icon, and applied ad-hoc codesign.
- `swift build` after online-only UI changes
  - Result: passed.
- `./build.sh` after online-only UI changes
  - Result: passed; rebuilt and re-signed `BusyLight.app`.
- `./build.sh test` after online-only UI changes
  - Result: passed by following repo policy and skipped tests because full Xcode is not installed.
- `curl -sS -m 5 -o /tmp/busylight-wled-info.json -w 'http_code=%{http_code} time_total=%{time_total}\n' http://192.168.86.33/json/info`
  - Result: `http_code=200 time_total=0.046699`; the WLED endpoint is reachable from the shell, so app-level local-network permission/timeout settings were the likely failure points.
- `swift build` after timeout and Info.plist changes
  - Result: passed.
- `swift test --filter ConfigurationManagerTests`
  - Result: still blocked by local Command Line Tools-only Swift environment with `no such module 'XCTest'`.
- `swift test --filter InfoPlistNetworkPermissionTests`
  - Result: still blocked by local Command Line Tools-only Swift environment with `no such module 'XCTest'`.
- `plutil -lint macos-agent/Sources/BusyLight/Resources/Info.plist BusyLight.app/Contents/Info.plist`
  - Result: passed.
- `plutil -p BusyLight.app/Contents/Info.plist | rg -n "NSLocalNetwork|NSBonjour|_http"`
  - Result: confirmed bundled app contains `NSLocalNetworkUsageDescription` and `_http._tcp.` in `NSBonjourServices`.
- `git diff --check`
  - Result: passed.
- `swift - <<'SWIFT' ... URLSessionConfiguration.ephemeral with proxy disabled ...`
  - Result: timed out after about 2.51s against `http://192.168.86.33/json/info`; disabling URLSession proxy settings alone did not solve the app path.
- `swift - <<'SWIFT' ... NWConnection(host: .ipv4(192.168.86.33), using: .tcp) ...`
  - Result: TCP ready took about 5.36s and response bytes arrived after 5.45s, proving Network.framework was delayed before the request body was sent.
- `swift - <<'SWIFT' ... NWParameters.tcp; parameters.preferNoProxies = true ...`
  - Result: TCP ready in about 20ms and response bytes by about 49ms.
- `swift build` after raw HTTP/proxy, candidate ordering, and connect coalescing changes
  - Result: passed.
- `swift test`
  - Result: still blocked by local Command Line Tools-only Swift environment with `no such module 'XCTest'`.
- `./build.sh` after raw HTTP/proxy, candidate ordering, and connect coalescing changes
  - Result: passed; rebuilt and re-signed `BusyLight.app`.
- Installed rebuilt `BusyLight.app` into `/Applications/BusyLight.app` and `/Users/dralquinta/Documents/DevOps/busy-light/BusyLight.app`, refreshed LaunchServices, and launched `/Applications/BusyLight.app`.
  - Result: live logs for PID 21584 show `network_client.connect.joined`, one configured-device verification, `http.get.info.success [latency_ms=141 address=192.168.86.33]`, `network_client.connect.completed [total_devices=1]`, UI `online=1 offline=0 total=1`, and `http.post.state.success` to `192.168.86.33`.
  - Follow-up health checks stayed online with GET latencies around 58-95ms.
- `swift build` after probe-client and non-blocking accessibility prompt changes
  - Result: passed.
- `swift test` after probe-client tests were added
  - Result: still blocked by local Command Line Tools-only Swift environment with `no such module 'XCTest'`.
- `./build.sh` after probe-client and non-blocking accessibility prompt changes
  - Result: passed; rebuilt and re-signed `BusyLight.app`.
- Installed and launched the final rebuilt app from `/Applications/BusyLight.app`.
  - Result: live logs for PID 26921 show startup was not blocked by accessibility permission, `network_client.connect.joined`, configured verification of `192.168.86.33` in 222ms, UI `online=1 offline=0 total=1`, successful unknown-state POST in 81ms, native accessibility permission log at 5 seconds, then calendar-driven busy POST in 67ms.
- `plutil -lint macos-agent/Sources/BusyLight/Resources/Info.plist BusyLight.app/Contents/Info.plist`
  - Result: passed after final rebuild.
- `git diff --check`
  - Result: passed after final rebuild.

## Root Cause
- Device discovery depended on Bonjour/mDNS plus previously configured addresses. If the WLED light moved from a stale DHCP address such as `192.168.86.247` to `192.168.86.33` and Bonjour did not find it, the client kept a stale offline device list and `sendState(_:)` had no live target.
- The UI consumed the full `NetworkClient.devices` list and the configured address separately, so stale offline devices and addresses could remain visible even when they were not usable.
- The app bundle did not declare local-network access metadata, which can cause LAN requests from the app process to time out on modern macOS even when curl/browser access works.
- The app also treated 500ms as the default WLED timeout, which is too low for some ESP32/WLED `/json/info` responses and can be persisted in existing installs.
- The raw Network.framework replacement still allowed system proxy/PAC processing. On this machine that delayed direct LAN TCP readiness beyond the BusyLight timeout, causing retries and broad subnet scans even though the WLED device was healthy.
- The raw HTTP reader waited for TCP EOF instead of HTTP framing, so a valid `Content-Length` response could be delayed until timeout if the socket did not close promptly.
- Startup launched a state send while discovery was still running, causing duplicate recovery/connect work. That made the failure look like the app ignored the known configured IP and immediately started scanning.
- The custom Accessibility `NSAlert.runModal()` was able to block app initialization after a rebuild changed the app identity for TCC. That could prevent network initialization before the user dismissed a hotkey-permission prompt.

## Final Status
- Source fix implemented and build verified.
- The interface now receives only online devices from `NetworkClient`; no online device yields `Searching`, not stale/offline device entries.
- Recovery now runs immediately when a state send has no online target, and background health recovery retries every 5 seconds.
- WLED requests now tolerate slower ESP32 responses, and the bundled app includes local-network privacy metadata.
- WLED raw TCP requests now prefer no proxy/PAC, complete on HTTP framing, and verify configured online devices before scanning.
- Accessibility permission checks no longer block the WLED connection path.
- Live installed app verification shows `192.168.86.33` online, only one online device in the UI, successful state POSTs, and healthy subsequent pings.
- Focused and full automated tests could not execute in this environment because XCTest is unavailable under the installed Command Line Tools-only toolchain. The new regression tests should run under a full Xcode installation.
