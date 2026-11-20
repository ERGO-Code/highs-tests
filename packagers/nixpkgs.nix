# nixpkgs (nixos-unstable) with its highs built from a local HiGHS source, and
# one package that depends on it. Building a package runs its nixpkgs checks.
#   nix build --impure -f packagers/nixpkgs.nix --argstr highsSrc <dir> --argstr package <attr path>
{ highsSrc, package }:
let
  nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/nixos-unstable";
  # nixpkgs's versionCheckHook expects `highs --version` to print this
  lines = builtins.filter builtins.isString (builtins.split "\n" (builtins.readFile "${highsSrc}/Version.txt"));
  field = name: builtins.head (builtins.concatMap
    (line: let m = builtins.match "${name}=([0-9]+)" line; in if m == null then [ ] else m)
    lines);
  version = "${field "HIGHS_MAJOR"}.${field "HIGHS_MINOR"}.${field "HIGHS_PATCH"}";
  overlay = final: prev: {
    highs = prev.highs.overrideAttrs (_: {
      inherit version;
      src = final.lib.cleanSource highsSrc;
    });
  };
  pkgs = nixpkgs.legacyPackages.x86_64-linux.extend overlay;
in
pkgs.lib.getAttrFromPath (pkgs.lib.splitString "." package) pkgs
