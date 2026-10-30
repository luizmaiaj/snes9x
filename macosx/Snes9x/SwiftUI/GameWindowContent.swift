/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import AppKit
import Combine
import SwiftUI

/// Holds the engine's game view and lays it out the way the AppKit window
/// showed it: full height, centred horizontally, as wide as the SNES aspect
/// ratio asks but never narrower than the view's minimum width.
///
/// The engine's own constraints (aspect ratio plus a 512×478 minimum) cannot
/// all hold in a shorter window, and Auto Layout then drops a different one
/// depending on the height, so the container sizes the view itself.
final class GameContainerView: NSView {
    private(set) weak var gameView: NSView?

    /// The smallest size the current game view allows (its size when created).
    private(set) var minimumSize = NSSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ newView: NSView?) {
        guard newView !== gameView else {
            return
        }

        gameView?.removeFromSuperview()
        gameView = newView

        guard let newView else {
            return
        }

        minimumSize = newView.frame.size
        newView.removeConstraints(newView.constraints)
        newView.translatesAutoresizingMaskIntoConstraints = true
        newView.autoresizingMask = []
        addSubview(newView)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let gameView, minimumSize.width > 0, minimumSize.height > 0 else {
            return
        }

        let height = bounds.height
        let aspectWidth = height * minimumSize.width / minimumSize.height
        let width = min(bounds.width, max(aspectWidth, minimumSize.width))

        gameView.frame = NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: height)
    }
}

/// Puts the engine's current game view into SwiftUI.
struct GameView: NSViewRepresentable {
    let model: EmulatorModel

    final class Coordinator {
        var subscription: AnyCancellable?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GameContainerView {
        let container = GameContainerView(frame: .zero)

        // Swap views synchronously, not on SwiftUI's next update: the engine
        // makes the new view first responder right after a ROM loads, and it
        // must already be in the window by then.
        context.coordinator.subscription = model.$gameView.sink { [weak container] view in
            container?.show(view)
        }

        return container
    }

    func updateNSView(_ nsView: GameContainerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GameContainerView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: nsView.minimumSize)
    }
}

/// The content of the game window.
struct GameWindowContent: View {
    let model: EmulatorModel

    var body: some View {
        GameView(model: model)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.openROM()
                    } label: {
                        Label("Open ROM", systemImage: "folder")
                    }
                    .help("Open a ROM file and start the game")
                }
            }
    }
}

/// Hosts the game window content and acts as the window's delegate; the
/// window keeps it alive as its content view controller.
final class GameHostingController: NSHostingController<GameWindowContent>, NSWindowDelegate {
    /// In full screen the toolbar hides with the menu bar and comes back, with
    /// the window buttons, when the pointer reaches the top of the screen.
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        proposedOptions.union([.fullScreen, .autoHideMenuBar, .autoHideDock, .autoHideToolbar])
    }
}

@MainActor
@objc(S9xGameWindowHosting)
public final class GameWindowHosting: NSObject {
    /// Makes `window` show the SwiftUI game window content for `model`.
    @objc public static func install(in window: NSWindow, model: EmulatorModel) {
        let hostingController = GameHostingController(rootView: GameWindowContent(model: model))
        // The window keeps the size the user (or the saved frame) gave it.
        hostingController.sizingOptions = []
        // Puts the SwiftUI `.toolbar` items into this AppKit window's toolbar.
        hostingController.sceneBridgingOptions = [.toolbars]

        let frame = window.frame
        window.toolbarStyle = .unifiedCompact
        // The toolbar shows the window background behind its buttons; a clear
        // one lets the desktop show through. The game area stays black.
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = hostingController
        window.delegate = hostingController
        window.setFrame(frame, display: false)
    }
}
