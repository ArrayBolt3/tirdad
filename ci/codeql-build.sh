#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CodeQL manual build for the tirdad out-of-tree Linux kernel module.
##
## tirdad hot-patches TCP ISN generation via a kernel module built by
## kbuild. For the CodeQL c-cpp extractor to see module/tirdad.c, the
## build-command (build-mode=manual) must actually compile it under
## CodeQL's tracer. A kbuild external-module build needs a configured
## kernel build tree (headers).
##
## Kernel headers source:
##
## The CI runner (ubuntu-24.04) runs an Azure kernel whose exact
## '/lib/modules/$(uname -r)/build' tree is not apt-installable, and
## matching the runtime kernel is irrelevant for static extraction -
## the module is compiled, never loaded. So install the apt-stable
## 'linux-headers-generic' (noble main, 6.8 GA) and point KERNELDIR
## at it, overriding the repo Makefile's '$(uname -r)' default.
##
## Version-guard note: module/tirdad.c gates the TCP-ISN hook body on
## LINUX_VERSION_CODE (< 6.12.94, or 6.13.0..6.18.17). The 6.8 GA
## headers satisfy the first branch, so the security-relevant hook
## code is the code that gets compiled and extracted - not an empty
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

## Drive the repo's own Makefile ('make -C $(KERNELDIR) M=$(pwd)/module'),
## overriding only KERNELDIR. Compiles module/tirdad.c -> tirdad.o/.ko.
make KERNELDIR="${kerneldir}"

## Guard against the false-green where the lane reports success while
## the extractor saw no compiler invocation at all.
if [ ! -f module/tirdad.o ]; then
  printf '%s\n' "error: module/tirdad.o not produced; nothing was compiled" >&2
  exit 1
fi

ls -l -- module/tirdad.o module/tirdad.ko
