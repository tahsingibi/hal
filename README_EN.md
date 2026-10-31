<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Resources/Icons/hal-white.svg">
  <img alt="Hâl" src="Resources/Icons/hal.svg" width="96">
</picture>

# Hâl

**A personal status dashboard that lives in your macOS menu bar.**

Your quotas, prayer times, focus, calendar, health and payments in a single window. Leaves no icon in the Dock.

English · [Türkçe](README.md)

macOS 14+ · MIT License

</div>

---

## Table of contents

- [Highlights](#highlights)
- [Quick start](#quick-start)
- [Menu bar](#menu-bar)
- [Modules](#modules)
- [Tools](#tools)
- [Notifications](#notifications)
- [Privacy: what does the app read?](#privacy-what-does-the-app-read)
- [Updates and releases](#updates-and-releases)
- [Code signing](#code-signing)
- [Release notes](#release-notes)
- [Development](#development)
- [About](#about)

## Highlights

- **One window, seven tabs:** Today, Focus, Quotas, Worship, Calendar, Health, Payments.
- **Modular:** Turning a module off also stops its data source and notifications.
- **Quotas:** Track Claude, Codex and Grok usage from the menu bar.
- **Prayer times and tracking:** Next prayer, daily count and an unbroken streak.
- **Automatic focus tracking:** Browser URLs are never read, and no permission is required.
- **Tools:** Downloader, Ports, Homebrew, a volume mixer and updates.
- **Turkish and English UI;** the language switches instantly.
- **Not sandboxed, fully local;** your data stays on your Mac.

## Quick start

The ready-to-use build is the DMG on [Releases](https://github.com/tahsingibi/hal/releases/latest). The published release is **1.1.0** (31 October 2026).

1. Open the DMG and drag **Hal** to **Applications**.
2. First launch: System Settings → Privacy & Security → **Open Anyway**.

macOS 14+ · Apple Silicon and Intel. The package is ad-hoc signed and not notarized.

Building from the repo is the development path:

```bash
./build.sh
open Hal.app
```

`./build.sh --dmg` packs that same build as `dist/Hal-<version>.dmg` and writes a SHA-256 beside it. The project `Hal.app` stays signed with the development certificate. `Hal.app`, `.build` and `dist/` are build output and are not committed.

**Naming:** The display name is **Hâl**. The file name, bundle identifier and data folder use the ASCII spelling **Hal**:

| What | Value |
| --- | --- |
| App | `Hal.app` |
| Bundle identifier | `dev.sungur.Hal` |
| Data folder | `~/Library/Application Support/Hal` |

**Brand:** A gauge ring that opens to the right, with a location dot inside. Source: `Resources/Icons/hal.svg`. The menu bar drawing lives in `Sources/BrandIcons.swift`.

### Language

On first launch the Mac's language is used: Turkish if the system language is Turkish, English otherwise. If no language key is stored, the system language still applies. Settings › General › Language offers *System*, *Türkçe* or *English*; the choice applies immediately with no relaunch.

- Dates and day names follow the selected language. Time stays in 24-hour format.
- Date keys written to files and sent over the network use POSIX format.
- Sparkle's own update windows remain in English.
- Brand names (Claude, Codex, Grok, Hâl, Always Wake) are not translated.

## Menu bar

On first launch only the Hâl icon is shown. Quota and prayer icons can be turned on individually in Settings › Appearance.

- **Opening:** Clicking opens the detail window; hovering does not.
- **Target:** By default an icon opens the *Today* dashboard. If you choose "Detail of the clicked item" in Settings › Appearance › Click, each icon opens its own page. The general Hâl icon always goes to the dashboard. If the dashboard is off, every icon falls back to the page it represents.
- **Navigation:** While the window is open, clicking another icon moves it there. The last viewed tab is remembered; refreshing doesn't change the selection.
- **Pinning:** The pin in the header keeps the window open when you click outside. `Esc` closes it.
- **Right-click menu:** Refresh, settings, tools, modes, quit. A second-display copy is optional.
- **Single-icon mode:** With "Combine quotas into one icon" on, quota icons merge into one summary showing the quota with the most room left. The prayer time stays a separate icon.
- **Status marks:** `–` appears when there is no session, `!` on a read error. If no percentage is available, no number is made up.

## Modules

There are seven tabs. *Today* cannot be turned off; the others can be disabled in Settings › Appearance. A disabled module isn't merely hidden: its data source and notifications stop too. Tabs scroll horizontally. With more than four modules enabled, the title is shown only on the selected tab.

### Today

Collects the rows that enabled modules contribute to the dashboard: deep work, emptiest quota, full or unreadable quotas, next prayer, prayers performed and streak, water and protein. A row consists of an icon, a title, a value and, if needed, a one-line description. There are no progress bars here; the ratio is the value itself (bars live on module pages). Clicking a row opens the relevant tab.

- Which rows appear is chosen one by one under Settings › Appearance › *Show on the Today dashboard*. Hiding a row does not disable its module: the tab, measurement and notifications stay in place. A hidden row is also left out of the evening daily summary.
- The list is not limited to what is on screen right now. Once a row has been seen it stays in the `hal.summaryCatalog` record; when a module is turned off, its rows drop out of the list. Rows whose title changes during the day keep a fixed name in the list ("Next prayer", "Next event").
- **Week:** Shows the last seven days of focus, workout, prayer and nutrition. It collects no new data.
- **End of Day:** Gathers the last four days of prayer, medication and workout marks in one list. Days you were away from the computer can be completed here. If yesterday has open marks, the dashboard row leads there too. Today's gaps show up in the evening. The window is deliberately short; back-filling a streak indefinitely would corrupt the measurement.
- Daily records live in `~/Library/Application Support/Hal/daily.json`. The structure is day → metric dictionary, with 400 days of history kept.

### Focus

Time is counted automatically when the name of the frontmost app is in the `focusApps` list and the Mac has not been idle for two minutes. Slices are 30 seconds. It shows the daily goal, the app currently being counted, the last seven days, the weekly total and the best day. Browser URLs are never read; tracking requires no permission.

### Quotas

Claude, Codex and Grok. Toggles are off on first setup; even if a CLI is installed, you decide when to turn the quota on.

| | Source | Session |
| --- | --- | --- |
| Claude | `api.anthropic.com/api/oauth/usage` | Keychain, "Claude Code-credentials" |
| Codex | `chatgpt.com/backend-api/wham/usage` | `~/.codex/auth.json` |
| Grok | grok CLI billing response | `~/.grok/auth.json` |

- **Grok:** The weekly limit and Grok Build are read from this billing response. If the token is about to expire, it is renewed with the refresh token in the same file and written back. Prepaid balance and management keys do not factor into this figure.
- **No session:** For Claude or Grok, a Terminal login can be opened from the window. Chats, the session directory and browser cookies are not read; Chrome Safe Storage is never queried.
- **Custom source:** A custom quota source can be added in Settings manually, by command or by URL.
- If a percentage is unavailable, none is invented.

### Worship

Prayer times and prayer tracking. Location, calculation method and the tracking toggle sit together under Settings › Worship.

- Pick a city from the list. Location permission is never requested automatically. Times are not requested until coordinates are chosen; `0,0` does not count as a location.
- Times come from `api.aladhan.com`. In Turkey, Diyanet uses the early (Shafi'i) calculation for Asr; Hanafi is roughly an hour later.
- Prayers are marked in the Prayer tab. The dashboard shows the count for the day and an unbroken day streak. If today isn't complete yet, the streak counts back from yesterday.
- When enabled, the menu bar icon shows the time of the next prayer. Sunrise can also be the next entry.

### Calendar

Today's remaining events and the next event on the dashboard. Permission is requested only through the button in Settings or on the page. Without permission, EventKit is never touched and the page stays empty.

### Health

Four sections: Overview, Workout, Medication & Supplements, Nutrition.

- **Water and protein** are optional. Quick entry is available both on the Today row and on their own page.
- **Workout:** A plan label for each day of the week, one-tap "done", weekly progress and an unbroken streak. Empty or "Rest" days don't count as workouts and don't break the streak. There is no set, rep or weight logging.
- **Medication and supplements:** Each item can have multiple dose times; each time is its own record. A dose whose time has passed and is unmarked is highlighted as "overdue". The notification fires at dose time and not for a dose already taken.

### Payments

Subscriptions, bills and installments. You enter the renewal date once; later dates are computed without editing the record, so dates stay correct even if the app is closed for days. Annual payments are added to the monthly total divided by twelve. A notification arrives at 09:00 in the morning, the chosen number of days before renewal. There is no one-off expense tracking.

## Tools

They are not dashboard modules. Open them from Settings › Tools or by right-clicking the menu bar icon.

### Downloader

A `yt-dlp` wrapper. Paste a link, choose MP3 or MP4, pick a folder (the desktop is used if none is chosen). Progress is read live and can be cancelled. Errors are `yt-dlp`'s own messages. If `yt-dlp` or `ffmpeg` is missing, the install command is shown; nothing is installed for you.

**Automatic updates:** Once a day, before the first download, `yt-dlp` is updated. If a download fails with an extractor error (`Unable to extract`, `nsig extraction failed`, `HTTP Error 403`), it is force-updated once and retried. Errors such as "Video unavailable" do not trigger an update. The method depends on how it was installed:

| Install | Command |
| --- | --- |
| Single-file build | `yt-dlp -U` |
| Homebrew | `brew upgrade` |
| Python script | `pipx upgrade` or `pip install -U` |

### Ports

Lists listening TCP ports and the program holding them (`lsof`).

- "Only my processes" is on by default.
- The "Developer" chip is off by default; when on, only developer servers remain.
- Stopping (`kill`): if the process is yours, it asks first and sends `SIGTERM`. If the process keeps listening, the next confirmation is `SIGKILL`.
- System processes and other users' processes are shown as "system", with no button.

### Homebrew

Homebrew on this Mac. Formulae and casks can be searched, installed, removed and upgraded. `brew services` entries can be started or stopped. Removal and stopping ask first. If Homebrew is missing, nothing is installed; `brew.sh` is shown instead.

### Sound

Output volume and mute. Each app that is playing audio has its own level, up to 150%. At 100% the sound passes straight through. When the level changes, that app’s audio is read through a process tap and played back at the chosen gain. Nothing is recorded. A separate level needs the system audio recording permission.

### Updates

One list for macOS (`softwareupdate`), Homebrew (`brew outdated`) and apps that publish a Sparkle feed. App Store apps open through `mas` when it is installed, otherwise through the App Store page. Nothing installs on its own. A system update can restart the Mac.

## Notifications

Settings › Notifications. Permission is requested when a notification is switched on. Each event is notified once.

- **Prayer time:** when it begins, or 5, 10, 15 or 30 minutes before
- **Quota reset**
- **Quota threshold exceeded**
- **End-of-day reminder:** 12:00 by default, can be turned off; clicking opens End of Day
- **Daily summary:** notifies the dashboard at the chosen time
- **Medication dose and subscription renewal:** while a matching record exists

Other notifications are off by default. Modules produce an `Alert` in `ModuleAlerts.swift`; scheduling and de-duplication live in `NotificationService`.

### Other features

- **Cleaning mode:** Covers the screen with a shield; this part works without permissions. Locking system shortcuts also requires Accessibility and Input Monitoring. Permission is requested with the button in Settings; it doesn't send you to System Settings on every launch.
- **Keep awake:** While Always is on, the Mac does not idle-sleep or sleep the display. Optional timer, while apps from the Focus list are frontmost, while on power or an external display, and while the lid is closed. The lid rule blocks idle sleep; macOS can still sleep on lid close when there is no external power and display.
- **Launch at login:** Updated only when the switch in Settings changes.

## Privacy: what does the app read?

The app is **not** sandboxed. Everything it reads is listed here:

| What | From where / when | Note |
| --- | --- | --- |
| Claude quota | Keychain, "Claude Code-credentials" | Chats are not read |
| Codex quota | `~/.codex/auth.json` | Session directory and chat bodies are not read |
| Grok quota | `~/.grok/auth.json` | Written back to the same file when the token is refreshed. Cookies and the console.x.ai management key are not requested |
| Prayer times | `api.aladhan.com` once a city is chosen | No request until coordinates are chosen |
| Calendar | EventKit after pressing the button | Not accessed without permission |
| Cleaning shortcut lock | Accessibility and Input Monitoring | Only via the button in Settings |
| Daily records | `~/Library/Application Support/Hal/` | The old `secrets.json` is not part of the quota path |
| Keep awake | Frontmost app, power source, displays, lid | No network |
| Homebrew | `brew` on this Mac | Network only if `brew` itself asks for it |
| Volume mixer | Playing processes; a process tap when the level changes | Nothing is recorded |
| Updates | `softwareupdate`, `brew`, `SUFeedURL` | App Store packages are not downloaded |

## Updates and releases

A downloaded copy asks about new versions on its own; nothing installs automatically. It checks once a day, and you can also trigger it from Settings › About › *Check for updates*.

- **Channel:** `https://raw.githubusercontent.com/tahsingibi/hal/main/appcast.xml`. The app reads this file from the repo. The zip goes on a GitHub Release; its address is the `enclosure` line inside `appcast.xml`. The channel lists **1.1.0** (build 3).
- **Sparkle:** The bundle ships with Sparkle 2.10.0. `build.sh` downloads the archive and verifies it with SHA-256.
- **Keys:** The public key is in `SUPublicEDKey`. The private key is in the login keychain (account name `Hal`) and never enters the repo. If the key is deleted, updates after this version can no longer be signed.
- **This release:** the DMG and the Sparkle zip on the GitHub Release. An in-app check sees 1.1.0.
- **A later in-app update:** `scripts/publish-update.sh` builds a zip only when a **Developer ID Application** certificate is present. The zip goes on a GitHub Release, and its address is written to the `enclosure` line inside `appcast.xml`. Notarization needs `NOTARY_KEYCHAIN_PROFILE`. `CFBundleVersion` increases strictly.
- **Continuity:** The bundle identifier never changes, so `~/Library/Application Support/Hal` and preferences stay in place.

> **Note:** The first zip that carries in-app updates has to be a build that already contains Sparkle. `CFBundleVersion` increases strictly on every release.

## Code signing

`build.sh` signs with the first Apple Development or Developer ID certificate in the keychain. The identity can be overridden with `HAL_SIGN_IDENTITY`.

- With no certificate it signs **ad hoc**. An ad-hoc signature produces a new code identity on every build, so Keychain and Accessibility permissions reset each time. With a stable developer certificate, permission is granted once.
- `./build.sh --dmg` copies the app under `dist`, signs that copy ad hoc, and writes `dist/Hal-<version>.dmg`. The project `Hal.app` keeps the development certificate.
- The first time the signing identity changes, macOS asks once for Keychain access; choose **Always Allow**. The old entry in the Accessibility list also becomes invalid; delete it and add it again.

## Development

Tabs and menu bar icons are derived from the `ModuleKind` registry in `Sources/Modules.swift`. `today` cannot be disabled. Downloader, Ports, Homebrew, Sound and Updates sit outside this registry.

**To add a new module:**

1. Add a `case`, `title` and `symbol` to `ModuleKind`
2. Pages in `AppStore.pages(for:)`
3. Dashboard rows in `AppStore.summaryLines(for:)`
4. The page's view in `DetailPopoverView`
5. A data source and, if needed, an `Alert` in `ModuleAlerts.swift`

**Notes:**

- Selection travels as a `DetailTarget` and is stored in the form `"usage/claude"`. Old records (`"prayer"`, a bare quota id) still resolve. Each module's last viewed page is remembered separately.
- The Settings window uses a sidebar and search: App (General, Appearance, Notifications, Keep awake), Modules, Tools (Downloader, Ports, Homebrew, Sound, Updates), About and What's New.
- The detail window's height follows the selected page's natural size and is capped by the screen, at 440 pt at most. A page that exceeds the cap scrolls internally.
- The bundle's development region is marked `tr`; this does not lock the runtime language.

## Release notes

The About page in the app shows the same list.

### 1.1.0 — 31 October 2026

- Compact power panel: battery and system charts, adapter power, temperature, health, cycles and capacity details
- Introduction screen available from About
- Window switcher permission status, automatic shortcut reconnection after granting access and hold-and-release switching

- Keep awake: a timer, while selected apps are frontmost, while on power or an external display, and while the lid is closed
- Homebrew: search, install, remove, upgrade, start and stop services
- Volume mixer: output level and a level per app
- Updates: macOS, Homebrew and installed apps
- Menu bar panel: icon rail, keep-awake durations, volume mixer and tools
- What's New on its own page

### 1.0.0 — 16 October 2026

- Today board, week summary and end of day
- Focus tracking
- Quotas: Claude, Codex, Grok and custom sources
- Prayer times and prayer tracking
- Calendar
- Health: water, protein, workouts, medication and supplements
- Payments
- Downloader (yt-dlp)
- Ports
- Cleaning mode
- Keep awake: always on
- Notifications, Turkish and English, Sparkle update prompt

## About

Written by **Tahsin Sungur** · [sungur.dev](https://sungur.dev) · [@tahsingibi](https://x.com/tahsingibi)

License: [MIT](LICENSE)
## Feature hub and localization resources

Settings now groups Essentials, Work & energy, Personal and Tools. The Features page offers individual module switches and Work, Daily life and Minimal presets. Disabled modules stop loading and disappear from panel navigation and the settings sidebar; settings search and the hub still let you configure them. Today always stays enabled.

Appearance → Panel layout saves module order and a compact panel option. The panel groups Board, Sound, Keep awake and Tools, with descriptive utility cards. Permissions explains access and links to the related settings without requesting access automatically. Reopening the app brings the Features window forward.

Editable translations and native permission descriptions live in `Resources/en.lproj` and `Resources/tr.lproj`. Language changes apply immediately; macOS chooses the language for its permission dialogs. `python3 scripts/localize.py --write` adds missing literal L/Lf entries while preserving translator edits. Prefer positional Lf placeholders to Swift interpolation for new dynamic copy. Context keys (`English | Türkçe`) distinguish identical English text with different Turkish meanings.

```sh
python3 scripts/localize.py --check
./scripts/verify-settings.sh
```

The checks cover older settings, module ordering and persistence, duplicate/stale IDs, format placeholders and runtime language switching from bundled resources. They do not read or modify personal preferences. `./build.sh` builds `Hal.app` in this folder without copying it to Applications.

## Window switcher and display brightness

Enable the switcher from Settings → Work & energy → Window switcher. The default global shortcut is Control-Option-Tab; Option-Tab and Control-Shift-Space are alternatives. It preserves macOS Command-Tab. Navigate with Tab/Shift-Tab or arrows, press Return to activate, and Escape to dismiss. Search by app or window name. Three layouts are available: previews, large icons and a simple list.

Without Accessibility access it lists running apps. With access it lists and restores individual windows, including minimized windows. Preview images additionally require Screen Recording access, requested only through the permission button. Images stay in memory and are cleared when the panel closes; minimized windows use app icons. Current-display and windowless-app filters are available. The feature starts disabled.

Display controls are separately enabled in Settings → Displays. Supported displays use hardware brightness; other displays get click-through software dimming, clearly labeled. Software dimming does not reduce display power consumption. Changes are restored on sleep, disabling the feature or normal app termination. Hardware changes subsequently made elsewhere are preserved. Dimming is never reapplied on launch.

The settings sidebar now has collapsible groups and back/forward navigation. Sound devices use visible Change menus with separate app cards. Homebrew separates Installed, Find packages and Services, with optional dependencies and expandable package details. Updates are grouped by source, with optional daily/weekly background checks that never install automatically.

### Hold-to-switch update

The switcher now uses a dedicated keyboard event-tap thread, background window enumeration and a screen-sized thumbnail strip. Shortcut fields record arbitrary modifier/key combinations. Apps, current-app windows and all windows have separate shortcuts. Holding the modifiers opens a session, Tab/Shift-Tab and arrows navigate, and releasing commits. Fast taps can switch without flashing the panel; Escape cancels. W requests a normal window close and Q requests app termination. Optional S pins search. Record Command-Tab or Command-backtick to opt into temporary native-key takeover; native keys are restored on disable, secure input and quit, with recovery bookkeeping for interrupted exits.

Options include appearance delay, columns, preview sizes, minimal previews, per-app grouping, minimized ordering, fullscreen/display/desktop filters, placement and app exclusions. Thumbnails are matched by window ID and cached only in RAM (48 maximum), including minimized-window capture where supported. The list layout does not capture the screen. Old shortcut records migrate without losing the user's chosen keys.

Collapsed quotas are now enabled by default and cycle selected providers every 3.5 seconds with a native SwiftUI transition. The menu mixer uses flat rows with native device pickers and sliders; it does not reuse nested settings cards.
