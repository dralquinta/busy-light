import AppKit

/// Controller for the hotkey preferences window.
/// Allows users to view and reconfigure hotkey bindings interactively.
@MainActor
public class HotkeyPreferencesController: NSObject, NSWindowDelegate {
    
    private let window: NSWindow
    private var currentBindings: [PresenceState: UInt16]
    private var editingState: PresenceState?
    private var bindingButtons: [PresenceState: NSButton] = [:]
    private var statusLabel: NSTextField?
    private var keyEventMonitor: Any?  // NSEvent.LocalMonitorForEvents return value
    
    /// Called when the user saves new hotkey bindings
    public var onBindingsSaved: (@MainActor ([PresenceState: UInt16]) -> Void)?
    
    // MARK: - Initialization
    
    public init(currentBindings: [PresenceState: UInt16]) {
        self.currentBindings = currentBindings
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.window = window
        
        super.init()
        
        window.delegate = self
        window.title = "Configure Hotkeys"
        window.center()
        window.isReleasedWhenClosed = false
        
        setupContent()
    }
    
    // MARK: - Setup
    
    private func setupContent() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView
        
        // Title label
        let titleLabel = NSTextField()
        titleLabel.stringValue = "Hotkey Bindings"
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // Instructions label
        let instructionsLabel = NSTextField()
        instructionsLabel.stringValue = "Click a button below, then press the key you want to assign."
        instructionsLabel.font = NSFont.systemFont(ofSize: 11)
        instructionsLabel.isEditable = false
        instructionsLabel.isSelectable = false
        instructionsLabel.isBezeled = false
        instructionsLabel.drawsBackground = false
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(instructionsLabel)
        
        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)
        
        // Bindings stack view
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        // Add binding controls for each state
        let states: [PresenceState] = [.available, .tentative, .busy, .away, .off]
        for state in states {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 16
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            
            // State label
            let stateLabel = NSTextField()
            stateLabel.stringValue = "\(state.displayName):"
            stateLabel.font = NSFont.systemFont(ofSize: 12)
            stateLabel.isEditable = false
            stateLabel.isSelectable = false
            stateLabel.isBezeled = false
            stateLabel.drawsBackground = false
            stateLabel.translatesAutoresizingMaskIntoConstraints = false
            stateLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            rowStack.addArrangedSubview(stateLabel)
            
            // Key binding button
            let keyCode = currentBindings[state] ?? 0
            let keyName = keyCodeToName(keyCode)
            
            let button = NSButton()
            button.title = keyName
            button.translatesAutoresizingMaskIntoConstraints = false
            button.target = self
            button.action = #selector(editBinding(_:))
            button.tag = state.hashValue  // Store state identifier
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            rowStack.addArrangedSubview(button)
            
            bindingButtons[state] = button
            stackView.addArrangedSubview(rowStack)
        }
        
        // Status label (for feedback during editing)
        let status = NSTextField()
        status.stringValue = ""
        status.font = NSFont.systemFont(ofSize: 10)
        status.textColor = NSColor.systemOrange
        status.isEditable = false
        status.isSelectable = false
        status.isBezeled = false
        status.drawsBackground = false
        status.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = status
        contentView.addSubview(status)
        
        // Bottom buttons
        let bottomStack = NSStackView()
        bottomStack.orientation = .horizontal
        bottomStack.spacing = 8
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomStack)
        
        let resetButton = NSButton()
        resetButton.title = "Reset to Defaults"
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.target = self
        resetButton.action = #selector(resetToDefaults)
        bottomStack.addArrangedSubview(resetButton)
        
        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(spacer)
        
        let cancelButton = NSButton()
        cancelButton.title = "Cancel"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        bottomStack.addArrangedSubview(cancelButton)
        
        let saveButton = NSButton()
        saveButton.title = "Save"
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.target = self
        saveButton.action = #selector(save)
        bottomStack.addArrangedSubview(saveButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            instructionsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            instructionsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            instructionsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            divider.topAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            stackView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            status.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            bottomStack.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            bottomStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])
    }
    
    // MARK: - Public API
    
    public func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Window Delegate
    
    public func windowWillClose(_ notification: Notification) {
        // Clean up key capture
        stopKeyCapture()
        statusLabel?.stringValue = ""
    }
    
    // MARK: - Actions
    
    @objc private func editBinding(_ sender: NSButton) {
        // Find which state this button represents
        guard let state = bindingButtons.first(where: { $0.value === sender })?.key else {
            return
        }
        
        // If already editing, stop the previous edit
        if editingState != nil {
            stopKeyCapture()
        }
        
        editingState = state
        statusLabel?.stringValue = "🎹 Press a key for \(state.displayName)..."
        statusLabel?.textColor = NSColor.systemBlue
        
        // Focus the preferences window to ensure it captures keystrokes
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Install a local event monitor for this window only
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.editingState != nil else {
                return event  // Not in editing mode, pass through
            }
            
            // Log the keystroke
            uiLogger.logEvent("hotkey.capture.keydown", details: [
                "keyCode": String(event.keyCode),
                "characters": event.characters ?? "none"
            ])
            
            // Capture the key code
            let keyCode = event.keyCode
            let capturedState = self.editingState
            
            // Stop monitoring and process the captured key
            self.stopKeyCapture()
            if let state = capturedState {
                self.handleCapturedKeyCode(keyCode, forState: state)
            }
            
            // Consume the event (don't pass it through)
            return nil
        }
        
        // Set a timeout to cancel key capture if no key is pressed
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            if self?.editingState != nil {
                self?.stopKeyCapture()
                self?.statusLabel?.stringValue = "Timeout - no key captured"
                self?.statusLabel?.textColor = NSColor.systemRed
            }
        }
    }
    
    private func stopKeyCapture() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        editingState = nil
    }
    
    private func handleCapturedKeyCode(_ keyCode: UInt16, forState state: PresenceState) {
        let keyName = keyCodeToName(keyCode)
        
        // Update binding
        currentBindings[state] = keyCode
        
        // Update button
        if let button = bindingButtons[state] {
            button.title = keyName
        }
        
        statusLabel?.stringValue = "✓ Updated \(state.displayName) → \(keyName)"
        statusLabel?.textColor = NSColor.systemGreen
        
        editingState = nil
        
        // Reset status after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.statusLabel?.stringValue = ""
        }
    }
    
    @objc private func resetToDefaults() {
        // Load default bindings
        currentBindings = [
            .available: 18,    // 1 key (with Ctrl+Cmd modifiers)
            .tentative: 19,    // 2 key (with Ctrl+Cmd modifiers)
            .busy: 20,         // 3 key (with Ctrl+Cmd modifiers)
            .away: 106,        // F16
            .off: 64           // F17
        ]
        
        // Update all buttons
        for (state, button) in bindingButtons {
            let keyCode = currentBindings[state] ?? 0
            button.title = keyCodeToName(keyCode)
        }
        
        statusLabel?.stringValue = "Reset to defaults"
        statusLabel?.textColor = NSColor.systemOrange
    }
    
    @objc private func cancel() {
        window.close()
    }
    
    @objc private func save() {
        onBindingsSaved?(currentBindings)
        uiLogger.logEvent("hotkey.bindings.preferences.saved", details: [
            "bindingsCount": String(currentBindings.count)
        ])
        window.close()
    }
    
    // MARK: - Helpers
    
    private func keyCodeToName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 18:  return "Ctrl+Cmd+1"
        case 19:  return "Ctrl+Cmd+2"
        case 20:  return "Ctrl+Cmd+3"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        default:  return "Key \(keyCode)"
        }
    }
}
