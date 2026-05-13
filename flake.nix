{
  description = "Panaroo pangenome analysis pipeline";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f {
            pkgs = import nixpkgs { inherit system; };
            inherit system;
          });
    in
    {
      packages = forAllSystems ({ pkgs, ... }:
        let
          lib = pkgs.lib;
          python = pkgs.python3;
          pyPkgs = python.pkgs;
          optionalPyDep = name:
            lib.optionals (builtins.hasAttr name pyPkgs) [ (builtins.getAttr name pyPkgs) ];
          requiredPyDep = names:
            let
              existing = builtins.filter (name: builtins.hasAttr name pyPkgs) names;
            in
            if existing == [] then
              throw ("Missing required python dependency; looked for: " + lib.concatStringsSep ", " names)
            else
              builtins.getAttr (builtins.head existing) pyPkgs;
          gffutilsPkg =
            if builtins.hasAttr "gffutils" pyPkgs then
              pyPkgs.gffutils
            else
              pyPkgs.buildPythonPackage rec {
                pname = "gffutils";
                version = "0.13";
                pyproject = true;

                src = pyPkgs.fetchPypi {
                  inherit pname version;
                  hash = "sha256-sNUvNcAUzAMw+1xOPG/qEnyQzPTFOEqCXNtcj/Mw1Os=";
                };

                build-system = [ pyPkgs.setuptools ];

                propagatedBuildInputs = [
                  (pyPkgs.pyfaidx.overridePythonAttrs (_: { doCheck = false; }))
                  pyPkgs.argh
                  pyPkgs.argcomplete
                  pyPkgs.simplejson
                  pyPkgs.pyyaml
                ];

                doCheck = false;
              };
          biocodePkg =
            if builtins.hasAttr "biocode" pyPkgs then
              pyPkgs.biocode
            else
              pyPkgs.buildPythonPackage rec {
                pname = "biocode";
                version = "0.12.1";
                pyproject = true;

                src = pyPkgs.fetchPypi {
                  inherit pname version;
                  hash = "sha256-z8bRmUi7/VJcjUZznCpv/I1aroxOf3zZrJ7S3jCnAv0=";
                };

                build-system = [ pyPkgs.setuptools ];

                propagatedBuildInputs = [
                  pyPkgs.biopython
                ];

                doCheck = false;
                dontCheckRuntimeDeps = true;
              };
          panaroo = pyPkgs.buildPythonApplication rec {
            pname = "panaroo";
            version = "1.6.1";
            format = "setuptools";

            src = self;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            propagatedBuildInputs =
              [
                (requiredPyDep [ "networkx" ])
                (requiredPyDep [ "biopython" ])
                (requiredPyDep [ "joblib" ])
                (requiredPyDep [ "tqdm" ])
                (requiredPyDep [ "edlib" ])
                (requiredPyDep [ "scipy" ])
                (requiredPyDep [ "numpy" ])
                (requiredPyDep [ "matplotlib" ])
                (requiredPyDep [ "scikit-learn" "scikitlearn" ])
                (requiredPyDep [ "plotly" ])
              ]
              ++ [ gffutilsPkg biocodePkg ]
              ++ optionalPyDep "dendropy"
              ++ optionalPyDep "intbitset";

            pythonImportsCheck = [ "panaroo" ];
            doCheck = false;

            postFixup = ''
              for prog in \
                $out/bin/panaroo \
                $out/bin/run_prokka \
                $out/bin/panaroo-qc \
                $out/bin/panaroo-merge \
                $out/bin/panaroo-plot-abundance \
                $out/bin/panaroo-spydrpick \
                $out/bin/panaroo-img \
                $out/bin/panaroo-fmg \
                $out/bin/panaroo-msa \
                $out/bin/panaroo-gene-neighbourhood \
                $out/bin/panaroo-integrate \
                $out/bin/panaroo-filter-pa \
                $out/bin/panaroo-generate-gffs \
                $out/bin/panaroo-extract-gene
              do
                if [ -x "$prog" ]; then
                  wrapProgram "$prog" \
                    --prefix PATH : "${lib.makeBinPath [ pkgs.cd-hit pkgs.mafft ]}"
                fi
              done
            '';

            meta = {
              description = "A pangenome analysis pipeline";
              homepage = "https://github.com/gtonkinhill/panaroo";
              license = lib.licenses.mit;
              mainProgram = "panaroo";
              platforms = lib.platforms.all;
            };
          };
        in
        {
          default = panaroo;
          panaroo = panaroo;
        });

      apps = forAllSystems ({ system, ... }: {
        default = {
          type = "app";
          program = "${self.packages.${system}.panaroo}/bin/panaroo";
        };
        panaroo = {
          type = "app";
          program = "${self.packages.${system}.panaroo}/bin/panaroo";
        };
      });

      devShells = forAllSystems ({ pkgs, system }:
        {
          default = pkgs.mkShell {
            packages = [
              self.packages.${system}.panaroo
              pkgs.cd-hit
              pkgs.mafft
            ];
          };
        });

      overlays.default = final: prev: {
        panaroo = self.packages.${prev.system}.panaroo;
      };
    };
}
