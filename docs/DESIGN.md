# arriq: design spec

arriq is a macOS 13+ menu bar app. when you get home it wakes the room: lamp on, speaker on, tv on.
it looks and feels exactly like haptyq (reference: `~/Projects/haptyq`, esp. `docs/DESIGN.md` §1 and
`Sources/haptyq/Theme.swift`, `HaptyqSwitch.swift`, `SignalBar.swift`, `GadgetController.swift`, `GadgetView.swift`,
`MainWindow.swift`, `MenuBarIcon.swift`). copy those patterns, rename haptyq → arriq. read them first.

## 0. ground rules (all agents)

- swift 5 language mode (tools 5.9), macOS 13 target, command line tools only (no xcode). tests use swift-testing
  (`import Testing`, `@Test`, `#expect`).
- the mac is the machine to build on; reach it ONLY via `mcp__remote-devices__Control_your_Mac__osascript`
  (`do shell script "..."`). that tool dies after ~30s per call, so run builds like
  `cd ~/projects/arriq && nohup swift build --scratch-path .build/<agent> > /tmp/arriq-<agent>.log 2>&1 &` and poll the log.
  `export PATH=/usr/bin:/opt/homebrew/bin:/usr/local/bin:$PATH` first.
- write files via `mcp__remote-devices__device_bash` into `$HOME/mnt/arriq/...` (the project folder is mounted there;
  that shell is linux, it cannot compile). edit in place, never retype a whole file from earlier output.
- each agent builds with its own scratch path. only edit files you own (§8). `Model.swift` is frozen.
- no third-party dependencies, no python, no global installs: everything stays inside `~/projects/arriq`.
- no force unwraps on runtime data, no `try!`. logs via `os.Logger(subsystem: "io.github.arriq", category: ...)`.
- env var `ARRIQ_DRY_RUN=1`: drivers log "dry run: <what>" and return success without touching the network/bluetooth.
  tests and any verification run use it. never fire real devices unless the lead says so.
- keep comments short, explain why.

## 1. brand & visual language (same as haptyq)

lowercase only (every user-visible string). two colors only: black `#000000` and neon orange `#FF6B00`; secondary text
0.55, disabled 0.32, hairlines 0.16, hover/pressed 0.08 of the same orange. no grey/white/accent. monospaced system
font, sizes 22/13/11, regular+medium. 4pt grid, pad 16, row 32, radius 10 (controls 6). no emoji, gradients, shadows,
sf symbols in content. force dark appearance. only functional motion (pulse dot 1→0.16 over 180ms; device squares
fill in sequence when a trigger runs). put the accent in ONE token (`Theme.fg`) so it can be swapped to red later.

## 2. behaviour

### 2.1 presence rules (pure function, unit tested)
`func reduce(_ s: PresenceState, _ e: PresenceEvent, now: Date, config: PresenceConfig) -> (PresenceState, trigger: Bool)`
in `Presence.swift`. the phone arrival is the anchor of every trigger.
- `phoneLeft`: phoneHome=false, armedUntil=nil.
- `macHome(b)`: macHome=b. if b and armedUntil is in the future and phoneHome==true → trigger (rule b), armedUntil=nil.
  if !b → armedUntil=nil.
- `phoneArrived`: if phoneHome==true already → ignore (duplicate). else phoneHome=true; if macHome → trigger (rule a);
  else armedUntil = now + pairWindow (waiting for the laptop).
- `tick`: if armedUntil <= now → armedUntil=nil.
- a trigger only counts if `lastTrigger` is nil or older than `cooldown`; when it counts set lastTrigger=now. inside
  the cooldown nothing fires and armedUntil is cleared.
- mac coming home alone (phone away or already home) never triggers.
tests: a) phone arrives, mac home → trigger. b) both away, phone arrives, mac home 5 min later → trigger on the mac event.
c) same but mac home after the window → no trigger. d) duplicate arrived → once. e) cooldown blocks, then allows.
f) mac home alone → none. g) phone arrives while mac away, mac still away at window end → none, armed cleared.

### 2.2 phone signal
phone posts `arrived` / `left` as the body of an https POST to `https://ntfy.sh/<settings.phoneTopic>` from its own
geofence automation (ios shortcuts "arrive/leave"; android tasker/macrodroid). mac subscribes with a streaming GET
`https://ntfy.sh/<topic>/json?since=5m` (newline-delimited json; keep `event == "message"` only, body in `message`, unix
`time`, dedupe by `id`, ignore messages older than 5 minutes). reconnect with backoff 1s…60s, mark `listening`
false while down. re-subscribe on `NSWorkspace.didWakeNotification`. pure parse function `parseNtfyLine(_:) -> NtfyMessage?`
unit tested (open/keepalive events, junk, missing fields).

### 2.3 is the mac home
`HomeDetector`: default gateway ip from `/sbin/route -n get default`, its mac from `/usr/sbin/arp -n <ip>`
(normalize: lower-case, each octet zero padded). macHome = mac == `settings.homeGatewayMAC`. no saved mac → false.
poll every 15s, also on `NWPathMonitor` updates and wake. emit `.macHome(b)` only on change. `markHome()` saves the
current gateway mac into settings (via `onSettingsChange`). no location permission is needed. parsers are pure and tested.

### 2.4 devices (`Drivers/`), run concurrently after each device's `delaySeconds`, each independent, errors never block others
- **lamp** (govee H6076, lan api, udp). scan: multicast `{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}` to
  239.255.255.250:4001, listen on 4002 (bsd sockets, SO_REUSEADDR+SO_REUSEPORT, 3s timeout); reply has `msg.data.ip`.
  prefer `settings.lampIP` (verify with unicast `devStatus` to ip:4003, answer on 4002); on failure rescan and update
  `lampIP`. then to ip:4003: `turn` value 1, `brightness` value N, `colorwc` with `color` r/g/b 0 and `colorTemInKelvin` K
  (warm white). command json builders are pure and tested.
- **speaker** (ue boom 3, ble wake). CoreBluetooth central: if `IOBluetoothDevice(addressString:)?.isConnected()` is true
  → done. else scan up to 15s for a peripheral whose advertisement has service uuid `FE61` OR manufacturer data
  containing the 6 address bytes of `settings.speakerAddress`; connect; discover service `000061FE-0000-1000-8000-00805F9B34FB`
  and characteristic `C6D6DC0D-07F5-47EF-9B59-630622B01FD3`; write (with response) = the host bluetooth address bytes
  (`IOBluetoothHostController.default().addressAsString()`) followed by `0x01`; then wait up to 8s for the classic
  connection (`isConnected()`), success either way if the write worked. pure helpers (address→bytes, payload, advert match) tested.
- **tv** (samsung, smartthings cloud). token in the keychain (service `arriq`, account `smartthings`), never in
  settings or logs. `GET https://api.smartthings.com/v1/devices` lists devices (for the picker);
  `POST /v1/devices/<id>/commands` body `{"commands":[{"component":"main","capability":"switch","command":"on"}]}`,
  `Authorization: Bearer <token>`. status `notSetUp` until token and device id exist. 10s timeout.
- every attempt appends a lower-case `LogLine` ("lamp on · 10.10.x.x", "speaker failed · not found").
  statuses go working → done/failed, back to ready after 20s.

### 2.5 engine
`ArriqEngine` (skeleton in `ArriqEngine.swift`, signatures fixed). owns settings copy, presence state, ntfy client,
home detector, drivers. `simulate(_:)` feeds the same path as real events. when `settings.enabled` is false nothing
triggers (state is still tracked). `onFire` fires at every trigger. settings storage:
`~/Library/Application Support/arriq/settings.json` via `SettingsStore.load()/save(_)` (kit agent, tolerant decode).
`LaunchAtLogin` via `SMAppService.mainApp`, returning a lower-case error string.

## 3. app (target `arriq`, ui agent)

structure like haptyq: `@main ArriqApp` + `NSApplicationDelegateAdaptor`, `MenuBarExtra(.window)`, `@MainActor AppModel`
(owns `Settings`, `ArriqEngine`, `EngineSnapshot`, `GadgetController`; debounced save 300ms; sets
`engine.onChange/onSettingsChange/onFire`), `Theme.swift`, `ArriqSwitch.swift`, `SignalBar.swift` (3-cell variant for
device state), `MenuBarIcon.swift`, `GadgetController/GadgetView`, `MainWindow.swift`, `PopoverView.swift`.
tagline: `the room wakes up when you do.` product name `arriq`.

- **menu bar glyph**: custom template NSImage 18×18, the doorway: open-floored casing (stroke 1.5), the door swung in
  (outline 1.2) and the lit gap as the one solid shape; drawn as one layer, whole glyph at 0.32 when the master switch is off.
- **popover** (300 wide): header `arriq` + master switch; tagline; rows `phone  home|away|unknown`,
  `laptop  home|away`; (when armed: `waiting for laptop · 12:40`); 3 device rows (name left, 3-cell status bar +
  `test` text button right: notSetUp=dash, ready=1 cell, working=2, done=3, failed=dash outline); `fire now` text
  button; footer `customize…`, `quit`, version.
- **window** (~620×460, same chrome as haptyq's window: transparent titlebar, full size content, dark, black, not resizable,
  activation policy .regular while visible, frame autosave). header: `arriq` + status line (priority: `set your home network`
  / `phone not linked` / `paused` / `listening`) + master switch.
  - left **scene** (~300×300): dashed ring = home. phone dot and laptop dot sit inside the ring when home, outside when
    away, 16% when unknown; a dashed arc between them while armed. below: three 28pt squares labelled lamp/speaker/tv
    that fill in sequence (respecting each delay) when a trigger runs, outline otherwise; readout line (11pt):
    `phone away · laptop home` / `armed · 11:42 left` / `fired 18:03`.
  - right **inspector** with text tabs `devices · phone · home · log` (selected tab has a 1px orange underline):
    - devices: three rows with status bar; selecting one shows `on arrival` switch, `delay` slider 0–120s (haptyq's
      custom slider style), lamp: `brightness` 1–100, `warmth` 2000–9000k; tv: `smartthings token` secure field + `save`
      (token goes straight to `engine.setSmartThingsToken`, field clears, shows `token saved`), `pick your tv`
      list from `listSmartThingsDevices()`; speaker: address shown read-only; every device has `test`.
    - phone: two copyable lines `arrive` and `leave` (url + body), 4 short lowercase setup steps for ios shortcuts and
      android, `heard from phone · 12:03` or `nothing yet`, `cooldown` and `pair window` sliders.
    - home: `this network is home` button (`engine.markHome()`), shows saved gateway and the current one, and `home / away` now.
    - log: monospaced scroll list of `LogLine`s, `HH:mm:ss text`.
  - footer (11pt): `desktop gadget`, `float`, `launch at login` switches, `quit`, version.
- **gadget** 140×140 as in haptyq: top-left `arriq`, state word 22pt: `home` / `away` / `armed` (laptop pending) / `off`;
  pulse dot flashes on `onFire`; bottom-left caption `phone home · laptop away`; click toggles master; right-click:
  `hide gadget`, `float above windows`, `customize…`, `quit`.
- previews/tests must run with `ARRIQ_DRY_RUN=1`.

## 4. release (release agent)
`Resources/Info.plist` (id `io.github.arriq`, LSUIElement true, LSMinimumSystemVersion 13.0, version from `VERSION`,
`NSBluetoothAlwaysUsageDescription` = "arriq wakes your speaker when you get home.", `NSLocalNetworkUsageDescription` =
"arriq talks to your lamp on your home network."), `scripts/make-icon.swift` (the doorway: dark wall, door swung open, orange light fanning across the floor,
like haptyq's make-icon), `scripts/bundle.sh` (same shape as haptyq's: release build, assemble `dist/arriq.app`, ad-hoc
sign, zip, sha256; `set -euo pipefail`), lowercase `README.md`, `LICENSE` (mit). copy the structure of haptyq's scripts.

## 5. tests (`Tests/ArriqKitTests`, kit agent)
presence (§2.1 a–g), settings (defaults, round-trip, `{}`, garbage values, unknown keys, clamping), ntfy parse,
gateway/arp parse, govee json builders, ble helpers, ntfy dedupe/stale logic. all pure, no network.

## 6. ownership
| owner | files |
|---|---|
| lead | `Package.swift`, `Sources/ArriqKit/Model.swift`, `docs/` |
| kit agent | `Sources/ArriqKit/**` except Model.swift, `Tests/**` |
| ui agent | `Sources/arriq/**` |
| release agent | `scripts/**`, `Resources/**`, `README.md`, `LICENSE`, `.gitignore`, `VERSION` |
