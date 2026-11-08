# How to build this shell so it feels good

These rules come from reading the five most popular Quickshell shells: caelestia, end-4's
illogical-impulse, dux-shell (formerly DankMaterialShell), serpantinum and Ambxst. They describe
how those shells are built. They don't prescribe a look, and none of their code was copied.
They exist because past builds of this bar looked fine as HTML mockups but felt cheap once they
were real QML. Each rule is followed by the reason for it.

## Windows and geometry

1. **Use one drawing window per screen and give it an input mask.** Make it a full-width overlay
   `PanelWindow` with `exclusionMode: Ignore`, and have its `mask: Region` follow the live,
   animated geometry of whatever is visible. When the bar and its popouts share one window
   they also share one coordinate space. That is the only way a popout can grow *out of* the
   bar, and the only way an open popout can slide to the next icon instead of closing and
   reopening.
2. **Reserve screen space with separate invisible windows.** A 1×1 `PanelWindow` per edge,
   with `mask: Region {}` and the bar's `exclusiveZone`, reserves the space. Because space is
   reserved apart from drawing, the drawn bar can grow and morph without pushing tiled
   windows around.
3. **Bind the mask to items, not to positions read once.** Each `Region { item: … }` should
   point at a live item. A `mapToItem` snapshot taken once goes stale, and part of the bar
   stops responding to clicks. Masks also ignore `scale` and transforms, so animate width
   and height, never `scale`, on anything that defines a hit area.
4. **Snap geometry to the device-pixel grid.** At a scale factor of 1.5, half-pixel edges
   blur 1px lines and text. Snap to whole device pixels, and use even values for anything
   centred.

## Motion

5. **Keep all motion in one token table.** Store every curve and duration in a singleton,
   behind one global speed multiplier, and give the singleton a reusable `Anim { type: … }`.
   Never write a bare `duration: 250` in a module. The tokens:

   | token | curve (bezier) | ms | use |
   |---|---|---|---|
   | spatial | 0.38, 1.21, 0.22, 1.00 | 500 | size and position, with a slight overshoot |
   | spatialFast | 0.42, 1.67, 0.21, 0.90 | 350 | small moves: indicators, chips |
   | effects | 0.34, 0.80, 0.34, 1.00 | 200 | opacity and colour, never overshoots |
   | enter | 0.05, 0.70, 0.10, 1.00 | 400 | things arriving |
   | exit | 0.30, 0.00, 0.80, 0.15 | 200 | things leaving: fast, no bounce |

6. **Choose the curve family by what moves.** Geometry uses the spatial curves, which may
   overshoot. Opacity and colour use the effects curve, which never overshoots: fading
   content that bounces looks broken.
7. **Animate the container, cross-fade the content.** Work out the next size in the same
   frame the content is chosen, by loading the next view before measuring it. Then spring
   the box to that size while the old content fades out over about 100ms and the new
   content fades in over about 200ms. Never let the content itself drive a size animation.
8. **Drive each piece of UI from one progress value.** Use a single `progress` (0 = closed,
   1 = open) and derive width, height, offset and opacity from it, rather than giving five
   properties five separate Behaviors. Openings then always stay in sync.
9. **Make opening and closing different.** Open with overshoot. Close quickly with the exit
   curve. Something leaving should never bounce.
10. **Gate Behaviors so idle changes don't animate.** A width Behavior should run only while
    something is opening or switching. A new track title should not make the bar wobble.
    Turn layout animation off during startup.

## Layout that never twitches

11. **Give changing text a fixed width.** Use tabular figures (`font.features: {"tnum": 1}`)
    and reserve width for the widest value (for a clock, `text.replace(/\d/g, "0")`). Give
    the centre slots fixed widths. A neighbour must never move because a number changed.
12. **Don't swap a field's content on hover if that changes its width.** A hover may reveal
    things inside space the field already reserves, or open a popout. It must never resize
    the field.
13. **Keep a fading item visible until its fade ends.** Set `visible: opacity > 0`, and
    position things with explicit x and animated width so neighbours slide rather than jump.

## Efficiency

14. **Load nothing until it's needed.** Every popout and panel is a `Loader` or `LazyLoader`
    with `active: open || closing`. Unload it after it closes, or keep a few warm on
    purpose.
15. **Count users of polled data.** A metrics source starts its timer when the first
    visible thing uses it and stops when the last one goes. Nothing should poll while it's
    off screen.
16. **Prefer native data, then file reads, then processes.** Use the Quickshell Hyprland,
    Pipewire, MPRIS, UPower and Bluetooth bindings first. Read `/proc` with `FileView` next.
    Spawn a `Process` only for one-off jobs, or keep one long-running stream; never fork
    every two seconds.
17. **Don't repaint the bar for decoration.** A looping Animation repaints the whole bar
    window at the display's refresh rate. Use a stepped Timer for slow pulses. Enable a
    layer or MultiEffect only while it is animating. Use `RectangularShadow { cached: true }`
    instead of a MultiEffect shadow, and never place a full-screen layer under a shadow.
18. **Don't animate variable-font axes continuously.** Every frame re-maps the font.
19. **Avoid binding churn.** Don't reassign a list that hasn't changed, don't use
    "revision counter" dummy reads, and use typed readonly properties instead of a
    `Connections` per delegate.

## Feel

20. **Make indicators feel physical.** The workspace highlight should animate its two edges
    separately: the edge in the direction of travel moves fast and the trailing edge
    follows, so it stretches and then settles.
21. **Pause before hover opens anything.** Wait about 120–200ms before opening on hover.
    Once one popout is open, moving to the next icon retargets it straight away.
22. **Draw one surface.** A popout that grows from the bar shares the bar's colour and joins
    it through concave fillets at the meeting corners, so it reads as the bar stretching
    and not as a second box.
