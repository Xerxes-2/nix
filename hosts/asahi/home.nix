{ ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.xerxes2 = {
      imports = [ ../../modules/home/cli.nix ];

      programs.home-manager.enable = true;

      home = {
        username = "xerxes2";
        homeDirectory = "/home/xerxes2";
        stateVersion = "25.05";
      };
    };
  };
}
