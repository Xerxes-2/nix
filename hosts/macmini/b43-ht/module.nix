# 只从内核源码里拿 b43 目录、打上本目录的补丁、按当前内核配置编成单独的 b43.ko，
# 装进 lib/modules/<ver>/updates/ 覆盖主线版本。改补丁后只重编这一个模块，几十秒。
{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  # 打开 b43 自带的 debugfs（/sys/kernel/debug/b43/phyN/{mmio,shm}16{read,write} 等），
  # 只影响这个模块，内核本身不用重编。
  debug ? false,
}:
stdenv.mkDerivation {
  pname = "b43-ht";
  version = kernel.version;
  src = kernel.src;
  unpackPhase = ''
    tar -xf $src --strip-components=1 --wildcards '*/drivers/net/wireless/broadcom/b43/*'
  '';
  patches = [ ./b43-ht-5ghz.patch ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "-C"
      "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "M=$(PWD)/drivers/net/wireless/broadcom/b43"
    ]
    ++ lib.optionals debug [
      "CONFIG_B43_DEBUG=y"
      "KCFLAGS=-DCONFIG_B43_DEBUG=1"
    ];
  buildFlags = [ "modules" ];
  installPhase = ''
    install -Dm644 drivers/net/wireless/broadcom/b43/b43.ko \
      $out/lib/modules/${kernel.modDirVersion}/updates/b43.ko
  '';
  meta.platforms = lib.platforms.linux;
}
