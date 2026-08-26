# Initial DankMaterialShell settings: the notch-aware bar layout.
#
# This seeds ~/.config/DankMaterialShell/settings.json once and is what the
# greeter renders; DMS keeps writing that file at runtime, so anything changed
# through the DMS UI afterwards stays.
{ display }:
{
  configVersion = 13;
  iconThemeDark = "Adwaita";
  iconThemeLight = "Adwaita";
  barConfigs = [
    {
      id = "default";
      name = "Main Bar";
      enabled = true;
      position = 0;
      screenPreferences = [ "all" ];
      showOnLastDisplay = true;

      # Widgets are anchored to both edges so the center stays free for the
      # notch; the spacer is sized from the display scale.
      leftWidgets = [
        "launcherButton"
        "workspaceSwitcher"
        "focusedWindow"
        "music"
      ];
      centerWidgets = [
        {
          id = "spacer";
          size = display.spacerSize;
        }
      ];
      rightWidgets = [
        "clock"
        "systemTray"
        "clipboard"
        "cpuUsage"
        "memUsage"
        "notificationButton"
        "battery"
        "controlCenterButton"
      ];

      # Flush, opaque black bar tall enough to cover the notch.
      spacing = 0;
      innerPadding = display.innerPadding;
      barInsetPadding = -1;
      bottomGap = 0;
      transparency = 1.0;
      backgroundColor = "#000000";
      widgetTransparency = 1.0;
      squareCorners = true;
      noBackground = false;

      maximizeWidgetIcons = false;
      maximizeWidgetText = false;
      removeWidgetPadding = false;
      widgetPadding = 8;
      gothCornersEnabled = false;
      gothCornerRadiusOverride = false;
      gothCornerRadiusValue = 12;
      borderEnabled = false;
      borderColor = "surfaceText";
      borderOpacity = 1.0;
      borderThickness = 1;
      widgetOutlineEnabled = false;
      widgetOutlineColor = "primary";
      widgetOutlineOpacity = 1.0;
      widgetOutlineThickness = 1;
      fontScale = 1.0;
      iconScale = 1.0;
      autoHide = false;
      autoHideStrict = false;
      autoHideDelay = 250;
      showOnWindowsOpen = false;
      openOnOverview = false;
      visible = true;
      popupGapsAuto = true;
      popupGapsManual = 4;
      maximizeDetection = true;
      useOverlayLayer = false;
      scrollEnabled = true;
      scrollXBehavior = "column";
      scrollYBehavior = "workspace";
      shadowIntensity = 0;
      shadowOpacity = 60;
      shadowColorMode = "default";
      shadowCustomColor = "#000000";
      clickThrough = false;
      hoverPopouts = false;
      hoverPopoutDelay = 150;
    }
  ];
}
