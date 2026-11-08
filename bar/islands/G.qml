import QtQuick

// One Nerd Font glyph, by codepoint.
Text {
    property int glyph
    text: String.fromCodePoint(glyph)
    color: Qt.alpha(Look.text, 0.86)
    font.family: Look.icons
    font.pixelSize: 13
    // a full item's height, centred: a Row top-aligns, and the glyph sat high next to text
    height: Look.item
    verticalAlignment: Text.AlignVCenter
}
