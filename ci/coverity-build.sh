#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Coverity Scan manual build for the tirdad out-of-tree Linux kernel
## module.
##
## The reusable Coverity workflow runs this build-command directly
## ('bash -c "${BUILD_COMMAND}"') and then tars ./cov-int/ for
## submission - it does NOT wrap the command in cov-build itself
## (unlike the Python default, which runs 'coverity capture'). So
## THIS script must invoke cov-build so ./cov-int/ actually captures
## module/tirdad.c's compilation. A build that ran plain 'make'
## without cov-build would leave cov-int empty and Coverity would
## analyze zero units while reporting success - the same false-green
## class as an empty CodeQL cpp database.
##
## Build derivation: mirrors ci/codeql-build.sh exactly (same kernel
## header install + same 'make -C $(KERNELDIR) M=$(pwd)/module' drive
## via the repo Makefile). The only additions are the cov-build
## wrapper and the emitted-units guard.
##
## Kernel headers source (per ci/codeql-build.sh):
##
## The CI runner (ubuntu-24.04) runs an Azure kernel whose exact
## '/lib/modules/$(uname -r)/build' tree is not apt-installable, and
## matching the runtime kernel is irrelevant for static capture -
## the module is compiled, never loaded. So install the apt-stable
## 'linux-headers-generic' (noble main, 6.8 GA) and point KERNELDIR
## at it, overriding the repo Makefile's '$(uname -r)' default.
##
## Version-guard note: module/tirdad.c gates the TCP-ISN hook body on
## LINUX_VERSION_CODE (< 6.12.94, or 6.13.0..6.18.17). The 6.8 GA
## headers satisfy the first branch, so the security-relevant hook
## code is the code that gets compiled and captured - not an empty
## translation unit.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
set -o xtrace

sudo --non-interactive apt-get update --error-on=any
sudo --non-interactive apt-get install --yes --no-install-recommends \
  linux-headers-generic build-essential

## Resolve the concrete headers package the metapackage pulled, so
## KERNELDIR is deterministic regardless of any other headers present.
kver="$(dpkg-query --showformat='${Depends}' --show linux-headers-generic \
  | grep --only-matching --extended-regexp 'linux-headers-[0-9][^, ]*-generic' \
  | head --lines=1)"

if [ -z "${kver}" ]; then
  printf '%s\n' "error: could not resolve linux-headers-generic dependency" >&2
  exit 1
fi

kerneldir="/usr/src/${kver}"

if [ ! -d "${kerneldir}" ]; then
  printf '%s\n' "error: kernel build tree not found: ${kerneldir}" >&2
  exit 1
fi

## cov-build lives under ./cov-analysis/ (extracted by
## ci/coverity-download.sh, which the reusable runs before this
## build step). Deterministic path, matching that script's cwd
## contract.
cov_build="./cov-analysis/bin/cov-build"

if [ ! -x "${cov_build}" ]; then
  printf '%s\n' "error: cov-build not found at ${cov_build}" >&2
  exit 1
fi

## Wrap the repo's own kbuild under Coverity's compiler tracer so
## the module/tirdad.c compile is captured, not just run.
"${cov_build}" --dir cov-int make KERNELDIR="${kerneldir}"

## Guard 1: the object file must exist (make actually compiled).
if [ ! -f module/tirdad.o ]; then
  printf '%s\n' "error: module/tirdad.o not produced; nothing was compiled" >&2
  exit 1
fi

## Guard 2: cov-build must have captured a non-zero number of C/C++
## compilation units. A zero-unit capture is a false green - Coverity
## reports success while analyzing nothing. Read the count from
## cov-build's own build log; take the maximum across the log so an
## intermediate '0 ... ready' line cannot mask the final summary.
build_log='cov-int/build-log.txt'

if [ ! -f "${build_log}" ]; then
  printf '%s\n' "error: ${build_log} missing; cov-build captured nothing" >&2
  exit 1
fi

emitted="$(grep --only-matching --extended-regexp \
  '[0-9]+ C/C\+\+ compilation units' -- "${build_log}" \
  | grep --only-matching --extended-regexp '^[0-9]+' \
  | sort --reverse --numeric-sort \
  | head --lines=1)"

if [ -z "${emitted}" ] || [ "${emitted}" -eq 0 ]; then
  printf '%s\n' "error: cov-build captured 0 C/C++ compilation units; nothing to analyze" >&2
  cat -- "${build_log}" >&2 || true
  exit 1
fi

printf 'cov-build captured %s C/C++ compilation unit(s).\n' "${emitted}"
ls -l -- module/tirdad.o module/tirdad.ko
