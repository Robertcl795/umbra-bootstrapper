#!/usr/bin/env bash
# stage1_apt.sh — what stage 1 needs from Ubuntu. Sourced by stage1.sh, same functions as
# stage1_pacman.sh. /etc/sudoers already grants %sudo, so no rule is added. The groups are the ones
# Ubuntu's first launch gives its user. Nothing is upgraded: stage 2 installs what it needs.
# shellcheck disable=SC2034

UM_ADMIN_GROUP=sudo
UM_USER_GROUPS=adm,cdrom,sudo,dip,plugdev
UM_ADMIN_RULE=""

pm_present() {
  command -v apt-get >/dev/null 2>&1
}

pm_ready() {
  dpkg -s git sudo curl ca-certificates >/dev/null 2>&1
}

pm_prepare() {
  apt-get update || return 1
  DEBIAN_FRONTEND=noninteractive apt-get install -y git sudo curl ca-certificates
}
