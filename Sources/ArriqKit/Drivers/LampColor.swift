import Foundation

/// pure hue maths for the lamp. the ui stays two-colour, so a hue is shown as a word, never as a swatch.
public enum LampColor {
    /// full saturation, full value: hue in degrees -> 0...255 rgb
    public static func rgb(hue: Int) -> (r: Int, g: Int, b: Int) {
        let h = Double(((hue % 360) + 360) % 360) / 60
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// lower-case colour word for a hue, for the readout next to the slider
    public static func name(hue: Int) -> String {
        let h = ((hue % 360) + 360) % 360
        switch h {
        case 0..<15, 345..<360: return "red"
        case 15..<45: return "orange"
        case 45..<70: return "yellow"
        case 70..<160: return "green"
        case 160..<200: return "cyan"
        case 200..<260: return "blue"
        case 260..<290: return "purple"
        default: return "pink"
        }
    }
}
