# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################
# MISC (For dots/.config/* but not quickshell, not Hyprland, not fontconfig)
case "${SKIP_MISCCONF}" in
  true) true;;
  *)
    for i in $(find dots/.config/ -mindepth 1 -maxdepth 1 ! -name 'quickshell' ! -name 'hypr' ! -name 'fontconfig' -exec basename {} \;); do
#      i="dots/.config/$i"
      echo "[$0]: Found target: dots/.config/$i"
      if [ -d "dots/.config/$i" ];then install_dir__sync "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      elif [ -f "dots/.config/$i" ];then install_file "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      fi
    done
    install_dir "dots/.local/share/konsole" "${XDG_DATA_HOME}"/konsole
    ;;
esac

case "${SKIP_QUICKSHELL}" in
  true) true;;
  *)
     # Should overwriting the whole directory not only ~/.config/quickshell/ii/ cuz https://github.com/end-4/dots-hyprland/issues/2294#issuecomment-3448671064
    install_dir__sync dots/.config/quickshell "$XDG_CONFIG_HOME"/quickshell
    ;;
esac

case "${SKIP_FONTCONFIG}" in
  true) true;;
  *)
    case "$FONTSET_DIR_NAME" in
      "") install_dir__sync dots/.config/fontconfig "$XDG_CONFIG_HOME"/fontconfig ;;
      *) install_dir__sync dots-extra/fontsets/$FONTSET_DIR_NAME "$XDG_CONFIG_HOME"/fontconfig ;;
    esac;;
esac

# For Hyprland
case "${SKIP_HYPRLAND}" in
  true) true;;
  *)
    install_dir__sync dots/.config/hypr/hyprland "$XDG_CONFIG_HOME"/hypr/hyprland
    for name in hyprland hyprlock monitors workspaces ; do
      if [ -f "dots/.config/hypr/$name.lua" ]; then
        install_file__auto_backup "dots/.config/hypr/$name.lua" "${XDG_CONFIG_HOME}/hypr/$name.lua"
      elif [ -f "dots/.config/hypr/$name.conf" ]; then
        install_file__auto_backup "dots/.config/hypr/$name.conf" "${XDG_CONFIG_HOME}/hypr/$name.conf"
      fi
    done
    install_file__auto_backup "dots/.config/hypr/hypridle.conf" "${XDG_CONFIG_HOME}/hypr/hypridle.conf"

    install_dir__skip_existed "dots/.config/hypr/custom" "${XDG_CONFIG_HOME}/hypr/custom"
    ;;
esac

install_file "dots/.local/share/icons/illogical-impulse.svg" "${XDG_DATA_HOME}"/icons/illogical-impulse.svg
