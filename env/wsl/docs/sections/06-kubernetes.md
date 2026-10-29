# Phase 6 — Dev environment (Kubernetes tooling)

Script: [`install/dev/k8s.sh`](../../install/dev/k8s.sh)

Installs `kubectl` (latest stable release, via `dl.k8s.io`), `helm` (official
`get-helm-3` script) and `k3d` (official install script) if they aren't
already present. Entirely skipped when `UM_ENABLE_K8S=0`.

Interactive runs ask "Enable Kubernetes tooling (kubectl/helm/k3d)?"
(default yes) if `UM_ENABLE_K8S` isn't already set; non-interactive runs
default to enabled (`UM_ENABLE_K8S=1`).

## OS notes

The installers used here are all official upstream scripts that detect
architecture themselves — identical on Ubuntu and Arch. On native Windows,
the same three tools come from scoop instead (`kubectl`, `helm`, `k3d`
manifests) — `k3d` additionally needs Docker Desktop with the WSL2 backend
since it runs containers; see [os/windows.md](../os/windows.md).

## Customization

`UM_ENABLE_K8S=0|1`

## Test

[`tests/06_dev.sh`](../../tests/06_dev.sh) — skips cleanly if
`UM_ENABLE_K8S=0`; otherwise asserts `kubectl version --client` and
`k3d version` both succeed.
