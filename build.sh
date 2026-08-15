#!/bin/bash

## For CodeQL autobuild

## Keep the command trace: it is this script's diagnostic output.
set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

#sudo --non-interactive apt-get update --error-on=any
#sudo --non-interactive apt-get install --yes dkms

sudo --non-interactive make
