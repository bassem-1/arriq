import Foundation

/// result of one device attempt. `text` is the lower-case log line; `lampIP` is set when the lamp was found;
/// `hint` is an optional second log line that explains a failure.
public struct DeviceOutcome: Equatable, Sendable {
    public var ok: Bool
    public var text: String
    public var lampIP: String?
    public var hint: String?
    public init(ok: Bool, text: String, lampIP: String? = nil, hint: String? = nil) {
        self.ok = ok; self.text = text; self.lampIP = lampIP; self.hint = hint
    }
}
