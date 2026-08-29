# ===== chive 虚拟仓（Breakout）=====
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  chive = inputs.chive.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # `chive paper` 跟着币安的公开成交流跑一个模拟账本：不下单、不签名、不读私钥，
  # 所以这个服务的密钥面是空的，sops 里没有它的东西。
  #
  # 它只有一样东西不可再生：archive/<SYMBOL>.toml —— 每 symbol 一份、几 KB 的
  # 人可读 TOML，每 60 秒原子重写（先 .part 再 rename），重启时靠它把 55 天的
  # Channel、手上的 Holding、Risk Line 和飞在半路的委托一起接回来。
  # 而 aggTrades 缓存是币安的公开档案：56 天热身就要 6-8 GB CSV，随时可重下。
  #
  # 这两者的保留价值差三个数量级，所以让它们分居两个子卷：
  #   /var/lib/chive    @varlib —— snapper 每小时快照 + restic 每日异地备份
  #   /var/cache/chive  @cache  —— 不快照、不备份、可随时清空
  # 若把缓存也放进 @varlib，等于每小时给几 GB 可重下的公共数据做快照、
  # 每天把它们传去对象存储，还让 bees 白扫一遍唯一数据。
  #
  # chive 的三个路径（archive/、aggtrades/、rules-snapshot.toml）都相对工作目录，
  # 所以工作目录设在状态那一侧，只把大的那个用 symlink 引去 @cache：
  # 将来它若新写出什么文件，落点默认是"被快照被备份"，而不是"随时会被清掉"。
  systemd.services.chive-paper = {
    description = "chive paper run (Breakout tenant)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # 一个不可信的 Archive（被改过、截断、版本与 config 不符、两个 tenant 的段
    # 同时在场）会让 chive 拒绝启动而不是静默重建一个空策略。配上 Restart=always
    # 就必须给次数上限，否则它会以 60 秒周期无声地转圈：五次之后进 failed，
    # OnFailure 把 systemctl status 推到手机上（见 ntfy.nix 的 monitoredUnits）。
    startLimitBurst = 5;
    startLimitIntervalSec = 3600;

    serviceConfig = {
      Type = "simple";
      ExecStartPre = [
        # 配置的真源在 git 里，每次启动覆盖机器上那份。
        "${pkgs.coreutils}/bin/install -m 0644 ${../chive.toml} /var/lib/chive/chive.toml"
        # 幂等：把缓存目录挂到工作目录下 chive 唯一认识的那个名字上。
        "${pkgs.coreutils}/bin/ln -sfn /var/cache/chive /var/lib/chive/aggtrades"
      ];
      ExecStart = "${lib.getExe chive} paper";

      User = "chive";
      Group = "chive";
      StateDirectory = "chive";
      CacheDirectory = "chive";
      # 0755 是故意的：archive/*.toml 就是给人读的运行状态，
      # 而缓存要能被手动跑的复核 Backtest 读到（见 README）。
      StateDirectoryMode = "0755";
      CacheDirectoryMode = "0755";
      WorkingDirectory = "/var/lib/chive";

      # 杀掉与干净停止在 chive 里是同一件事（Archive 每分钟落盘，
      # 缺口由下次启动的 catch-up 补上），所以不需要优雅关停的余地。
      Restart = "always";
      RestartSec = "60s";

      # 只需要出站 HTTPS/WSS 和自己那两个目录，其余一概关掉。
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ];
      # AF_UNIX 是给 glibc 的名字解析留的，不是给 chive 的。
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  users.users.chive = {
    isSystemUser = true;
    group = "chive";
    description = "chive paper run";
  };
  users.groups.chive = { };

  # 缓存按龄清理。安全的前提是 chive 自己给的：缺一份 Bundle 只会被重新下载，
  # 状态在 Archive 里而不在这里。180 天而不是 90 天，是为了留出足够长的窗口
  # 让"拿虚拟仓期间的行情跑一遍 Backtest 对账"这件事不必重下几个 GB。
  systemd.tmpfiles.rules = [
    "d /var/cache/chive 0755 chive chive 180d"
  ];

  # 手动跑复核 Backtest 用（README 里那条命令）。同一个包，同一个二进制，
  # 因此手里对的账和服务跑的账不会来自两份编译。
  environment.systemPackages = [ chive ];
}
