import QtQuick
import qs
import qs.islands

// Screen brightness. Scrolling on the bar's icon changes it too.
Panel {
    implicitWidth: 260
    Head { text: "Brightness"; note: "scroll on the icon to change" }
    Row {
        width: parent.width
        spacing: 10
        G { glyph: 0xF00DF; color: Look.text; width: 18 }
        Slide { width: parent.width - 72; value: Brightness.pct / 100; onMoved: v => Brightness.set(v * 100) }
        T { width: 34; horizontalAlignment: Text.AlignRight; text: Brightness.pct + "%"; color: Look.dim }
    }
}
