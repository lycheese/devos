{ lib, dev, nixos, inputs, self, ... }:

{ dir, extern, suites, overrides, multiPkgs, ... }:
let
  defaultSystem = "x86_64-linux";

  experimentalFeatures = [
    "flakes"
    "nix-command"
    "ca-references"
    "ca-derivations"
  ];

  modules = {
    core = "${self}/profiles/core";
    modOverrides = { config, overrideModulesPath, ... }:
      let
        inherit (overrides) modules disabledModules;
      in
      {
        disabledModules = modules ++ disabledModules;
        imports = map
          (path: "${overrideModulesPath}/${path}")
          modules;
      };

    global = { config, ... }: {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;

        extraSpecialArgs = extern.userSpecialArgs // { suites = suites.user; };
        sharedModules = extern.userModules ++ (builtins.attrValues self.homeModules);
      };

      hardware.enableRedistributableFirmware = lib.mkDefault true;

      nix.nixPath = [
        "nixpkgs=${nixos}"
        "nixos-config=${self}/compat/nixos"
        "home-manager=${inputs.home}"
      ];

      nixpkgs.pkgs = lib.mkDefault multiPkgs.${config.nixpkgs.system};

      nix.registry = {
        devos.flake = self;
        nixos.flake = nixos;
        override.flake = inputs.override;
      };

      nix.extraOptions = ''
        experimental-features = ${lib.concatStringsSep " "
          experimentalFeatures
        }
      '';

      system.configurationRevision = lib.mkIf (self ? rev) self.rev;
    };

    # Everything in `./modules/list.nix`.
    flakeModules = { imports = builtins.attrValues self.nixosModules ++ extern.modules; };

    cachix = ../../cachix.nix;
  };

  specialArgs = extern.specialArgs // { suites = suites.system; };

  mkHostConfig = hostName:
    let
      local = {
        require = [
          "${dir}/${hostName}.nix"
        ];

        networking = { inherit hostName; };

        _module.args = {
          inherit self;
          hosts = builtins.mapAttrs (_: host: host.config)
            (removeAttrs hosts [ hostName ]);
        };
      };
      lib = {
        lib = { inherit specialArgs; };
        lib.testModule = {
          imports = builtins.attrValues modules;
        };
      };
    in
    dev.os.devosSystem {
      inherit specialArgs;
      system = defaultSystem;
      modules = modules // { inherit local lib; };
    };

  hosts = dev.os.recImport
    {
      inherit dir;
      _import = mkHostConfig;
    };
in
hosts
