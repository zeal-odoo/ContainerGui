#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly app_version="$(
  /usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
    "$project_root/Sources/ContainerGUI/App/AppVersion.swift"
)"
readonly architecture="$(/usr/bin/uname -m)"
readonly output_directory="${1:-$project_root/dist}"
readonly package_identifier="io.github.zeal-odoo.container-gui"
readonly package_name="ContainerGUI-$app_version-$architecture.pkg"
readonly package_path="$output_directory/$package_name"
readonly checksum_path="$package_path.sha256"
readonly installer_identity="${CONTAINER_GUI_INSTALLER_IDENTITY:-}"

if [[ -z "$app_version" ]]; then
  print -u2 "Unable to read the Container GUI version."
  exit 65
fi
if [[ "$architecture" != "arm64" ]]; then
  print -u2 "Container GUI packages currently support Apple silicon only."
  exit 65
fi

readonly work_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/container-gui-pkg.XXXXXX")"
trap '/bin/rm -rf "$work_directory"' EXIT
readonly payload_root="$work_directory/payload"
readonly component_package="$work_directory/component.pkg"
readonly unsigned_product="$work_directory/unsigned.pkg"
readonly distribution_file="$work_directory/Distribution.xml"
readonly scratch_directory="$work_directory/swift-build"
readonly runtime_directory="$payload_root/Library/Application Support/ContainerGUI/versions/$app_version"
readonly support_root="$payload_root/Library/Application Support/ContainerGUI"

print "Building Container GUI $app_version for $architecture..."
cd "$project_root"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  /usr/bin/xcrun swift build \
    -c release \
    --product ContainerGUI \
    --scratch-path "$scratch_directory" \
    -Xswiftc -file-prefix-map \
    -Xswiftc "$project_root=ContainerGUI"
readonly build_directory="$(
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    /usr/bin/xcrun swift build -c release --scratch-path "$scratch_directory" --show-bin-path
)"

if [[ ! -x "$build_directory/ContainerGUI" || \
      ! -d "$build_directory/ContainerGUI_ContainerGUI.bundle" ]]; then
  print -u2 "Release binary or resource bundle is missing."
  exit 66
fi

/bin/mkdir -p "$runtime_directory" "$payload_root/usr/local/bin" "$output_directory"
/bin/cp "$build_directory/ContainerGUI" "$runtime_directory/ContainerGUI"
/bin/cp -R "$build_directory/ContainerGUI_ContainerGUI.bundle" "$runtime_directory/ContainerGUI_ContainerGUI.bundle"
/bin/cp "$project_root/scripts/container-gui-watchdog.sh" "$runtime_directory/container-gui-watchdog.sh"
/bin/cp "$project_root/scripts/render-launch-agents.sh" "$runtime_directory/render-launch-agents.sh"
/bin/cp "$project_root/packaging/bin/container-gui-enable" "$payload_root/usr/local/bin/container-gui-enable"
/bin/cp "$project_root/packaging/bin/container-gui-uninstall" "$payload_root/usr/local/bin/container-gui-uninstall"
/usr/bin/strip -S "$runtime_directory/ContainerGUI"
/usr/bin/codesign --force --sign - "$runtime_directory/ContainerGUI"
/usr/bin/codesign --verify --strict "$runtime_directory/ContainerGUI"
/bin/chmod 755 \
  "$runtime_directory/ContainerGUI" \
  "$runtime_directory/container-gui-watchdog.sh" \
  "$runtime_directory/render-launch-agents.sh" \
  "$payload_root/usr/local/bin/container-gui-enable" \
  "$payload_root/usr/local/bin/container-gui-uninstall"
/bin/ln -s "versions/$app_version" "$support_root/current"
/usr/bin/xattr -cr "$payload_root"

/usr/bin/pkgbuild \
  --root "$payload_root" \
  --scripts "$project_root/packaging/pkg-scripts" \
  --identifier "$package_identifier" \
  --version "$app_version" \
  --install-location / \
  "$component_package"
/usr/bin/sed "s/__VERSION__/$app_version/g" \
  "$project_root/packaging/Distribution.xml" > "$distribution_file"
/usr/bin/productbuild \
  --distribution "$distribution_file" \
  --package-path "$work_directory" \
  "$unsigned_product"

/bin/rm -f "$package_path" "$checksum_path"
if [[ -n "$installer_identity" ]]; then
  /usr/bin/productsign --sign "$installer_identity" "$unsigned_product" "$package_path"
else
  /bin/mv "$unsigned_product" "$package_path"
fi

(
  cd "$output_directory"
  /usr/bin/shasum -a 256 "$package_name" > "$package_name.sha256"
)

readonly expanded_package="$work_directory/expanded"
/usr/sbin/pkgutil --expand-full "$package_path" "$expanded_package"
readonly package_info="$(/usr/bin/find "$expanded_package" -name PackageInfo -type f -print -quit)"
if [[ -z "$package_info" ]] || \
    ! /usr/bin/grep -q "identifier=\"$package_identifier\"" "$package_info" || \
    ! /usr/bin/grep -q "version=\"$app_version\"" "$package_info"; then
  print -u2 "The built package metadata did not match the requested identifier and version."
  exit 67
fi

print "Package: $package_path"
print "SHA-256: $checksum_path"
if [[ -z "$installer_identity" ]]; then
  print "Signature: unsigned (set CONTAINER_GUI_INSTALLER_IDENTITY to sign)"
else
  /usr/sbin/pkgutil --check-signature "$package_path"
fi
