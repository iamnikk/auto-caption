import SwiftUI

/// Prompt 5: Style Customization Sheet
/// Live customization for font, size, text/highlight colors, vertical position, stroke, and animation.
public struct StyleCustomizationSheet: View {
    @Binding public var style: CaptionStyle
    @Environment(\.dismiss) private var dismiss
    
    // Bundled iOS system fonts with compatible licenses
    private let availableFonts: [(name: String, displayName: String)] = [
        ("HelveticaNeue-Black", "Helvetica Black"),
        ("AvenirNext-Heavy", "Avenir Heavy"),
        ("TrebuchetMS-Bold", "Trebuchet Bold"),
        ("Impact", "Impact"),
        ("MarkerFelt-Wide", "Marker Felt"),
        ("CourierNewPS-BoldMT", "Courier Mono"),
        ("Futura-Bold", "Futura Bold"),
        ("ArialRoundedMTBold", "Arial Rounded")
    ]
    
    public init(style: Binding<CaptionStyle>) {
        self._style = style
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Preset & Typography
                Section("Typography") {
                    Picker("Font Family", selection: $style.fontName) {
                        ForEach(availableFonts, id: \.name) { item in
                            Text(item.displayName).tag(item.name)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(style.fontSize)) pt").bold()
                        }
                        Slider(value: $style.fontSize, in: 20...56, step: 2)
                            .tint(.yellow)
                    }
                }
                
                // Section 2: Colors & Highlights
                Section("Color Palette") {
                    ColorPicker(
                        "Text Color",
                        selection: Binding(
                            get: { Color(hex: style.textColor) },
                            set: { style.textColor = $0.toHex() ?? "#FFFFFF" }
                        )
                    )
                    
                    ColorPicker(
                        "Highlight Color (Spoken Word)",
                        selection: Binding(
                            get: { Color(hex: style.highlightColor) },
                            set: { style.highlightColor = $0.toHex() ?? "#FFDE03" }
                        )
                    )
                }
                
                // Section 3: Position & Layout
                Section("Positioning") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Vertical Position")
                            Spacer()
                            Text(positionLabel(style.position.verticalOffsetPercentage)).bold()
                        }
                        Slider(value: $style.position.verticalOffsetPercentage, in: 0.15...0.85, step: 0.05)
                            .tint(.yellow)
                    }
                }
                
                // Section 4: Animation
                Section("Animation") {
                    Picker(
                        "Animation Style",
                        selection: Binding(
                            get: { style.animation },
                            set: { style.animation = $0 }
                        )
                    ) {
                        ForEach(CaptionAnimation.allCases) { anim in
                            Text(anim.rawValue).tag(anim)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Customize Style")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                        .foregroundColor(.yellow)
                }
            }
        }
    }
    
    private func positionLabel(_ val: CGFloat) -> String {
        if val <= 0.3 { return "Top" }
        if val >= 0.7 { return "Bottom / Lower Third" }
        return "Center"
    }
}

// MARK: - Color to Hex conversion helper
public extension Color {
    func toHex() -> String? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rgb: Int = (Int)(red * 255) << 16 | (Int)(green * 255) << 8 | (Int)(blue * 255) << 0
        return String(format: "#%06x", rgb)
        #else
        return nil
        #endif
    }
}
