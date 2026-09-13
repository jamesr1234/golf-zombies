Golf Zombies for Mac (Apple Silicon / M1, universal)

If macOS says the app is damaged or corrupt, that is Gatekeeper,
not a broken file. The build is unsigned and not Apple-notarized.

In Terminal, from this folder:

  xattr -dr com.apple.quarantine "Golf Zombies.app"
  open "Golf Zombies.app"

Or right-click Open Golf Zombies.command and choose Open.
