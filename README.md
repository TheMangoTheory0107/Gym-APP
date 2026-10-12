# Iron Log

Personal gym + nutrition tracker for iPhone. Swift, SwiftUI, SwiftData, Swift Charts. Fully offline, no accounts.

## Run it on your iPhone

**One-time setup**

1. Update your Mac to macOS 26.6 or later (Apple menu → System Settings → General → Software Update).
2. Install **Xcode** from the Mac App Store and open it once (install iOS components if asked).
3. Xcode → Settings → Accounts → **+** → sign in with your Apple ID.
4. On the iPhone: Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).

**Get the code**

Xcode → **Integrate → Clone…**, paste `https://github.com/TheMangoTheory0107/Gym-APP`, choose a folder, open `IronLog.xcodeproj`.
Later updates: **Integrate → Pull…**

**Run**

1. Plug in the iPhone and tap **Trust**.
2. Click **IronLog** (blue icon, top of the left sidebar) → **Signing & Capabilities**.
3. Set **Team** to your name (Personal Team) for **both** targets: `IronLog` and `IronLogWidget`.
   If Xcode says the bundle identifier isn't available, change `com.themangotheory.ironlog` to something unique
   (e.g. `com.yourname.ironlog`) on IronLog, and the widget's to the same thing plus `.widget`.
4. Pick your iPhone at the top of the window and press **⌘R**.
5. First time only: iPhone → Settings → General → **VPN & Device Management** → your Apple ID → **Trust**, then ⌘R again.

With a free Apple ID the app must be re-run from Xcode every 7 days. Your data is kept. **Never delete the app**: that
erases its data. Use Settings → Backup → Export regularly.

### Widget calories (optional)

The Home Screen widget always shows today's workout. To also show **calories and protein left**, the app and widget need
to share data through an App Group:

1. Signing & Capabilities → **+ Capability** → **App Groups** on the `IronLog` target, add `group.com.themangotheory.ironlog`.
2. Do the same on the `IronLogWidget` target with the same group.

If your free account doesn't allow App Groups, skip this; everything else works.

## What's in the app

| Tab | Features |
|---|---|
| **TODAY** | Auto-loads the weekday's split, day switcher, start/resume workout, +/- steppers pre-filled from last time, rest timer (notification + Lock Screen / Dynamic Island countdown), finish screen with PRs, Sunday recovery + weekly summary |
| **EXERCISES** | 38 exercises, form demo photos, HD 3D muscle map (front/back), cues, mistakes, YouTube form search |
| **NUTRITION** | Target rings, plain-text / dictated food logging with an offline parser, review & correct, learns your portions, Claude prompt round-trip, one-tap diet plan meals, plan vs targets, supplements with reminders and creatine streak, history charts |
| **PROGRESS** | Weight chart, BMI / FFMI / lean mass, streak calendar, strength charts per exercise, weekly sets per muscle group, PR list, weekly / monthly reports (shareable image) |

## Edit your data

All reference data is plain JSON:

| File | What's in it |
|---|---|
| `Shared/Data/split.json` | Weekly split. `scheme` formats: `"3x8-12"`, `"20,15,15,15"`, `"20,15,8-10,8-10,8-10"`. Plank is seconds (`"3x120"`), cardio minutes. |
| `IronLog/Resources/Data/exercises.json` | Exercises: log type (`weightReps`, `reps`, `seconds`, `minutes`), muscles, weight step, cues, mistakes. |
| `IronLog/Resources/Data/muscles.json` | Muscle ids, names and groups. |
| `IronLog/Resources/Data/foods.json` | 248 foods: macros per 100 g, aliases (Hinglish spellings), household units (`"piece": 40`, `"bowl": 150`). |
| `IronLog/Resources/Data/diet_plan.json` | Your meal plan (food ids + quantities). |
| `IronLog/Resources/Data/supplements.json` | Supplement checklist and reminder times. |

If a file has a mistake, the app shows which file and what's wrong instead of crashing.

### Muscle images

The HD muscle images in `IronLog/Resources/Images/Muscles` are rendered with Blender from the Z-Anatomy model.
Which muscles light up comes from `exercises.json`; the mapping to 3D meshes is in `tools/render/muscle_meshes.json`.
To re-render after changing muscles, see the header of `tools/render/render_batch.py`.

## Build check

Every push is built on GitHub's macOS machines (`.github/workflows/build.yml`).

## Credits

- Muscle images: [Z-Anatomy](https://www.z-anatomy.com) (CC BY-SA 4.0), based on BodyParts3D © The Database Center for Life Science (CC BY-SA 2.1 JP). The rendered images are shared under CC BY-SA 4.0.
- Exercise photos: [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense / public domain).
- Font: Bebas Neue, SIL Open Font License (`licenses/BebasNeue-OFL.txt`).
