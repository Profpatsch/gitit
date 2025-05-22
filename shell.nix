let
  pkgs = import ./nixpkgs.nix {};

  gitit = (import ./default.nix {});

in pkgs.haskellPackages.shellFor {
  withHoogle = true;
  packages = _hps: [
    gitit
  ];
  nativeBuildInputs = [
    pkgs.cabal-install
    pkgs.haskell-language-server
 
    gitit.extractRuntimeDependenciesTo
  ];
}
