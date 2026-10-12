# Iron Log

Personal gym + nutrition tracker for iPhone. Swift, SwiftUI, SwiftData, fully offline.

## Run it on your iPhone

**One-time setup**

1. Update your Mac to macOS 26.6 or later (Apple menu → System Settings → General → Software Update).
2. Install **Xcode** from the Mac App Store and open it once.
3. Xcode → Settings → Accounts → **+** → sign in with your Apple ID.
4. On the iPhone: Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).

**Get the code**

In Xcode: **Integrate → Clone…** (or File → Clone on older versions), paste
`https://github.com/TheMangoTheory0107/Gym-APP`, and choose a folder. Then open `IronLog.xcodeproj`.

To get later updates: **Integrate → Pull…**

**Run**

1. Plug in the iPhone and tap **Trust** on it.
2. In Xcode, click **IronLog** (blue icon, top of the left sidebar) → target **IronLog** → **Signing & Capabilities**.
3. **Team**: pick your name (Personal Team).
   If Xcode says the bundle identifier isn't available, change `com.themangotheory.ironlog` to something unique like `com.yourname.ironlog`.
4. At the top of the window, pick your iPhone as the run destination and press **⌘R**.
5. First time only: on the iPhone go to Settings → General → **VPN & Device Management** → your Apple ID → **Trust**. Press ⌘R again.

With a free Apple ID the app must be re-run from Xcode every 7 days. Your data is kept. **Never delete the app** — that erases its data.

## Edit your data

All reference data lives in `IronLog/Resources/Data/` as plain JSON:

| File | What's in it |
|---|---|
| `split.json` | Your weekly split. `scheme` formats: `"3x8-12"`, `"20,15,15,15"`, `"20,15,8-10,8-10,8-10"`. Plank is in seconds (`"3x120"`), cardio in minutes. |
| `exercises.json` | Every exercise: name, log type (`weightReps`, `reps`, `seconds`, `minutes`), muscles, weight step. |
| `muscles.json` | Muscle ids, names and groups used for the muscle map and weekly volume. |

If a file has a mistake, the TODAY tab shows exactly which file and line to fix.

## Build check

Every push is built on GitHub's macOS machines (`.github/workflows/build.yml`), so build errors are caught before you open Xcode.

## Credits

- Bebas Neue font — SIL Open Font License (`licenses/BebasNeue-OFL.txt`).
