#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

cd "$(dirname -- "$(readlink -f -- "$0")")"

usage() {
cat << HEREDOC
Usage: $0 --board=[orangepi-5|orangepi-5b|orangepi-5-plus|rock-5b|rock-5a|radxa-cm5-io|nanopc-t6|nanopi-r6c|nanopi-r6s|indiedroid-nova|mixtile-blade3|lubancat-4|hinlink-h88k]

Required arguments:
  -b, --board=BOARD     target board 

Optional arguments:
  -h, --help            show this help message and exit
  -c, --clean           clean the build directory
  -d, --docker          use docker to build
  -k, --kernel-only     only compile the kernel
  -u, --uboot-only      only compile uboot
  -l, --launchpad       use kernel and uboot from launchpad repo
  -v, --verbose         increase the verbosity of the bash script
HEREDOC
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")"

for i in "$@"; do
    case $i in
        -h|--help)
            usage
            exit 0
            ;;
        -b=*|--board=*)
            export BOARD="${i#*=}"
            shift
            ;;
        -b|--board)
            export BOARD="${2}"
            shift
            ;;
        -d|--docker)
            DOCKER="docker run --privileged --network=host --rm -it -v \"$(pwd)\":/opt -e BOARD -e VENDOR -e LAUNCHPAD ubuntu-rockchip-build /bin/bash"
            docker build -t ubuntu-rockchip-build docker
            shift
            ;;
        -k|--kernel-only)
            export KERNEL_ONLY=Y
            shift
            ;;
        -u|--uboot-only)
            export UBOOT_ONLY=Y
            shift
            ;;
        -l|--launchpad)
            export LAUNCHPAD=Y
            shift
            ;;
        -c|--clean)
            export CLEAN=Y
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        -*)
            echo "Error: unknown argument \"$i\""
            exit 1
            ;;
        *)
            ;;
    esac
done

if [[ -z ${BOARD} ]]; then
    usage
    exit 1
fi

if [[ ${CLEAN} == "Y" ]]; then
    if [ -d build/rootfs ]; then
        umount -lf build/rootfs/dev/pts 2> /dev/null || true
        umount -lf build/rootfs/* 2> /dev/null || true
    fi
    rm -rf build
fi

if [ "${BOARD}" == orangepi-5 ] || [ "${BOARD}" == orangepi-5b ] || [ "${BOARD}" == orangepi-5-plus ]; then
    export VENDOR=orangepi
elif [ "${BOARD}" == rock-5b ] || [ "${BOARD}" == rock-5a ] || [ "${BOARD}" == radxa-cm5-io ]; then
    export VENDOR=radxa
elif [ "${BOARD}" == nanopi-r6c ] || [ "${BOARD}" == nanopi-r6s ] || [ "${BOARD}" == nanopc-t6 ]; then
    export VENDOR=friendlyelec
elif [ "${BOARD}" == indiedroid-nova ]; then
    export VENDOR=9tripod
elif [ "${BOARD}" == mixtile-blade3 ]; then
    export VENDOR=mixtile
elif [ "${BOARD}" == lubancat-4 ]; then
    export VENDOR=lubancat
elif [ "${BOARD}" == hinlink-h88k ]; then
    export VENDOR=hinlink
else
    echo "Error: \"${BOARD}\" is an unsupported board"
    exit 1
fi

mkdir -p build/logs
exec > >(tee "build/logs/build-$(date +"%Y%m%d%H%M%S").log") 2>&1

if [[ ${KERNEL_ONLY} == "Y" ]]; then
    eval "${DOCKER}" ./scripts/build-kernel.sh
    exit 0
fi

if [[ ${UBOOT_ONLY} == "Y" ]]; then
    eval "${DOCKER}" ./scripts/build-u-boot.sh
    exit 0
fi

if [[ ${LAUNCHPAD} != "Y" ]]; then
    for file in build/linux-{headers,image}-5.10.160-rockchip_*.deb; do
        if [ ! -e "$file" ]; then
            eval "${DOCKER}" ./scripts/build-kernel.sh
        fi
    done
fi

if [[ ${LAUNCHPAD} != "Y" ]]; then
    eval "${DOCKER}" ./scripts/build-u-boot.sh
fi

eval "${DOCKER}" ./scripts/build-rootfs.sh
eval "${DOCKER}" ./scripts/config-image.sh

exit 0
