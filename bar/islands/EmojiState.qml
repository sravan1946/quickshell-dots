pragma Singleton
import QtQuick
import Quickshell

// The emoji picker (panels/Emoji.qml, SUPER+.). Data: scripts/emoji.tsv, built from Unicode's
// emoji-test, CLDR and emojilib keywords by scripts/emoji-data.py.
// Drawn with fonts/NotoColorEmoji-COLRv1.ttf: Noto's vector (COLRv1) build, renamed so only the
// bar uses it. The usual bitmap Noto Color Emoji came out blocky when Qt shrank it to 24px.
// From github.com/googlefonts/noto-emoji 2D/fonts/Noto-COLRv1.ttf (OFL), family renamed with
// fontTools (name IDs 1/4/16/18 "Noto Color Emoji COLRv1", 6 "NotoColorEmojiCOLRv1").
Singleton {
    readonly property alias data: d
    FontLoader { id: colr; source: Qt.resolvedUrl("../fonts/NotoColorEmoji-COLRv1.ttf") }
    PickerData {
        id: d
        name: "emoji"
        tsv: "emoji.tsv"
        font: colr.name || "Noto Color Emoji"
        groups: [
            { key: "", glyph: 0xF02DA, label: "Recent" },
            { key: "Smileys & Emotion", glyph: 0xF01F5 },
            { key: "People & Body", glyph: 0xF1822 },
            { key: "Animals & Nature", glyph: 0xF03E9 },
            { key: "Food & Drink", glyph: 0xF0C84 },
            { key: "Travel & Places", glyph: 0xF001D },
            { key: "Activities", glyph: 0xF04B8 },
            { key: "Objects", glyph: 0xF0336 },
            { key: "Symbols", glyph: 0xF02D5 },
            { key: "Flags", glyph: 0xF023D }
        ]
    }
}
