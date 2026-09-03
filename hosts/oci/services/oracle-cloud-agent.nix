# ===== Oracle Cloud Agent（只跑 gomon：实例指标上报）=====
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # OCI 控制台实例页那一屏图（CPU / 内存 / 磁盘 / 网络 / 负载，命名空间
  # oci_computeagent）全部由 Oracle Cloud Agent 里的 gomon 插件主动上报；
  # 没有 agent 就只剩 oci_vcn（VNIC 流量）和 oci_blockstore（卷 IOPS）——
  # 那两个是虚拟化层采的，跟机器内部无关。LUSTRATE 掉 Ubuntu 时把 Oracle
  # 装的那个 snap 一起带走了，所以这里把它重新装回来。
  #
  # nixpkgs 没有 oracle-cloud-agent，Oracle 只发 Oracle Linux 的 RPM 和
  # Ubuntu 的 snap。取 snap 是因为：snap 里的 agent / gomon 是**静态链接**的
  # Go 二进制（`ldd` 报 not a dynamic executable），不需要 snapd、不需要
  # patchelf、不需要 FHS 环境，解包即用。snap 里另外那 300 多 MB 的 embedded
  # glibc 是 snapcraft 的打包习惯，用不上。
  #
  # 同一个二进制原生支持 RPM 布局（配置 /etc/oracle-cloud-agent、状态
  # /var/lib/oracle-cloud-agent、日志 /var/log/oracle-cloud-agent），所以不需要
  # 伪造 /snap 路径。
  #
  # TODO revisit: 想升级 agent，或 gomon 上报开始报错时
  #   check: curl -sH 'Snap-Device-Series: 16' \
  #            'https://api.snapcraft.io/v2/snaps/info/oracle-cloud-agent?architecture=arm64&fields=download,version,revision' \
  #          看 latest/stable 的 revision 与 version
  #   then:  换下面的 revision / version / hash，rebuild 后确认日志里有
  #          "Sent metrics status: 200"
  #   last:  2026-09，1.61.0-6（snap revision 125）仍是 latest/stable，
  #          monitoring.log 里每分钟一条 "Sent metrics status: 200"
  version = "1.61.0-6";
  revision = "125";

  oca = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "oracle-cloud-agent";
    inherit version;

    # snap store 的下载地址按 revision 定死，内容不可变，适合 fetchurl。
    # 这个 URL 只有 arm64 的包，换架构要重新查（见上面的 check）。
    src = pkgs.fetchurl {
      url = "https://api.snapcraft.io/api/v1/snaps/download/ltx4XjES2e2ujitNIuO5GxPYDM6lp6ry_${revision}.snap";
      hash = "sha256-U83Y/hO6XLgDcGIgAXFFpUgyme8j3c45Gzz5mYZbM+M=";
    };

    nativeBuildInputs = [ pkgs.squashfsTools ];

    unpackPhase = ''
      runHook preUnpack
      unsquashfs -no-progress -dest snap $src
      sourceRoot=snap
      runHook postUnpack
    '';

    # 只装 agent 本体和 gomon。其余插件一律不进 store：runcommand / oci-osmh /
    # oci-blockautoconfig 会去调 apt、yum、multipath、systemctl 改系统，在 NixOS
    # 上要么无效要么有害；unifiedmonitoring 是 Oracle 打包的 Fluentd，一整套
    # embedded Ruby 3.3 + 136 个 gem、318 MB、unit 里写着 MemoryMax=5G——
    # Ubuntu 时代它在这台机器上空转吃了几百 MB 内存（fluentd.conf 是 0 字节，
    # 因为控制台侧没配任何日志采集）。它也是那个"内存占用很大的 ruby 应用"。
    installPhase = ''
      runHook preInstall
      install -Dm755 agent $out/bin/oracle-cloud-agent
      install -Dm755 plugins/gomon/gomon $out/libexec/oracle-cloud-agent/plugins/gomon/gomon
      # gomon 硬编码优先读 /etc/oracle-cloud-agent/plugins/gomon/config.yml，
      # 这份原样存进 store 再由 environment.etc 链过去，跟着版本一起升级。
      install -Dm644 plugins/gomon/config/config.yml \
        $out/share/oracle-cloud-agent/gomon-config.yml
      runHook postInstall
    '';

    # 静态 Go 二进制：strip 没收益，patchelf 无对象。
    dontStrip = true;
    dontPatchELF = true;

    meta = {
      description = "Oracle Cloud Infrastructure 实例 agent（本仓库只启用 gomon 指标插件）";
      homepage = "https://docs.oracle.com/iaas/Content/Compute/Tasks/manage-plugins.htm";
      # 闭源二进制，Oracle 的许可随 OCI 服务条款。
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  });

  # agent.yml 只声明 gomon 一个插件。控制台侧另有几个插件的期望状态是 ENABLED
  # （Custom Logs Monitoring、Cloud Guard Workload Protection），agent 读不到对应
  # 条目就直接跳过、不报错——实测日志里只有 gomon 的行。想彻底安静可以去控制台把
  # 那几项的期望状态也改成 DISABLED。
  agentConfig = (pkgs.formats.yaml { }).generate "oracle-cloud-agent.yml" {
    logDir = "/var/log/oracle-cloud-agent";
    agentHardStopInterval = "25s";
    pluginHardStopInterval = "20s";
    pluginHealthCheckInterval = "10m";
    logAllResources = false;
    plugins.gomon = {
      disabled = false;
      exec = "${oca}/libexec/oracle-cloud-agent/plugins/gomon/gomon";
      winexec = "";
      elevated = false;
      args = [ ];
      # 上游默认值。agent 只在这两项存在时才按 systemd-run 施加限额，
      # 删掉会让它走另一条代码路径，没必要试。
      resourceConstraints = {
        cpu = 1;
        memory = 1;
      };
    };
  };
in
{
  assertions = [
    {
      assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
      message = "oracle-cloud-agent.nix 里 pin 的是 arm64 snap，换架构要换 URL 和 hash";
    }
  ];

  environment.etc."oracle-cloud-agent/plugins/gomon/config.yml".source =
    "${oca}/share/oracle-cloud-agent/gomon-config.yml";

  systemd.services.oracle-cloud-agent = {
    description = "Oracle Cloud Agent（gomon：向 OCI Monitoring 上报实例指标）";
    wantedBy = [ "multi-user.target" ];
    # 起来第一件事就是找 169.254.169.254 和 telemetry-ingestion 端点。
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # agent 按 resourceConstraints 用 systemd-run 拉插件时要能找到它；
    # NixOS 上没有 /usr/bin/systemd-run。
    path = [ pkgs.systemd ];

    serviceConfig = {
      ExecStart = "${oca}/bin/oracle-cloud-agent -agent-config ${agentConfig}";
      Restart = "always";
      RestartSec = 10;
      # agentHardStopInterval 是 25s，别在它收尾前就 SIGKILL。
      TimeoutStopSec = 30;

      # agent 自己在这两个子目录下放插件状态。
      StateDirectory = [
        "oracle-cloud-agent"
        "oracle-cloud-agent/tmp"
        "oracle-cloud-agent/reattach"
      ];
      LogsDirectory = [
        "oracle-cloud-agent"
        "oracle-cloud-agent/plugins/gomon"
      ];

      # root 运行：gomon 要读全机 /proc 才能算出 CPU / 内存 / 磁盘 IO。
      # 加固刻意保持温和——它是个闭源二进制，收得太紧只会换来难查的静默失效。
      # 三条边界值得设：
      NoNewPrivileges = true; # gomon 是 elevated:false，不需要提权
      ProtectKernelTunables = true; # 只上报，不该写 /proc/sys
      ProtectKernelModules = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallFilter = [ "@system-service" ];
      SystemCallArchitectures = "native";
      # 探测元数据时会先试 IPv6，再走 IPv4；网络统计走 netlink。
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
      # 故意不设 PrivateTmp：agent 与 gomon 之间是 hashicorp go-plugin 的
      # unix socket，将来若真让 systemd-run 把插件拉进独立单元，独立的 /tmp
      # 命名空间会让双方看不见同一个 socket。
      # 也不设 ProtectHome：gomon 遍历挂载点统计磁盘，/home 是独立子卷。
    };
  };
}
