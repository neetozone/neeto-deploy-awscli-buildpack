#!/usr/bin/env bash

set -eu
set -o pipefail

readonly ROOT_DIR="$(cd "$(dirname "${0}")/.." && pwd)"
readonly BIN_DIR="${ROOT_DIR}/.bin"

# shellcheck source=SCRIPTDIR/.util/tools.sh
source "${ROOT_DIR}/scripts/.util/tools.sh"

# shellcheck source=SCRIPTDIR/.util/print.sh
source "${ROOT_DIR}/scripts/.util/print.sh"

function main {
  local archive_path image_ref token
  token=""

  while [[ "${#}" != 0 ]]; do
    case "${1}" in
    --archive-path | -a)
      archive_path="${2}"
      shift 2
      ;;

    --image-ref | -i)
      image_ref="${2}"
      shift 2
      ;;

    --token | -t)
      token="${2}"
      shift 2
      ;;

    --help | -h)
      shift 1
      usage
      exit 0
      ;;

    "")
      shift 1
      ;;

    *)
      util::print::error "unknown argument \"${1}\""
      ;;
    esac
  done

  if [[ -z "${image_ref:-}" ]]; then
    usage
    util::print::error "--image-ref is required"
  fi

  if [[ -z "${archive_path:-}" ]]; then
    util::print::info "Using default archive path: ${ROOT_DIR}/build/buildpack.tgz"
    archive_path="${ROOT_DIR}/build/buildpack.tgz"
  fi

  repo::prepare
  tools::install "${token}"
  buildpack::publish "${image_ref}" "${archive_path}"
}

function usage() {
  cat <<-USAGE
Publishes the AWS CLI buildpack to a registry.

OPTIONS
  -a, --archive-path <filepath>       Path to the buildpack archive (default: ${ROOT_DIR}/build/buildpack.tgz) (optional)
  -h, --help                          Prints the command usage
  -i, --image-ref <ref>               Image reference to publish to (required)
  -t, --token <token>                 Token used to download assets from GitHub (e.g. jam, pack, etc) (optional)
USAGE
}

function targets::from_toml() {
  local toml_path
  toml_path="${1}"

  if [[ ! -f "${toml_path}" ]]; then
    return 0
  fi

  awk '
    function emit_target() {
      if (inside_targets && os != "" && arch != "") {
        print os "/" arch
      }
      os = ""
      arch = ""
    }

    /^\[\[targets\]\]/ {
      emit_target()
      inside_targets = 1
      next
    }

    /^\[\[/ {
      emit_target()
      inside_targets = 0
      next
    }

    inside_targets {
      if ($0 ~ /^[[:space:]]*os[[:space:]]*=/) {
        value = $0
        sub(/^[^=]*=[[:space:]]*/, "", value)
        gsub(/"/, "", value)
        gsub(/[[:space:]]/, "", value)
        os = value
      }
      if ($0 ~ /^[[:space:]]*arch[[:space:]]*=/) {
        value = $0
        sub(/^[^=]*=[[:space:]]*/, "", value)
        gsub(/"/, "", value)
        gsub(/[[:space:]]/, "", value)
        arch = value
      }
    }

    END {
      emit_target()
    }
  ' "${toml_path}" | sort -u
}

function repo::prepare() {
  util::print::title "Preparing repo..."
  mkdir -p "${BIN_DIR}"
  export PATH="${BIN_DIR}:${PATH}"
}

function tools::install() {
  local token
  token="${1}"

  util::tools::pack::install \
    --directory "${BIN_DIR}" \
    --token "${token}"
}

function buildpack::publish() {
  local image_ref archive_path
  image_ref="${1}"
  archive_path="${2}"

  util::print::title "Publishing buildpack..."

  local buildpack_toml="${ROOT_DIR}/buildpack.toml"
  local -a targets=()
  if [[ -f "${buildpack_toml}" ]]; then
    util::print::info "Reading targets from ${buildpack_toml}..."
    while IFS= read -r target; do
      [[ -n "${target}" ]] && targets+=("${target}")
    done < <(targets::from_toml "${buildpack_toml}")
    [[ ${#targets[@]} -gt 0 ]] && util::print::info "Found ${#targets[@]} target(s): ${targets[*]}"
  fi

  if [[ ! -f "${archive_path}" ]]; then
    util::print::error "buildpack artifact not found at ${archive_path}; run scripts/package.sh first"
  fi

  if [[ ${#targets[@]} -gt 1 ]]; then
    util::print::info "Publishing multi-arch buildpack (${#targets[@]} architectures)..."

    if docker manifest inspect "${image_ref}" >/dev/null 2>&1; then
      util::print::info "Existing manifest list found; removing..."
      docker manifest rm "${image_ref}"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d -p "${ROOT_DIR}")
    tar -xzf "${archive_path}" -C "${tmp_dir}"

    local arch_images=()
    for target in "${targets[@]}"; do
      local arch
      arch=$(echo "${target}" | cut -d'/' -f2)
      local arch_image_ref="${image_ref}-${arch}"
      util::print::info "Publishing ${target} as ${arch_image_ref}..."
      pack \
        buildpack package "${arch_image_ref}" \
        --path "${tmp_dir}" \
        --target "${target}" \
        --format image \
        --publish
      arch_images+=("${arch_image_ref}")
    done

    util::print::info "Creating multi-arch manifest for ${image_ref}..."
    docker manifest create "${image_ref}" "${arch_images[@]}"
    docker manifest push "${image_ref}"
    rm -rf "${tmp_dir}"
    util::print::info "Successfully published multi-arch buildpack: ${image_ref}"
  else
    util::print::info "Publishing single-arch buildpack to ${image_ref}"
    local tmp_dir
    tmp_dir=$(mktemp -d -p "${ROOT_DIR}")
    tar -xzf "${archive_path}" -C "${tmp_dir}"

    local pack_args=(
      buildpack package "${image_ref}"
      --path "${tmp_dir}"
      --format image
      --publish
    )
    if [[ ${#targets[@]} -eq 1 ]]; then
      pack_args+=(--target "${targets[0]}")
    fi

    pack "${pack_args[@]}"
    rm -rf "${tmp_dir}"
  fi
}

main "${@:-}"


