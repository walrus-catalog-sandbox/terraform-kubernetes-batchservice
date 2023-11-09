#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${ROOT_DIR}/hack/lib/init.sh"

function generate() {
  local target="$1"
  shift 1

  if [[ $# > 0 ]]; then
    for subdir in "$@"; do
      local path="${target}/${subdir}"
      local tfs
      tfs=$(seal::util::find_files "${path}" "*.tf")

      if [[ -n "${tfs}" ]]; then
        seal::terraform::docs "${path}" --config="${target}/.terraform-docs.yml"
      else
        seal::log::warn "There is no Terraform files under ${path}"
      fi
    done
    
    return 0
  fi

  seal::terraform::docs "${target}" --config="${target}/.terraform-docs.yml" --recursive
  local examples=()
  # shellcheck disable=SC2086
  IFS=" " read -r -a examples <<<"$(seal::util::find_subdirs ${target}/examples)"
  for example in "${examples[@]}"; do
    seal::terraform::docs "${target}/examples/${example}" --config="${target}/.terraform-docs.yml"
  done
}

#
# main
#

seal::log::info "+++ GENERATE +++"

generate "${ROOT_DIR}" "$@"

seal::log::info "--- GENERATE ---"
