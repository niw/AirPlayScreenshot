AirPlayScreenshot
=================

A Swift Package provides an API to run AirPlay server locally to capture
any screenshot from the background applications.


Usage
-----

Add the package as a dependency in your `Package.swift`:

```swift
.package(url: "https://github.com/niw/AirPlayScreenshot.git", branch: "master"),
```

or add it through Xcode, then `import AirPlayScreenshot`.

Create an `AirPlayReceiver`, start it, and call `capture()` to render the
latest mirrored frame as a `UIImage`:

```swift
import AirPlayScreenshot

let receiver = AirPlayReceiver(name: "My Receiver")

// Start advertising on Bonjour and receiving the mirroring stream.
// Call from the main thread in the foreground before mirroring begins.
try receiver.start()

// Render the latest decoded frame, or nil if nothing has arrived yet.
// Safe to call from any thread.
let image = receiver.capture()

// Stop advertising and receiving.
receiver.stop()
```

Once started, the receiver advertises itself on the local network. Pick it
as an AirPlay (Screen Mirroring) target from another device, and `capture()`
returns the most recently decoded frame on demand.

Observe connection and mirroring lifecycle through the `events` stream:

```swift
for await event in receiver.events {
    switch event {
    case .connectionInitiated:
        print("A client is connecting…")
    case .clientConnected(let name, _, _):
        print("\(name) connected")
    case .mirroringStarted:
        print("Mirroring started")
    case .mirroringStopped:
        print("Mirroring stopped")
    case .disconnected:
        print("Client disconnected")
    case .videoSizeChanged(let size):
        print("Video size: \(size)")
    }
}
```

The H.264 decoding backend can be selected with `decoderKind` when creating
the receiver — `.openH264` (default) or `.videoToolbox`:

```swift
let receiver = AirPlayReceiver(name: "My Receiver", decoderKind: .videoToolbox)
```

See `Examples/AirPlayScreenshotApp` for a complete SwiftUI sample app.


Build
-----

This package contains a pre-build [OpenH264](https://github.com/cisco/openh264)
xcframework for ARM64 platforms.
To build `OpenH264.xcframework`, use `build.sh` in `openh264_xcframework_build`
directory.

### Example app

The sample app in `Examples/AirPlayScreenshotApp` uses [XcodeGen](https://github.com/yonaskolb/XcodeGen)
to generate its Xcode project.

Install XcodeGen, for instance with [Homebrew](https://brew.sh):

```sh
brew install xcodegen
```

Then generate the project and open it:

```sh
cd Examples/AirPlayScreenshotApp
xcodegen generate
open AirPlayScreenshotApp.xcodeproj
```

Code signing defaults to automatic. To run on a device with your own signing
settings, create `Configurations/CodeSigning-Local.xcconfig`.

```
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = ...
PROVISIONING_PROFILE_SPECIFIER = ...
```


License
-------

This project itself is provided under the [MIT license](LICENSE).

It bundles [OpenH264](https://github.com/cisco/openh264),
which is licensed under the BSD-2-Clause.

It also depends on [UxPlay](https://github.com/FDH2/UxPlay) through
[UxPlaySwift](https://github.com/niw/UxPlaySwift), which is licensed under the
GPL-3.0.
Any project that includes this package is considered as a derivative work of
UxPlay and is, therefore subject to the terms of the GPL-3.0.
In practice this means your project, as a whole, must comply with the GPL-3.0
license rules.
