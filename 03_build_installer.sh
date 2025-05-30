#!/usr/bin/env bash
set -x
set -e

source logging.sh
source common.sh
source network.sh
source utils.sh
source ocp_install_env.sh
source validation.sh

function clone_installer() {
  # Clone repo, if not already present
  if [[ ! -d $OPENSHIFT_INSTALL_PATH ]]; then
    sync_repo_and_patch "$(realpath -m --relative-to "${REPO_PATH:-$HOME}" "${OPENSHIFT_INSTALL_PATH}")" https://github.com/openshift/installer.git
  fi
}

function build_installer() {
  # Build installer
  pushd .
  cd $OPENSHIFT_INSTALL_PATH
  local default_tags="libvirt baremetal"
  if [[ "${FIPS_MODE:-false}" = "true" && "${FIPS_VALIDATE:-false}" = "true" ]]; then
      default_tags="${default_tags} fipscapable"
  fi
  TAGS="${OPENSHIFT_INSTALLER_BUILD_TAGS:-${default_tags}}" DEFAULT_ARCH=$(get_arch) hack/build.sh
  popd
  # This is only needed in rhcos.sh for old versions which lack the
  # openshift-install coreos-print-stream-json option
  # That landed in 4.8, and in 4.10 this file moved, so just
  # skip copying it if it's not in the "old" location ref
  # https://github.com/openshift/installer/pull/5252
  if [ -f "$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json" ]; then
    cp "$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json" "$OCP_DIR"
  fi
}

function extract_installer() {
    local release_image="$1"
    local outdir="$2"
    local cmd

    cmd="${OPENSHIFT_INSTALLER_CMD:-$(default_installer_cmd)}"

    extract_command "${cmd}" "${release_image}" "${outdir}"

    local target="openshift-install"
    if [ "${cmd}" != "${target}" ]; then
        mv "${outdir}/${cmd}" "${outdir}/${target}"
    fi
}

early_deploy_validation

write_pull_secret

# Extract an updated client tools from the release image
extract_oc "${OPENSHIFT_RELEASE_IMAGE}"

mkdir -p $OCP_DIR

save_release_info ${OPENSHIFT_RELEASE_IMAGE} ${OCP_DIR}

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
  # Extract openshift-install from the release image
  extract_installer "${OPENSHIFT_RELEASE_IMAGE}" $OCP_DIR
  ${OPENSHIFT_INSTALLER} coreos print-stream-json 1>/dev/null 2>&1 || extract_rhcos_json "${OPENSHIFT_RELEASE_IMAGE}" $OCP_DIR
else
  # Clone and build the installer from source
  clone_installer
  build_installer
fi

