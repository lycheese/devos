{ self, nixos, inputs, ... }:
let
  devos = self;
in

{ self, ... } @ args:
let
  inherit (self) lib;
  inherit (lib) os;

  inherit (inputs) utils deploy;

  cfg = (lib.evalFlakeArgs { inherit args; }).config;

  multiPkgs = os.mkPkgs { inherit (cfg) extern overrides; };

  outputs = {
    nixosConfigurations = os.mkHosts {
      inherit devos multiPkgs;
      inherit (cfg) extern suites overrides;
      dir = cfg.hosts;
    };

    homeConfigurations = os.mkHomeConfigurations;

    nixosModules = cfg.modules;

    homeModules = cfg.userModules;

    overlay = cfg.packages;
    inherit (cfg) overlays;

    lib = import "${devos}/lib" {
      inherit self nixos;
      inputs = inputs // self.inputs;
    };

    deploy.nodes = os.mkNodes deploy self.nixosConfigurations;
  };

  systemOutputs = utils.lib.eachDefaultSystem (system:
    let
      pkgs = multiPkgs.${system};
      # all packages that are defined in ./pkgs
      legacyPackages = os.mkPackages { inherit pkgs; };
    in
    {
      checks =
        let
          tests = nixos.lib.optionalAttrs (system == "x86_64-linux")
            (import "${devos}/tests" { inherit pkgs; self = devos; });
          deployHosts = nixos.lib.filterAttrs
            (n: _: self.nixosConfigurations.${n}.config.nixpkgs.system == system) self.deploy.nodes;
          deployChecks = deploy.lib.${system}.deployChecks { nodes = deployHosts; };
        in
        nixos.lib.recursiveUpdate tests deployChecks;

      inherit legacyPackages;
      packages = lib.filterPackages system legacyPackages;

      devShell = import "${devos}/shell" {
        inherit self system;
      };
    });
in
 nixos.lib.recursiveUpdate outputs systemOutputs

