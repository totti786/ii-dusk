# This script depends on `functions.sh' .
# This script is not for direct execution, instead it should be sourced by other script. It does not need execution permission or shebang.

# shellcheck shell=bash

# This file is provided for any distros, mainly non-Arch(based) distros.

install-Rubik(){
  x mkdir -p $REPO_ROOT/cache/Rubik
  x cd $REPO_ROOT/cache/Rubik
  try git init -b main
  try git remote add origin https://github.com/googlefonts/rubik.git
  x git pull origin main && git submodule update --init --recursive
	x sudo mkdir -p /usr/local/share/fonts/TTF/
	x sudo cp fonts/variable/Rubik*.ttf /usr/local/share/fonts/TTF/
	x sudo mkdir -p /usr/local/share/licenses/ttf-rubik/
	x sudo cp OFL.txt /usr/local/share/licenses/ttf-rubik/LICENSE
  x fc-cache -fv
  x cd $REPO_ROOT
}

install-Gabarito(){
  x mkdir -p $REPO_ROOT/cache/Gabarito
  x cd $REPO_ROOT/cache/Gabarito
  try git init -b main
  try git remote add origin https://github.com/naipefoundry/gabarito.git
  x git pull origin main && git submodule update --init --recursive
	x sudo mkdir -p /usr/local/share/fonts/TTF/
	x sudo cp fonts/ttf/Gabarito*.ttf /usr/local/share/fonts/TTF/
	x sudo mkdir -p /usr/local/share/licenses/ttf-gabarito/
	x sudo cp OFL.txt /usr/local/share/licenses/ttf-gabarito/LICENSE
  x fc-cache -fv
  x cd $REPO_ROOT
}

install-bibata(){
  x mkdir -p $REPO_ROOT/cache/bibata-cursor
  x cd $REPO_ROOT/cache/bibata-cursor
  name="Bibata-Modern-Classic"
  file="$name.tar.xz"
  try rm $file
  x curl -JLO https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/$file
  tar -xf $file
  x sudo mkdir -p /usr/local/share/icons
  x sudo cp -r $name /usr/local/share/icons
  x cd $REPO_ROOT
}

install-MicroTeX(){
  x mkdir -p $REPO_ROOT/cache/MicroTeX
  x cd $REPO_ROOT/cache/MicroTeX
  try git init -b master
  try git remote add origin https://github.com/NanoMichael/MicroTeX.git
  x git pull origin master && git submodule update --init --recursive
  x mkdir -p build
  x cd build
  x cmake ..
  x make -j32
	x sudo mkdir -p /opt/MicroTeX
  x sudo cp ./LaTeX /opt/MicroTeX/
  x sudo cp -r ./res /opt/MicroTeX/
  x cd $REPO_ROOT
}

install-uv(){
  x bash <(curl -LJs "https://astral.sh/uv/install.sh")
}

install-python-packages(){
  export UV_NO_MODIFY_PATH=1
  export UV_PYTHON_DOWNLOADS=automatic

  if ! command -v uv >/dev/null 2>&1; then
    echo -e "${STY_YELLOW}[$0]: \"uv\" not found. Installing uv...${STY_RST}"
    showfun install-uv
    v install-uv
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi

  # The shell's one Python environment is built from the lock that ships with the shell
  # (scripts/deps/requirements.lock), by its own bootstrap script, so the installer and
  # "Settings > About > Dependencies > Rebuild" always produce the same environment.
  local bootstrap="${REPO_ROOT}/dots/.config/quickshell/ii/scripts/deps/bootstrap.sh"
  if [[ "$INSTALL_VIA_NIX" = true ]]; then
    x nix-shell "${REPO_ROOT}/sdata/uv/shell.nix" --run "bash '${bootstrap}'"
  else
    x bash "${bootstrap}"
  fi
}
