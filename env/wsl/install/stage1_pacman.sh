#!/usr/bin/env bash
# stage1_pacman.sh — what stage 1 needs from Arch. Sourced by stage1.sh, same functions as
# stage1_apt.sh.
# shellcheck disable=SC2034

UM_ADMIN_GROUP=wheel
UM_USER_GROUPS=wheel
UM_ADMIN_RULE="%wheel ALL=(ALL:ALL) ALL"

keyring_ready() {
  local keys
  keys="$(pacman-key --list-keys 2>/dev/null)" && [ -n "$keys" ]
}

pm_present() {
  command -v pacman >/dev/null 2>&1
}

pm_ready() {
  keyring_ready \
    && [ -n "$(ls -A /var/lib/pacman/sync 2>/dev/null)" ] \
    && pacman -Q base-devel git sudo >/dev/null 2>&1 \
    && [ -z "$(pacman -Qu 2>/dev/null)" ]
}

pm_prepare() {
  # Only the image's first-launch script sets up the keyring; an imported distro has none.
  if ! keyring_ready; then
    pacman-key --init || return 1
    pacman-key --populate archlinux || return 1
  fi
  pacman -Syu --noconfirm --needed base-devel git sudo
}
