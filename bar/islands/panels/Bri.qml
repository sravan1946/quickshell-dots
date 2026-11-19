import QtQuick
import qs
import qs.islands

// Screen brightness: the whole card is one fat track, warm where it's lit, and the sun rides the
// edge of the light. Drag or click anywhere on it; scroll for 1% a notch (Shift for 5%). It never
// goes below 1%, so the screen never goes fully black. Night light lives in quick settings.
Panel {
    implicitWidth: 280
    Track {
        width: parent.width
        value: Brightness.pct / 100
        tint: Look.warm
        floor: 0.01
        glyph: value < 0.34 ? 0xF00DE : value < 0.67 ? 0xF00DF : 0xF00E0
        text: Brightness.pct + "%"
        onMoved: v => Brightness.set(v * 100)
    }
}
