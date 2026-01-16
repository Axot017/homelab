let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShell {
  packages = with pkgs; [
    age
    ansible
    fluxcd
    just
    kubectl
    kubernetes-helm
    kubeseal
    sops
    talhelper
    talosctl
    velero
  ];
}
