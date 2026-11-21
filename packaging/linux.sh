#!/usr/bin/env bash
set -euo pipefail

version=${1:-1.3.0}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versão inválida" >&2
  exit 1
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
install -d "$stage"/{DEBIAN,opt/bigevil-launcher,usr/bin,usr/share/applications,usr/share/icons/hicolor/256x256/apps} "$root/dist"
tar -C "$root/build/linux/x64/release/bundle" --exclude='.env' --exclude='.env.*' -cf - . |
  tar -C "$stage/opt/bigevil-launcher" -xf -
install -m 644 "$root/packaging/assets/bigevil.png" "$stage/usr/share/icons/hicolor/256x256/apps/bigevil-launcher.png"
ln -s /opt/bigevil-launcher/bigevil_launcher "$stage/usr/bin/bigevil-launcher"
cat > "$stage/DEBIAN/control" <<EOF
Package: bigevil-launcher
Version: $version
Architecture: amd64
Maintainer: BigEvil Launcher
Depends: libgtk-3-0, libstdc++6, libglib2.0-bin, libwebkit2gtk-4.1-0, libarchive-tools
Description: Biblioteca local de jogos e aplicativos
EOF
cat > "$stage/usr/share/applications/bigevil-launcher.desktop" <<'EOF'
[Desktop Entry]
Name=BigEvil Launcher
Exec=bigevil-launcher
Icon=bigevil-launcher
Terminal=false
Type=Application
Categories=Game;Utility;
EOF
dpkg-deb --root-owner-group --build "$stage" "$root/dist/BigEvil-Launcher-linux-x64.deb"
