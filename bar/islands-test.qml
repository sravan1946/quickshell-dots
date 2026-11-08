//@ pragma UseQApplication
// Test harness for the island bar: draws it only on the screen named in ISLANDS_SCREEN
// (a headless output while building), with nothing else the real shell runs.
// Run: ISLANDS_SCREEN=QSTEST qs -p islands-test.qml
import QtQuick
import Quickshell
import qs.islands

ShellRoot {
    Variants {
        model: Quickshell.screens.filter(s => s.name === Quickshell.env("ISLANDS_SCREEN"))
        IslandBar {}
    }
}
