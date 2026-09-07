# ===== Ignition SCADA 网关（演示用，rootless 容器）=====
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # 8.3.9 aarch64，按 digest 钉死而不是 tag。tag 是可变引用：同一份配置在不同
  # 时间会解析到不同镜像，那种「声明式」是假的。
  # 换版本：podman manifest inspect docker.io/inductiveautomation/ignition:<tag>
  # 取 architecture=arm64 那条的 digest。
  image = "docker.io/inductiveautomation/ignition@sha256:56263d587676f128275d13609c2afb4edeb1fea4750a31cac37423acb21e37bd";

  user = "exka";
  home = "/var/lib/exka";

  # 恢复用的 .gwbk 是构建产物而不是配置，所以既不进这个仓库也不进 nix store：
  # 4MB、含五个开发账号的口令哈希，由 exka_scada 的 make_gwbk.sh --demo 产出。
  # 手工放到这个路径（见 README）。恢复只在数据卷为空时触发一次。
  restore = "${home}/restore.gwbk";

  port = 8088;
in
{
  # 专用系统用户，而不是本仓库其它服务惯用的 DynamicUser：rootless podman 需要
  # 持久的家目录（容器存储在 ~/.local/share/containers）和稳定的 subuid 段，
  # 两样 DynamicUser 都给不了。
  #
  # 也不复用 ubuntu —— 它虽然已经 linger=true 且分到了 subuid 段（那条注释写的
  # 正是「开机即拉起容器」），但它是 isNormalUser + wheel 的登录账号，拿它跑这个
  # 容器等于让逃逸落在一个能 sudo 的身份上。
  users.groups.${user}.gid = 3001;
  users.users.${user} = {
    isSystemUser = true;
    uid = 3001; # 静态 uid：nixbld 占 30000+，1001 是 ubuntu
    group = user;
    inherit home;
    createHome = true;
    # rootless 容器必须在开机（无人登录）时就起来。linger 关着的话
    # oci-containers 只给一条 warning，服务并不会因此报错，只是起不来。
    linger = true;
    # 系统用户默认不分配 subuid/subgid（只有 isNormalUser 默认分配），
    # 没有它 rootless podman 建不了用户命名空间。
    autoSubUidGidRange = true;
  };

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.ignition = {
    inherit image;
    podman.user = user;
    ports = [ "${toString port}:8088" ];
    volumes = [
      "ignition-data:/usr/local/bin/ignition/data"
      # :U 让 podman 把挂载源 chown 成容器用户。没有它网关以
      #   AccessDeniedException: /restore.gwbk
      # 失败：rootless 下宿主 exka(3001) 映射成容器内 root，而网关进程是容器内
      # ignition(2003)，读不了 0400 的 root 文件。
      # 副作用：宿主侧属主会被改成映射后的数字 uid（不再是 exka）。ls -l 看到
      # 陌生 uid 是预期的，不是文件坏了。
      "${restore}:/restore.gwbk:ro,U"
    ];
    environment = {
      ACCEPT_IGNITION_EULA = "Y";
      IGNITION_EDITION = "standard";
      GATEWAY_ADMIN_USERNAME = "admin";
      TZ = config.time.timeZone;
    };
    environmentFiles = [ config.sops.secrets."ignition-env".path ];
    # 刻意不传 -a / -h / -s（本机开发那份 quadlet 传了 -a localhost）。传了会把
    # 「公开地址」钉死成那个值，客户端拿到的跳转链接就指向那里；不传则
    # autoDetect=true，按请求实际用的主机名生成 —— 这正是 tailnet 访问需要的。
    # 实测：省掉三者容器正常启动，gateway.xml 里 autoDetect=true、地址为空。
    # 三者是一组，只给 -a/-h 会以「HTTPS Port not specified」直接退出。
    cmd = [
      "-n"
      "exka-demo"
      "-m"
      "2048"
      "-r"
      "/restore.gwbk"
    ];
  };

  # 只在 tailnet 内开放。公网防火墙仍然只有 22（network.nix），其余服务走
  # cloudflared 隧道 —— 但这个网关带管理员入口和设备写入能力，且演示包里五个
  # 账号是同一个开发口令，不适合放进面向公网的隧道。
  #
  # rootless podman 的端口转发由用户态进程 bind 宿主端口，是普通监听套接字，
  # 因此受 INPUT 链约束、这条规则生效。（root podman 走 DNAT/FORWARD，
  # 会绕过只过滤 INPUT 的 nixos 防火墙 —— 那是选 rootless 的第二个理由。）
  # 部署后仍要从公网侧实测一次，见 README。
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ port ];
}
