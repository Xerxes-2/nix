# Single source of truth for the built-in panel of the 14" MacBook Pro.
#
# Everything that has to line up with the notch is derived from the scale, so
# changing `scaleText` below is enough: the niri output, the bar's notch spacer
# and the bar thickness all follow.
{ }:
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

  # Centered spacer that keeps the bar widgets out of the notch.
  spacerSize = toLogical notchWidthPx;

  # Noctalia takes this verbatim as `[bar.main] thickness`, so the number the
  # notch needs is the number in the config - there is no upstream formula left
  # to keep in sync.
  barThickness = toLogical notchHeightPx;
}
