# 跨机器共享的 CLI 工具集（Home Manager 模块，Linux/macOS 通用）。
# 各 host 的 home.nix 导入此模块，平台特有工具在各自 host 里追加。
{ lib, pkgs, ... }:
{
  # nh：nixos-rebuild / darwin-rebuild 的前端，自带 nvd 式的版本 diff 和构建树。
  # flake 写进 NH_FLAKE，`nh os switch` / `nh darwin switch` 不用再带路径；
  # 仓库在 NixOS 上的位置是 /etc/nixos，darwin 在 hosts/darwin/home.nix 覆盖。
  # 只用它做 rebuild：nh.clean 不开，定期 GC 仍由各系统的 nix.gc 负责
  # （NixOS 的 programs.nh.clean 与 nix.gc.automatic 互斥，没必要换）。
  programs.nh = {
    enable = true;
    flake = lib.mkDefault "/etc/nixos";
  };

  # 登录 shell。真正把 fish 设为登录 shell 的是各系统层的
  # `programs.fish.enable`（NixOS 上还有 `users.users.<u>.shell`；darwin 上
  # nix-darwin 的同名选项负责写 /etc/shells 和 vendor 补全）。
  #
  # 这里开的是 HM 模块，管 ~/.config/fish/config.fish，让 HM 装的包和
  # home.sessionVariables 在 fish 里也生效。
  programs.fish.enable = true;

  # 有几样自己交互时基本不碰，但编码 agent 会顺手就用（一没有就退化成
  # 手写一堆 shell 或者干脆放弃）：python3 / jq / yq-go 处理数据，file、dig、
  # socat 排查，nvd / nix-diff / nurl 专门伺候这个仓库的日常。
  home.packages = with pkgs; [
    bat
    btop
    claude-code
    codex
    curl
    difftastic
    dnsutils # dig / nslookup / nsupdate
    eza
    fastfetch
    fd
    file
    gh
    git
    go
    herdr
    htop
    jjui
    jq
    jujutsu
    lnav
    nano
    nixd
    nix-diff # 两个 drv 到底差在哪（rebuild 结果不符预期时）
    nixfmt
    nix-index
    nodejs-slim
    nurl # 加新包时自动出 fetcher + hash，省掉手抄 sha256
    nvd # rebuild 前后的包版本 diff
    osv-scanner
    pi-coding-agent
    pnpm
    powershell
    procs
    # 不含 pip/setuptools（nixpkgs 把 ensurepip 打断了），只是个能跑
    # 脚本的完整 stdlib；要临时装第三方库用 uv。
    python3
    ripgrep
    rsync
    sd
    socat
    sqlite
    steel
    steelix
    tldr
    tokei
    tombi
    tree
    unar
    unzip
    uv
    viddy
    vim
    vscode-json-languageserver
    wakatime-cli
    wget
    yazi
    yq-go
    zellij
    zip
  ];
}
