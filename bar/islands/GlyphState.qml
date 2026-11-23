pragma Singleton
import QtQuick
import Quickshell

// The Nerd Font glyph picker (panels/Glyphs.qml, SUPER+,). Data: scripts/glyphs.tsv, built from
// Nerd Fonts' glyphnames.json by scripts/glyph-data.py. Search "fa github" to stay in one set.
Singleton {
    readonly property alias data: d
    PickerData {
        id: d
        name: "glyph"
        noun: "glyphs"
        tsv: "glyphs.tsv"
        font: Look.icons
        tinted: true
        size: 20
        cols: 11
        groups: [
            { key: "", glyph: 0xF02DA, label: "Recent" },
            { key: "md", glyph: 0xF0986, label: "Material Design" },
            { key: "fa", glyph: 0xF005, label: "Font Awesome" },
            { key: "cod", glyph: 0xEAC4, label: "Codicons" },
            { key: "oct", glyph: 0xF408, label: "Octicons" },
            { key: "dev", glyph: 0xE702, label: "Devicons" },
            { key: "seti", glyph: 0xE615, label: "Seti" },
            { key: "linux", glyph: 0xF31A, label: "Linux logos" },
            { key: "weather", glyph: 0xE30D, label: "Weather" },
            { key: "other", glyph: 0xE0B0, label: "Powerline and the rest" }
        ]
    }
}
