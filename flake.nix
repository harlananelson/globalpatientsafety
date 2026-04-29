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

            # faers-mobi / aers-mobi runtime deps
            # (these apps live in sibling repos but are run from this dev shell)
            arrow
            DT

            # Dev
            languageserver
          ];
        };

      in {
        devShells.default = pkgs.mkShell {
          name = "globalpatientsafety";

          packages = [
            rWithPkgs
            pkgs.nodejs       # sass: node (rhino.yml) + claude-code install
            pkgs.git
            pkgs.tmux
            pkgs.mistral-vibe # Mistral CLI coding agent
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

            # Install Claude Code if not already available
            if ! command -v claude &>/dev/null; then
              echo "Installing Claude Code..."
              npm install -g @anthropic-ai/claude-code 2>/dev/null || true
            fi

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  globalpatientsafety.com dev environment"
            echo "  R: $(R --version | head -1)"
            echo "  Tools: claude, mistral, tmux"
            echo "  Run: Rscript -e 'shiny::runApp()'"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          '';
        };
      });
}
