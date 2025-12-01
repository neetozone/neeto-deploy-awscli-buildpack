#!/usr/bin/env bash

set -eu
set -o pipefail

readonly ROOT_DIR="$(cd "$(dirname "${0}")/.." && pwd)"
readonly BIN_DIR="${ROOT_DIR}/.bin"
readonly BUILD_DIR="${ROOT_DIR}/build"

# shellcheck source=SCRIPTDIR/.util/tools.sh
source "${ROOT_DIR}/scripts/.util/tools.sh"

# shellcheck source=SCRIPTDIR/.util/print.sh
source "${ROOT_DIR}/scripts/.util/print.sh"

function main {
  local version output token
  local -a targets
  token=""
  targets=()

  while [[ "${#}" != 0 ]]; do
    case "${1}" in
      --version|-v)
        version="${2}"
        shift 2
        ;;

      --output|-o)
        output="${2}"
        shift 2
        ;;

      --token|-t)
        token="${2}"
        shift 2
        ;;

      --target)
        targets+=("${2}")
        shift 2
        ;;

      --help|-h)
        shift 1
        usage
        exit 0
        ;;

      "")
        # skip if the argument is empty
        shift 1
        ;;

      *)
        util::print::error "unknown argument \"${1}\""
    esac
  done

  if [[ -z "${version:-}" ]]; then
    usage
    echo
    util::print::error "--version is required"
  fi

  if [[ -z "${output:-}" ]]; then
    output="${BUILD_DIR}/buildpackage.cnb"
  fi

  repo::prepare

  tools::install "${token}"

  buildpack_type=buildpack
  if [ -f "${ROOT_DIR}/extension.toml" ]; then
    buildpack_type=extension
  fi

  buildpack::archive "${version}" "${buildpack_type}"
  if [[ ${#targets[@]} -gt 0 ]]; then
    buildpackage::create "${output}" "${buildpack_type}" "${targets[@]}"
  else
    buildpackage::create "${output}" "${buildpack_type}"
  fi
}

function usage() {
  cat <<-USAGE
package.sh --version <version> [OPTIONS]

Packages a buildpack or an extension into a buildpackage .cnb file.

OPTIONS
  --help               -h            prints the command usage
  --version <version>  -v <version>  specifies the version number to use when packaging a buildpack or an extension
  --output <output>    -o <output>   location to output the packaged buildpackage or extension artifact (default: ${ROOT_DIR}/build/buildpackage.cnb)
  --token <token>                    Token used to download assets from GitHub (e.g. jam, pack, etc) (optional)
  --target <target>                  Target platform (e.g. linux/amd64). Can be specified multiple times for multi-arch (optional)
USAGE
}

function repo::prepare() {
  util::print::title "Preparing repo..."

  rm -rf "${BUILD_DIR}"

  mkdir -p "${BIN_DIR}"
  mkdir -p "${BUILD_DIR}"

  export PATH="${BIN_DIR}:${PATH}"
}

function tools::install() {
  local token
  token="${1}"

  util::tools::pack::install \
    --directory "${BIN_DIR}" \
    --token "${token}"

  util::tools::jam::install \
    --directory "${BIN_DIR}" \
    --token "${token}"
}

function buildpack::archive() {
  local version
  version="${1}"
  buildpack_type="${2}"

  util::print::title "Packaging ${buildpack_type} into ${BUILD_DIR}/buildpack.tgz..."

  jam pack \
    "--${buildpack_type}" "${ROOT_DIR}/${buildpack_type}.toml"\
    --version "${version}" \
    --output "${BUILD_DIR}/buildpack.tgz"
}

function buildpackage::create() {
  local output buildpack_type
  output="${1}"
  buildpack_type="${2}"
  shift 2
  local targets=("${@}")

  util::print::title "Packaging ${buildpack_type}... ${output}"

  pack_args=(
    buildpack package "${output}"
    --path "${BUILD_DIR}/buildpack.tgz"
    --format file
  )
  
  if [[ ${#targets[@]} -gt 0 ]]; then
    for target in "${targets[@]}"; do
      pack_args+=(--target "${target}")
    done
  fi

  pack "${pack_args[@]}"
}

main "${@:-}"

