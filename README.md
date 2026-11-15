# arriq

the room wakes up when you do.

arriq is a macos menu bar app. when you get home it turns on your lamp, your speaker and your tv, so the room is ready before you reach the door. it looks and works like its sibling app haptyq.

## what it does

- **arrival**: your phone posts `arrived` when its geofence says you are home. if your mac is already on your home network, arriq fires right away. the first start adopts the current network as home; change it in the home tab.
- **pairing**: if the mac is not home yet, arriq waits a short window (adjustable under phone) for the laptop to join your network, then fires.
- **devices**
  - lamp: a govee h6076 on your local network, over udp. turned on, with brightness and warmth set.
  - speaker: a ue boom 3, woken over bluetooth low energy and connected classically.
  - tv: a samsung tv through the smartthings cloud.

each device can have its own delay, and every attempt is written to the log.

## requirements

- macos 13 or later.
- bluetooth, and a home network with your lamp on it. on the lamp, govee home › lamp › settings › lan control must be on.
- for the tv: a smartthings account with a personal access token.
- for arrival: an ios or android phone that can send an http post when it enters or leaves an area.

## install

1. download `arriq-<version>.zip` from the latest release and unzip it.
2. move `arriq.app` to `/applications`.
3. open it for the first time (see below).

### first open for ad-hoc builds

release builds are signed ad-hoc, not with an apple developer identity, so gatekeeper will ask once.

- macos 15 or later: try to open it, then go to system settings › privacy & security and click "open anyway".
- macos 13 or 14: right-click `arriq.app`, choose "open", then confirm.
- or run `xattr -dr com.apple.quarantine /Applications/arriq.app` in terminal.

### grant bluetooth and local network

arriq asks for two permissions the first time it needs them:

- **bluetooth**: to wake the speaker.
- **local network**: to find and talk to the lamp.

if you denied one, turn it on in system settings › privacy & security, then reopen arriq. ad-hoc builds are not tied to a developer identity, so macos may ask again after an update. toggle arriq off and on in that pane.

## phone setup

arriq listens on a private ntfy.sh topic. your phone posts two words to it: `arrived` and `left`. pick a long random topic name (for example, 20 random letters), enter it in arriq under phone, and keep it secret: anyone who knows the topic can post to it.

the arriq window shows the exact url and body for each event under phone, ready to copy.

**ios (shortcuts)**

1. open shortcuts › automation › new, choose "arrive" and pick your home area.
2. add "get contents of url": url is your topic url, method post, request body json, add a new field: text, key `a`, value `arrived`.
3. turn off "ask before running". repeat with "leave" and the value `left`.
4. arriq also accepts a plain text body.

**android (tasker, macrodroid or similar)**

1. create a location profile for home, entering and leaving.
2. add an http request action: post to your topic url, body `arrived` on enter, `left` on exit.

after a test run, the phone tab in arriq shows `heard from phone` with the time.

## smartthings token

1. in your smartthings account, create a personal access token.
2. open arriq › devices › tv, paste the token into `smartthings token` and press `save`.
3. press `pick your tv` to choose the device.

the token is stored in the macos keychain. it is never written to settings or to the log.

new smartthings tokens expire after 24 hours. if the tv fails with `token expired`, paste a fresh one.

## music

open arriq › devices › speaker, turn on `play music`, paste a spotify playlist, album or track link, and set the volume and shuffle. when the speaker turns on, arriq makes it the mac's audio output and starts the link in the spotify app. the first time, macos asks to let arriq control spotify; if you said no, allow it in system settings › privacy › automation › arriq.

## tv scene

open arriq › devices › tv, turn on `tv scene` and paste a youtube link. after the tv turns on, arriq starts the video. adding the `tv address` (the tv's ip on your network) makes this reliable; without it arriq only opens the youtube app.

## privacy

the phone never sends location. it only posts the words `arrived` or `left` to your secret ntfy.sh topic. arriq detects home by reading the mac's default gateway and its hardware address, which needs no location permission. nothing leaves your mac except the requests to the lamp, the speaker, smartthings and the ntfy.sh topic.

## build from source

arriq is a swift package. with the command line tools installed (`xcode-select --install`):

    git clone <this repository url>
    cd arriq
    scripts/bundle.sh
    open dist/arriq.app

to run the tests:

    swift test

add `--debug` to `scripts/bundle.sh` for a debug build. the output is `dist/arriq.app` and `dist/arriq-<version>.zip`. the version lives in `VERSION` at the repo root.

apps you build yourself are not quarantined, so gatekeeper will not block them.

## license

mit. see [license](LICENSE).
