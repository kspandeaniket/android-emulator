# Standalone Android Emulator for Windows (no Android Studio)

Install the official Google Android Emulator on Windows **without installing Android Studio**, using a single PowerShell script. Then start it from a desktop shortcut that opens a small options window (GPU mode, audio, network speed, boot options, ...) before the emulator launches.

Everything is downloaded from Google's official servers (`dl.google.com`). Nothing is bundled in this repository except the scripts.

## Contents

| File | Purpose |
|---|---|
| `setup-android-emulator.bat` | Double-click wrapper for the installer |
| `setup-android-emulator.ps1` | The installer (also contains the launcher window) |
| `uninstall-android-emulator.bat` | Double-click wrapper for the uninstaller |
| `uninstall-android-emulator.ps1` | The uninstaller (every step asks first) |

Keep each `.bat` in the same folder as its `.ps1`.

## Requirements

- Windows 10 or 11, 64-bit
- Windows PowerShell 5.1 (already included in Windows)
- A **JDK** (17 or 21 recommended) with `JAVA_HOME` set, or `java.exe` on your `PATH`. The script checks for Java but does **not** install it.
- Hardware virtualization enabled in BIOS/UEFI, plus the Windows feature **Windows Hypervisor Platform** (see [Troubleshooting](#troubleshooting))
- An internet connection
- Free disk space: roughly 2 GB for the emulator and tools, plus about 1.5 to 3 GB per system image. Plan for around 6 to 10 GB in total.

## Installation

### 1. Get the files

```
git clone https://github.com/<your-user>/<your-repo>.git
cd <your-repo>
```

or download the repository as a ZIP and extract it. If you downloaded a ZIP, right-click it in Explorer, open **Properties** and tick **Unblock** *before* extracting. Otherwise, run this in PowerShell inside the folder:

```powershell
Get-ChildItem . -Recurse | Unblock-File
```

### 2. Run the installer

Either double-click `setup-android-emulator.bat`, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-android-emulator.ps1
```

Optional parameters:

| Parameter | Default | Meaning |
|---|---|---|
| `-SdkRoot` | `C:\Android\sdk` | Where the SDK is installed |
| `-AvdName` | asked | Name of the virtual device |
| `-Device` | asked | Device profile, e.g. `pixel_9_pro_xl` |
| `-ShortcutOnly` | off | Skip installation, only create the launcher and shortcut |

Example: `powershell -ExecutionPolicy Bypass -File .\setup-android-emulator.ps1 -SdkRoot D:\Android\sdk`

### 3. What the installer does, step by step

1. **Checks Java.** Stops with a message if no JDK is found.
2. **Downloads the Android command-line tools** from Google (skipped if already present) and unpacks them to `<SdkRoot>\cmdline-tools\latest`.
3. **Sets environment variables** (user level): `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and adds `cmdline-tools\latest\bin`, `platform-tools` and `emulator` to your `PATH`. Open a **new** terminal for this to apply.
4. **Accepts the SDK licenses** automatically. By running the script you accept Google's Android SDK license terms.
5. **Lists the available packages** and asks you to choose:
   - include beta/preview releases or not (default: no)
   - the Android version (newest first)
   - the image variant, e.g. *Google APIs*, *Google APIs + Play Store*, or plain AOSP
   - the SDK platform (defaults to the one matching your image, or skip)
6. **Installs** `emulator`, `platform-tools`, the chosen platform and the chosen system image.
7. **Creates the virtual device (AVD):** you pick a device profile (Pixel phones, tablets/foldables, Wear/TV/Automotive, or all) and a name. The script also runs a hardware-acceleration check at the end.
8. **Offers the desktop shortcut** (see next section).

Press **Enter** at any prompt to accept the default shown in brackets.

## Starting the emulator

If you accepted the shortcut prompt, you now have **Android Emulator** on your desktop (and optionally in the Start Menu). Opening it shows the launcher window instead of starting the emulator immediately.

### The launcher window

| Section | Option | Emulator flag |
|---|---|---|
| Virtual device | Dropdown of all your AVDs | `-avd <name>` |
| Graphics and audio | GPU mode: `host`, `auto`, `swiftshader_indirect`, `angle_indirect`, `guest`, `off` | `-gpu <mode>` |
| | Disable audio | `-no-audio` |
| | Skip boot animation | `-no-boot-anim` |
| Network | Speed: `full`, `lte`, `hsdpa`, `hspa`, `umts`, `evdo`, `edge`, `gprs`, `gsm` | `-netspeed <value>` |
| | Latency: `none`, `umts`, `gprs`, `edge` | `-netdelay <value>` |
| Startup and storage | Cold boot (ignore saved state) | `-no-snapshot-load` |
| | Don't save state on exit | `-no-snapshot-save` |
| | Read-only (discard all changes) | `-read-only` |
| | Headless (no window) | `-no-window` |
| | Wipe data / factory reset (asks for confirmation) | `-wipe-data` |
| Performance | RAM override | `-memory <MB>` |
| | CPU cores override | `-cores <n>` |
| Extra arguments | Any other flags, e.g. `-dns-server 8.8.8.8` | passed as-is |

Good to know:

- The defaults are `-no-audio -gpu host -netdelay none -netspeed full`.
- A **live preview** shows the exact command that will run, and **Copy command** puts it on your clipboard.
- Your last choices are remembered in `%LOCALAPPDATA%\AndroidEmulatorLauncher\settings.json`. "Wipe data" is never remembered.
- If the emulator exits within about 6 seconds, the launcher shows its error output. Logs are saved next to the settings file (`last-run.out.log`, `last-run.err.log`).
- The launcher script lives at `<SdkRoot>\launcher\emulator-launcher.ps1`. You can edit it freely.

### Creating the shortcut later

If you skipped the prompt, or you moved the SDK:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-android-emulator.ps1 -ShortcutOnly
```

### Starting from the command line

Without the launcher, from a new terminal:

```powershell
emulator -avd <your_avd_name> -no-audio -gpu host -netdelay none -netspeed full
```

To see all AVD names: `emulator -list-avds`.

## Using it with your projects

- **adb** is installed with the platform-tools. With the emulator running, `adb devices` should list it.
- **Expo / React Native:** start the emulator, then run `npx expo start` in your project and press `a`.
- **Flutter / Gradle projects:** `ANDROID_HOME` is already set, so they find the SDK automatically.

## Uninstalling

Double-click `uninstall-android-emulator.bat`, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-android-emulator.ps1
```

Every step asks first. It will:

1. Stop running emulator/adb processes from the SDK folder
2. List your AVDs and let you delete all or selected ones (Enter = none)
3. Remove the SDK: delete the whole folder, or pick individual packages (needs Java), or skip
4. Remove `ANDROID_HOME` / `ANDROID_SDK_ROOT` and the matching `PATH` entries
5. Delete the Desktop / Start Menu shortcuts, the launcher script and its saved options
6. Optionally delete `%USERPROFILE%\.android` (shared with Android Studio, so the default is to keep it)

Parameters: `-SdkRoot <path>` to point to a custom folder, and `-Yes` to answer yes to everything. `-Yes` never deletes `%USERPROFILE%\.android`. The script refuses to operate on drive roots or system folders.

It does **not** remove Java or the Windows Hypervisor Platform feature. To disable the latter (admin PowerShell, then reboot):

```powershell
Disable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform
```

## Troubleshooting

**"running scripts is disabled" or the window closes immediately**
Use the `.bat` files, or call PowerShell with `-ExecutionPolicy Bypass` as shown above.

**"Java was not found"**
Install a JDK (for example Temurin 17 or 21), set `JAVA_HOME`, open a new terminal, and run the installer again.

**Emulator says WHPX / hypervisor is not installed, or is extremely slow**
1. Enable virtualization (Intel VT-x / AMD-V / SVM) in BIOS/UEFI.
2. Turn on **Windows Hypervisor Platform** in *Turn Windows features on or off* (needs admin), then reboot.
3. Check with `emulator -accel-check`.

**"Access is denied" while listing packages**
The Android CLI unpacks itself on first run. The script retries three times automatically. If it still fails, close other terminals using the SDK and run it again.

**No system images listed**
The script saves the raw output to `%TEMP%\sdkmanager-list.txt`. Check your internet/proxy settings, and note that the script only lists images matching your CPU (`x86_64` or `arm64-v8a`).

**`emulator` or `adb` is not recognized**
PATH changes apply to new terminals only. Close and reopen your terminal (or sign out and in).

**Black screen, glitches or crashes with GPU mode `host`**
Try `angle_indirect` or `swiftshader_indirect` in the launcher, and update your graphics drivers.

**The emulator exits immediately after pressing Launch**
Read the message the launcher shows. Typical causes: the same AVD is already running (use *Read-only* to run a second instance), or not enough free RAM or disk space.

**Launcher window does not open**
Run this in PowerShell to see the error: `powershell -ExecutionPolicy Bypass -File "C:\Android\sdk\launcher\emulator-launcher.ps1"`

## FAQ

**Is this better than installing Android Studio?**
If you only need an emulator, yes: it skips the IDE, its bundled JDK, Gradle caches and the many default SDK packages. Google's own requirements list about 8 GB of free disk for Android Studio with the SDK and emulator (16 GB recommended), and that is before you add system images. If you actually write native Android apps in Kotlin or Java, you want Android Studio anyway.

**Is it official?**
The emulator, tools and images are Google's, downloaded from Google's servers. Only the automation around them is custom.

**Can I install several versions or devices?**
Yes. Run the installer again, pick another image or device, and use a new AVD name. They all show up in the launcher dropdown.

**Can I change the SDK location?**
Yes, pass `-SdkRoot` to both the installer and the uninstaller.

## License

Add your preferred license here (for example MIT). Android SDK components are licensed by Google under their own terms, which you accept when licenses are accepted during setup.

## Disclaimer

Not affiliated with or endorsed by Google. Android and the Android Emulator are trademarks of Google LLC. Use at your own risk.
