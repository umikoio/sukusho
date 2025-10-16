<div align="center">
  <img width="40%" src="assets/AppIcon.png" />
  <h1>Sukusho</h1>
  <p>The native screenshot history manager for MacOS</p>
</div>


Sukusho is a utility that saves your screenshot history in memory, so if you need to take multiple screenshots, but don't want to save them immediately to your local drive, this is for you. After you successfully take a screenshot, a row will populate in Sukusho's top menu bar. These screenshots will remain until you clear the history, exceed the max number of screenshots (10), or quit the program.

## Installation

Install with a single command:

```bash
curl https://umiko.io/sukusho.sh | sh
```

Once the installation script has completed, you should see `Sukusho v0.x.x successfully installed`. From there, just head over to the `/Applications` directory and run Sukusho!

### Keyboard Shortcuts

If you don't want to manually click any buttons or open the modal, a few keyboard shortcuts are available:

| Shortcut | Action               |
| -------- | -------------------- |
| `⌘ + N`  | Take a screenshot    |
| `⌘ + Q`  | Quit the application |

NOTE: Sekusho must be the active foreground application. You can just click the Sekusho dock icon to make it the active application.

> [!IMPORTANT]
> The install script above adds Sukusho to your quarantine settings.
> While Sukusho is safe to use, works fully offline, and has no analytics whatsoever built-in, I've decided to not sign the app. This may change, but for now, it's installable via the script above.

NOTE: Sukusho is not currently compatible with the default MacOS screenshot utility. There are also no keyboard shortcuts yet. You must use Sukusho directly to take and save screenshots. I have these on the backlog.

#### Windows / Linux Support?
I built this for MacOS only using native interfaces (i.e Swift, AppKit, etc.), however, if I ever personally need something like this on Linux or Windows, I'll build it. If this project gains traction and people need a solution for Linux or Windows, I'll build it. If you seriously need something like this, create an issue for your operating system, and I'll begin looking into it.
