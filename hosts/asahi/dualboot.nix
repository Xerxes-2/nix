# 与同一块盘上的 macOS 共存所需的东西。
#
# macOS 侧自身的配置是 flake.nix 里的 `homeConfigurations.xerxes2`，与本文件无关；
# 这里只管从 Linux 这边操作启动盘、以及读 macOS 写进 NVRAM 的那些东西。
{ pkgs, ... }:
let
  # 启动盘的选择存在 NOR flash 的 NVRAM 里（/dev/mtd0），只有 root 能写，所以下面
  # 的脚本要走 sudo。`--next` 只改下一次启动，默认启动盘仍是 NixOS——从 macOS 重启
  # 回来就自动是 Linux，不需要事后再 bless 回去。
  blessMacos = "${pkgs.asahi-bless}/bin/asahi-bless --next --set-boot-macos -y";

  # 刻意不做成"点一下立刻重启"：DMS 的启动器是模糊搜索，输入 "mac" 回车就重启会
  # 丢掉没保存的东西。默认只是给下次启动打个标记，之后正常关机/重启即可；真想一步
  # 到位就 `boot-macos --now`，或者在终端里跑然后回答那个确认。
  boot-macos = pkgs.writeShellApplication {
    name = "boot-macos";
    # sudo 来自 /run/wrappers，不在 runtimeInputs 里。
    runtimeInputs = [
      pkgs.libnotify
      pkgs.systemd
    ];
    text = ''
      sudo ${blessMacos}

      msg="下次启动：macOS（默认启动盘不变）"
      echo "$msg"
      notify-send -a boot-macos "Boot macOS" "$msg" || true

      if [ "''${1-}" = "--now" ]; then
        systemctl reboot
      elif [ -t 0 ]; then
        read -rp "现在重启？[y/N] " reply
        if [ "$reply" = y ] || [ "$reply" = Y ]; then
          systemctl reboot
        fi
      fi
    '';
  };

  boot-macos-desktop = pkgs.makeDesktopItem {
    name = "boot-macos";
    desktopName = "Boot macOS Next";
    comment = "把下次启动切到 macOS（不会立刻重启）";
    icon = "system-reboot";
    exec = "${boot-macos}/bin/boot-macos";
    categories = [ "System" ];
  };
in
{
  # 只放行这一条完整命令行（sudoers 是按解析后的绝对路径加参数逐字匹配的，所以脚本
  # 里也用同一个 store 路径调用）。能设的只有"下次启动去 macOS"，越权的最坏结果就是
  # 下次开机进了另一个系统。
  security.sudo.extraRules = [
    {
      users = [ "xerxes2" ];
      commands = [
        {
          command = blessMacos;
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  environment.systemPackages = [
    # 列出/交互式选择启动盘：`sudo asahi-bless -l`。
    pkgs.asahi-bless
    boot-macos
    boot-macos-desktop

    # macOS 把蓝牙配对密钥和 Wi-Fi 密码也写在同一块 NVRAM 里，这两个工具把它们搬到
    # bluez / NetworkManager，省掉每次切系统都要重新配对耳机、重输密码：
    #
    #   sudo asahi-btsync list && sudo asahi-btsync sync
    #   sudo asahi-wifisync list && sudo asahi-wifisync sync
    #
    # 刻意不做成开机自动跑的 service：配对不常变，而 sync 会去改 /var/lib/bluetooth
    # 并让 bluetoothd 重载配置，没理由每次开机都动一遍。在 macOS 侧配好新设备之后手
    # 动跑一次就够了。
    pkgs.asahi-btsync
    pkgs.asahi-wifisync

    # 直接读写 NVRAM 变量（boot-args 之类），上面两个工具的底座。
    pkgs.asahi-nvram
  ];
}
