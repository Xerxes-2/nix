# Single source of truth for the built-in panel of the 14" MacBook Pro.
#
# Everything that has to line up with the notch is derived from the scale, so
# changing `scaleText` below is enough: the niri output, the DMS notch spacer
# and the DMS bar thickness all follow.
{ lib }:
let
  # Written verbatim into niri's config.kdl, parsed for the notch math.
  scaleText = "1.75";
  scale = builtins.fromJSON scaleText;

  # Notch geometry in physical pixels.
  #
  # `appledrm.show_notch=1` makes the panel report 3024x1964 instead of the
  # 3024x1890 visible area, so the notch is exactly 74 physical rows tall.
  notchHeightPx = 74;
  # The width was measured on screen at scale 2.0 (220 logical pixels).
  notchWidthPx = 440;

  # Logical pixels needed to cover the given amount of physical pixels.
  toLogical = px: builtins.ceil (px / scale);
in
rec {
  inherit
    scale
    scaleText
    notchWidthPx
    notchHeightPx
    ;

  # Centered DMS spacer that keeps the bar widgets out of the notch.
  spacerSize = toLogical notchWidthPx;

  # DMS derives the bar thickness from the per-bar inner padding:
  #   max(max(20, 26 + 0.6 * p) + p + 4, Theme.barHeight - 4 - (8 - p))
  # With Theme.barHeight = 48 that is `36 + p` for the paddings we use, so pick
  # the padding that makes the opaque bar cover the whole notch.
  #
  # TODO revisit: on every dms-shell bump - if upstream changes that formula the
  # bar silently stops covering the notch
  #   check: `effectiveBarThickness` in Modules/DankBar/DankBarWindow.qml of the
  #          installed dms-shell (line 563 in 1.5.3)
  #   then:  update the formula above and the `36 +` below together
  #   last:  2026-09, dms-shell 1.5.3 - unchanged (still line 563, and
  #          Theme.barHeight is still 48)
  innerPadding = lib.max 4 (toLogical notchHeightPx - 36);

  barThickness = 36 + innerPadding;
}
