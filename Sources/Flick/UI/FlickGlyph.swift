import SwiftUI

extension LinearGradient {
    static let flick = LinearGradient(
        colors: [Color(red: 0.227, green: 0.855, blue: 0.584),
                 Color(red: 0.071, green: 0.757, blue: 0.733)],
        startPoint: .top, endPoint: .bottom)
}

struct FlickBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.95, y: h * 0.15))
        p.addLine(to: CGPoint(x: w * 0.05, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0, y: h),
                       control: CGPoint(x: 0, y: h * 0.45))
        p.addQuadCurve(to: CGPoint(x: w * 0.95, y: h * 0.15),
                       control: CGPoint(x: w * 0.55, y: h * 0.35))
        p.closeSubpath()
        return p
    }
}

/// The Flick bubble glyph: a rounded-rect speech bubble with a pointed tail.
/// `knockoutGlyph` renders the F transparent (for template menu-bar images).
struct FlickBubbleGlyph: View {
    var side: CGFloat
    var bubbleStyle: AnyShapeStyle
    var glyphColor: Color
    var knockoutGlyph = false
    var glyphScale: CGFloat = 0.40

    var body: some View {
        ZStack {
            FlickBubbleTail()
                .fill(bubbleStyle)
                .frame(width: side * 0.30, height: side * 0.26)
                .offset(x: -side * 0.17, y: side * 0.30)
            RoundedRectangle(cornerRadius: side * 0.15, style: .continuous)
                .fill(bubbleStyle)
                .frame(width: side * 0.82, height: side * 0.64)
                .offset(y: -side * 0.06)
            glyphText
                .offset(y: -side * 0.06)
        }
        .compositingGroup()
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private var glyphText: some View {
        let text = Text("F")
            .font(.system(size: side * glyphScale, weight: .bold, design: .rounded))
        if knockoutGlyph {
            text.blendMode(.destinationOut)
        } else {
            text.foregroundStyle(glyphColor)
        }
    }
}
