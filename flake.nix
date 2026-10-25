{
  description = "Flake that provides Zen Browser binaries wrapped and patched for NixOS.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          packages = import ./. { inherit pkgs system; };
        in
        packages
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          pkgsWithPolicies = import nixpkgs {
            inherit system;
            config.zen.policies.DisableTelemetry = true;
          };
          zen-browser = (import ./. { inherit pkgs system; }).default;
          configured =
            (import ./. {
              pkgs = pkgsWithPolicies;
              inherit system;
            }).default;
          overridden = zen-browser.override {
            extraPolicies = {
              DisableTelemetry = true;
            };
          };
          fakeExtension =
            pkgs.runCommand "fake-extension" { } ''
              mkdir -p $out
              touch $out/fake@example.com.xpi
            ''
            // {
              name = "fake-extension";
              extid = "fake@example.com";
            };
          mixed = zen-browser.override {
            nixExtensions = [ fakeExtension ];
            extraPolicies = {
              ExtensionSettings = {
                "extra@example.com" = {
                  installation_mode = "force_installed";
                  install_url = "https://example.com/extra.xpi";
                };
              };
            };
          };
        in
        {
          policies =
            assert zen-browser.policies.DisableAppUpdate == true;
            assert configured.policies.DisableTelemetry == true;
            assert overridden.policies.DisableAppUpdate == true;
            assert overridden.policies.DisableTelemetry == true;
            assert mixed.policies.ExtensionSettings."*".installation_mode == "blocked";
            assert mixed.policies.ExtensionSettings."fake@example.com".installation_mode == "allowed";
            assert mixed.policies.ExtensionSettings."extra@example.com".installation_mode == "force_installed";
            pkgs.runCommand "zen-browser-policies-check" { } ''
              touch $out
            '';
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          update = {
            type = "app";
            program = "${pkgs.callPackage ./update-scripts { }}/bin/commit-update.nu";
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
