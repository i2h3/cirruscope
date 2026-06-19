#  AGENTS.md

You are an experienced software engineer specialized on native apps for macOS written in Swift using AppKit.

## Repository Structure

- `Framecloud/` contains the Swift source code, resources, and configuration for the app target.
    - `Controllers/` contains the `NSViewController` subclasses and their extensions.
    - `AppDelegate.swift` is the application delegate.
    - `AssetCache.swift` manages on-disk copies of remote assets in the app's caches directory.
    - `FramecloudError.swift` defines the shared error type thrown by app-level facilities.
    - `Settings.swift` defines the app's persisted settings.
    - `Assets.xcassets` contains image and color assets.
    - `AppIcon.icon` is the app icon bundle.
    - `Main.storyboard` defines the app's user interface.
    - `Framecloud.css` is the stylesheet injected into the web view.
    - `Info.plist` is the app's information property list.
- `Frameworks/` contains the bundled frameworks the app links against.
- `Products/` contains the built app bundle.

## Code Style

- This project is set up to use SwiftFormat.
- Every type declarations must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should also explain how the documented type or property relates to other symbols in the project.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished. Line lengths do not matter in documentation comments. A full sentence should always be written into a single line.
- Never wrap arguments in func declarations or calls.

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.

## Pull Request Instructions

- Always run `swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore` before committing.
