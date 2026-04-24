{
  description = "globalpatientsafety.com — portal app for pharmacovigilance tool suite";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        rWithPkgs = pkgs.rWrapper.override {
          packages = with pkgs.rPackages; [
            # Rhino framework
            rhino
            shiny
            bslib
            box
            htmltools

            # Treesitter (rhino dependency for box linting)
            treesitter
            treesitter_r

            # Tidyverse core (used in logic/)
            tibble
            dplyr

            # Dev
            languageserver
          ];
        };

      in {
        devShells.default = pkgs.mkShell {
          name = "globalpatientsafety";

          packages = [
            rWithPkgs
            pkgs.nodejs  # sass: node (rhino.yml)
            pkgs.git
          ];

          env = {
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
              pkgs.stdenv.cc.cc.lib
            ];
          };

          shellHook = ''
            export USER="$(whoami 2>/dev/null || echo unknown)"
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  globalpatientsafety.com dev environment"
            echo "  R: $(R --version | head -1)"
            echo "  Run: Rscript -e 'shiny::runApp()'"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          '';
        };
      });
}
