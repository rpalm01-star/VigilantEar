import SwiftUI
import Foundation

// MARK: - Color Extensions
extension Color {
    /// Converts any color to a vibrant neon version
    func neon(saturationBoost: Double = 1.1, brightness: Double = 1.0, hueShift: Double = 0.0) -> Color {
        guard let uiColor = UIColor(self).cgColor.components, uiColor.count >= 3 else {
            return self
        }
        
        let r = uiColor[0]
        let g = uiColor[1]
        let b = uiColor[2]
        
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal
        
        var hue: Double = 0
        var saturation: Double = 0
        
        if delta != 0 {
            saturation = delta / maxVal
            
            if maxVal == r {
                hue = (g - b) / delta
            } else if maxVal == g {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        
        let newHue = fmod(hue + hueShift + 360, 360)
        let newSat = min(1.0, saturation * saturationBoost)
        
        let c = brightness * newSat
        let x = c * (1 - abs(fmod(newHue / 60.0, 2) - 1))
        let m = brightness - c
        
        var nr: Double = 0, ng: Double = 0, nb: Double = 0
        let sector = Int(newHue / 60) % 6
        
        switch sector {
        case 0:  nr = c; ng = x; nb = 0
        case 1:  nr = x; ng = c; nb = 0
        case 2:  nr = 0; ng = c; nb = x
        case 3:  nr = 0; ng = x; nb = c
        case 4:  nr = x; ng = 0; nb = c
        default: nr = c; ng = 0; nb = x
        }
        
        return Color(red: nr + m, green: ng + m, blue: nb + m)
    }
    
    var neon: Color { self.neon() }
}

// MARK: - String Extensions
extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isValidEmail: Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return range(of: regex, options: .regularExpression) != nil
    }
}

// MARK: - View Extensions
extension View {
    func neonGlow(color: Color = .blue, radius: CGFloat = 12) -> some View {
        self
            .shadow(color: color.neon(), radius: radius)
            .shadow(color: color.neon(), radius: radius / 2)
    }
}

struct CyanToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .tint(.cyan)
    }
}
