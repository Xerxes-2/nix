# Keep the familiar scrolling layout and key positions during the migration.
# Action names follow https://docs.noctalia.dev/umbriel/actions/.
{ display }:
{
  # Noctalia writes only this optional palette, not the read-only main config.
  include.optional.files = [ "noctalia.toml" ];

  # Noctalia and voxtype are started by graphical-session.target, after
  # start-umbriel has published the Wayland and X11 environment.
  general = {
    show_cheatsheet = false;
    focus_on_activate = true;
    # Keep X11 apps and Steam sharp at the panel's fractional scale.
    xwayland_native_resolution = true;
  };

  # Leave mode automatic so the preferred 120 Hz mode includes the notch rows.
  output.eDP-1.scale = display.scale;
  input = {
    keyboard.numlock_toggle = true;
    touchpad = {
      # Physical clicks are intentional; natural scrolling matches macOS.
      tap = false;
      natural_scroll = true;
    };
  };
  layout = {
    mode = "scrolling";
    gap = 16;
    extent_presets = [
      0.33333
      0.5
      0.66667
    ];
    scrolling.default_extent_fraction = 0.5;
  };
  appearance = {
    prefer_no_csd = true;
    border_width = 4;
    corner_radius = 12;
    title_bar.mode = "off";
    # Avoid adding continuous blur work on the laptop GPU.
    blur.enabled = false;
    shadow.enabled = false;
  };
  window_rule = [
    {
      match.app_id = "^dev[.]noctalia[.]Noctalia$";
      default_floating = true;
      default_floating_size_px = {
        width = 1080;
        height = 920;
      };
    }
    {
      match.app_id = "firefox$";
      match.title = "^Picture-in-Picture$";
      default_floating = true;
    }
  ];
  hot_corners.top_left = {
    enabled = true;
    delay_ms = 500;
    action = "overview-open";
  };

  # Defining keybinds replaces upstream defaults. F5/KEY_MICMUTE stays free
  # for voxtype's evdev push-to-talk, so it must never mute the microphone here.
  # Screenshots use Noctalia to preserve Cmd+Shift+3/4/5 and clipboard behavior.
  keybinds = {
    "Mod+Ctrl+R" = "window-set-secondary-extent 1.0";
    "Mod+Shift+Slash" = "cheatsheet-toggle";
    "Mod+T" = {
      action = "spawn alacritty";
      repeat = false;
    };
    "Mod+D" = {
      action = "spawn noctalia msg panel-toggle launcher";
      repeat = false;
    };
    "Super+Alt+L" = {
      action = "spawn noctalia msg session lock";
      repeat = false;
    };
    "Mod+S" = {
      action = "spawn noctalia msg panel-toggle control-center";
      repeat = false;
    };
    "Super+Alt+S" = {
      action = "spawn pkill orca || exec orca";
      allow_when_locked = true;
    };
    "XF86AudioRaiseVolume" = {
      action = "spawn noctalia msg volume-up 5";
      allow_when_locked = true;
    };
    "XF86AudioLowerVolume" = {
      action = "spawn noctalia msg volume-down 5";
      allow_when_locked = true;
    };
    "XF86AudioMute" = {
      action = "spawn noctalia msg volume-mute";
      allow_when_locked = true;
    };
    "XF86AudioPlay" = {
      action = "spawn noctalia msg media toggle";
      allow_when_locked = true;
    };
    "XF86AudioStop" = {
      action = "spawn noctalia msg media stop";
      allow_when_locked = true;
    };
    "XF86AudioPrev" = {
      action = "spawn noctalia msg media previous";
      allow_when_locked = true;
    };
    "XF86AudioNext" = {
      action = "spawn noctalia msg media next";
      allow_when_locked = true;
    };
    "XF86MonBrightnessUp" = {
      action = "spawn noctalia msg brightness-up current 5";
      allow_when_locked = true;
    };
    "XF86MonBrightnessDown" = {
      action = "spawn noctalia msg brightness-down current 5";
      allow_when_locked = true;
    };
    "XF86KbdBrightnessUp" = {
      action = "spawn noctalia msg keyboard-backlight-up";
      allow_when_locked = true;
    };
    "XF86KbdBrightnessDown" = {
      action = "spawn noctalia msg keyboard-backlight-down";
      allow_when_locked = true;
    };
    "Mod+F6" = {
      action = "spawn noctalia msg keyboard-backlight-up";
      allow_when_locked = true;
    };
    "Mod+F5" = {
      action = "spawn noctalia msg keyboard-backlight-down";
      allow_when_locked = true;
    };
    "Mod+O" = {
      action = "overview-toggle";
      repeat = false;
    };
    "Mod+Q" = {
      action = "window-close";
      repeat = false;
    };
    "Mod+Left" = "window-focus-left";
    "Mod+Down" = "window-focus-down";
    "Mod+Up" = "window-focus-up";
    "Mod+Right" = "window-focus-right";
    "Mod+H" = "window-focus-left";
    "Mod+J" = "window-focus-down";
    "Mod+K" = "window-focus-up";
    "Mod+L" = "window-focus-right";
    "Mod+Ctrl+Left" = "column-move-left";
    "Mod+Ctrl+Down" = "window-move-down";
    "Mod+Ctrl+Up" = "window-move-up";
    "Mod+Ctrl+Right" = "column-move-right";
    "Mod+Ctrl+H" = "column-move-left";
    "Mod+Ctrl+J" = "window-move-down";
    "Mod+Ctrl+K" = "window-move-up";
    "Mod+Ctrl+L" = "column-move-right";
    "Mod+Home" = "column-focus-first";
    "Mod+End" = "column-focus-last";
    "Mod+Ctrl+Home" = "column-move-to-first";
    "Mod+Ctrl+End" = "column-move-to-last";
    "Mod+Shift+Left" = "output-focus-left";
    "Mod+Shift+Down" = "output-focus-down";
    "Mod+Shift+Up" = "output-focus-up";
    "Mod+Shift+Right" = "output-focus-right";
    "Mod+Shift+H" = "output-focus-left";
    "Mod+Shift+J" = "output-focus-down";
    "Mod+Shift+K" = "output-focus-up";
    "Mod+Shift+L" = "output-focus-right";
    "Mod+Shift+Ctrl+Left" = "column-move-to-output-left";
    "Mod+Shift+Ctrl+Down" = "column-move-to-output-down";
    "Mod+Shift+Ctrl+Up" = "column-move-to-output-up";
    "Mod+Shift+Ctrl+Right" = "column-move-to-output-right";
    "Mod+Shift+Ctrl+H" = "column-move-to-output-left";
    "Mod+Shift+Ctrl+J" = "column-move-to-output-down";
    "Mod+Shift+Ctrl+K" = "column-move-to-output-up";
    "Mod+Shift+Ctrl+L" = "column-move-to-output-right";
    "Mod+Page_Down" = "workspace-next";
    "Mod+Page_Up" = "workspace-previous";
    "Mod+U" = "workspace-next";
    "Mod+I" = "workspace-previous";
    "Mod+Ctrl+Page_Down" = "column-move-to-workspace-next";
    "Mod+Ctrl+Page_Up" = "column-move-to-workspace-previous";
    "Mod+Ctrl+U" = "column-move-to-workspace-next";
    "Mod+Ctrl+I" = "column-move-to-workspace-previous";
    "Mod+Shift+Page_Down" = "workspace-move-down";
    "Mod+Shift+Page_Up" = "workspace-move-up";
    "Mod+Shift+U" = "workspace-move-down";
    "Mod+Shift+I" = "workspace-move-up";
    "Mod+WheelDown" = {
      action = "workspace-next";
      cooldown_ms = 150;
    };
    "Mod+WheelUp" = {
      action = "workspace-previous";
      cooldown_ms = 150;
    };
    "Mod+Ctrl+WheelDown" = {
      action = "column-move-to-workspace-next";
      cooldown_ms = 150;
    };
    "Mod+Ctrl+WheelUp" = {
      action = "column-move-to-workspace-previous";
      cooldown_ms = 150;
    };
    "Mod+WheelRight" = "window-focus-right";
    "Mod+WheelLeft" = "window-focus-left";
    "Mod+Ctrl+WheelRight" = "column-move-right";
    "Mod+Ctrl+WheelLeft" = "column-move-left";
    "Mod+Shift+WheelDown" = "window-focus-right";
    "Mod+Shift+WheelUp" = "window-focus-left";
    "Mod+Ctrl+Shift+WheelDown" = "column-move-right";
    "Mod+Ctrl+Shift+WheelUp" = "column-move-left";
    "Mod+1" = "workspace-switch 1";
    "Mod+2" = "workspace-switch 2";
    "Mod+3" = "workspace-switch 3";
    "Mod+4" = "workspace-switch 4";
    "Mod+5" = "workspace-switch 5";
    "Mod+6" = "workspace-switch 6";
    "Mod+7" = "workspace-switch 7";
    "Mod+8" = "workspace-switch 8";
    "Mod+9" = "workspace-switch 9";
    "Mod+Ctrl+1" = "column-move-to-workspace 1";
    "Mod+Ctrl+2" = "column-move-to-workspace 2";
    "Mod+Ctrl+3" = "column-move-to-workspace 3";
    "Mod+Ctrl+4" = "column-move-to-workspace 4";
    "Mod+Ctrl+5" = "column-move-to-workspace 5";
    "Mod+Ctrl+6" = "column-move-to-workspace 6";
    "Mod+Ctrl+7" = "column-move-to-workspace 7";
    "Mod+Ctrl+8" = "column-move-to-workspace 8";
    "Mod+Ctrl+9" = "column-move-to-workspace 9";
    "Mod+BracketLeft" = "window-consume-or-expel-left";
    "Mod+BracketRight" = "window-consume-or-expel-right";
    "Mod+Comma" = "window-consume-from-right";
    "Mod+Period" = "window-move-right";
    "Mod+R" = "window-cycle-primary-extent";
    "Mod+Shift+R" = "window-cycle-primary-extent-back";
    "Mod+Ctrl+Shift+R" = "window-cycle-secondary-extent";
    "Mod+F" = {
      action = "window-toggle-maximize";
      repeat = false;
    };
    "Mod+Shift+F" = {
      action = "window-toggle-fullscreen";
      repeat = false;
    };
    "Mod+M" = {
      action = "window-toggle-maximize-to-edges";
      repeat = false;
    };
    "Mod+C" = "column-center";
    "Mod+Minus" = "window-modify-primary-extent -0.1";
    "Mod+Equal" = "window-modify-primary-extent +0.1";
    "Mod+Shift+Minus" = "window-modify-secondary-extent -0.1";
    "Mod+Shift+Equal" = "window-modify-secondary-extent +0.1";
    "Mod+V" = {
      action = "window-toggle-floating";
      repeat = false;
    };
    "Mod+Shift+V" = {
      action = "window-focus-switch-floating";
      repeat = false;
    };
    "Mod+W" = {
      action = "column-toggle-tabbed";
      repeat = false;
    };
    "Mod+Shift+3" = {
      action = "spawn noctalia msg screenshot-fullscreen --no-show-cursor --copy-to-clipboard --save-to-file";
      repeat = false;
    };
    "Mod+Shift+4" = {
      action = "spawn noctalia msg screenshot-region --no-show-cursor --copy-to-clipboard --save-to-file";
      repeat = false;
    };
    "Mod+Shift+5" = {
      action = "spawn noctalia msg screenshot-window --no-show-cursor --copy-to-clipboard --save-to-file";
      repeat = false;
    };
    "Mod+Ctrl+Shift+3" = {
      action = "spawn noctalia msg screenshot-fullscreen --no-show-cursor --copy-to-clipboard --no-save-to-file";
      repeat = false;
    };
    "Mod+Ctrl+Shift+5" = {
      action = "spawn noctalia msg screenshot-window --no-show-cursor --copy-to-clipboard --no-save-to-file";
      repeat = false;
    };
    "Print" = {
      action = "spawn noctalia msg screenshot-region --no-show-cursor --copy-to-clipboard --save-to-file";
      repeat = false;
    };
    "Ctrl+Print" = {
      action = "spawn noctalia msg screenshot-fullscreen --no-show-cursor --copy-to-clipboard --save-to-file";
      repeat = false;
    };
    "Alt+Print" = {
      action = "spawn noctalia msg screenshot-window --no-show-cursor --copy-to-clipboard --save-to-file";
      repeat = false;
    };
    "Mod+Escape" = {
      action = "shortcuts-inhibit-toggle";
      allow_when_inhibited = true;
    };
    "Mod+Shift+E" = {
      action = "session-quit";
      repeat = false;
    };
    "Ctrl+Alt+Delete" = {
      action = "session-quit";
      repeat = false;
    };
    "Mod+Shift+P" = "dpms-off";
  };
}
