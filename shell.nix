let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShell {
  packages = with pkgs; [
    age
    ansible
    kubectl
    kubernetes-helm
    kubeseal
    sops
    talhelper
    talosctl
  ];
}
