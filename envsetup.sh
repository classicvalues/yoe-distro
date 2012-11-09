#!/bin/bash

# Original script done by Don Darling
# Later changes by Koen Kooi and Brijesh Singh

# Revision history:
# 20090902: download from twiki
# 20090903: Weakly assign MACHINE and DISTRO
# 20090904:  * Don't recreate local.conf is it already exists
#            * Pass 'unknown' machines to OE directly
# 20090918: Fix /bin/env location
#           Don't pass MACHINE via env if it's not set
#           Changed 'build' to 'bitbake' to prepare people for non-scripted usage
#           Print bitbake command it executes
# 20091012: Add argument to accept commit id.
# 20091202: Fix proxy setup

# Changes by Cliff Brake
# 20111101: modify script to work with BEC build template
#

###############################################################################
# Machine/Distro setup -- this is the main configuration for the build
# these variables can be set externally in the shell, or here
###############################################################################

if [ -n "${MACHINE-1}" ]; then export MACHINE=beagleboard; fi
if [ -n "${DISTRO-1}" ]; then export DISTRO=angstrom-next; fi


###############################################################################
# User specific vars like proxy servers
###############################################################################

#PROXYHOST=wwwgate.ti.com
#PROXYPORT=80
PROXYHOST=""

###############################################################################
# OE_BASE    - The root directory for all OE sources and development.
###############################################################################
OE_BASE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# incremement this to force recreation of config files.  This should be done
# whenever anything major changes
BASE_VERSION=6
OE_ENV_FILE=localconfig.sh

# Workaround for differences between yocto bitbake and vanilla bitbake
export BBFETCH2=True

export DISTRO_DIRNAME=`echo $DISTRO | sed s#[.-]#_#g`
export OE_DEPLOY_DIR=${OE_BASE}/build/tmp-${DISTRO_DIRNAME}-eglibc/deploy/images/${MACHINE}

#--------------------------------------------------------------------------
# Specify the root directory for your OpenEmbedded development
#--------------------------------------------------------------------------
OE_BUILD_DIR=${OE_BASE}
OE_BUILD_TMPDIR="${OE_BUILD_DIR}/build/tmp-${DISTRO_DIRNAME}"
OE_SOURCE_DIR=${OE_BASE}/sources

export BUILDDIR=${OE_BUILD_DIR}
mkdir -p ${OE_BUILD_DIR}
mkdir -p ${OE_SOURCE_DIR}
export OE_BASE

#--------------------------------------------------------------------------
# Include up-to-date bitbake in our PATH.
#--------------------------------------------------------------------------
export PATH=${OE_SOURCE_DIR}/openembedded-core/scripts:${OE_SOURCE_DIR}/bitbake/bin:${PATH}
# remove duplicate entries from path
# export PATH=`echo $PATH_ | awk -F: '{for (i=1;i<=NF;i++) { if ( !x[$i]++ ) printf("%s:",$i); }}'`
export PATH=`awk -F: '{for(i=1;i<=NF;i++){if(!($i in a)){a[$i];printf s$i;s=":"}}}'<<<$PATH`

#--------------------------------------------------------------------------
# Make sure Bitbake doesn't filter out the following variables from our
# environment.
#--------------------------------------------------------------------------
export BB_ENV_EXTRAWHITE="MACHINE DISTRO TCLIBC TCMODE GIT_PROXY_COMMAND http_proxy ftp_proxy https_proxy all_proxy ALL_PROXY no_proxy SSH_AGENT_PID SSH_AUTH_SOCK BB_SRCREV_POLICY SDKMACHINE BB_NUMBER_THREADS OE_BASE SVS_VERSION"

#--------------------------------------------------------------------------
# Specify proxy information
#--------------------------------------------------------------------------
if [ "x$PROXYHOST" != "x"  ] ; then
    export http_proxy=http://${PROXYHOST}:${PROXYPORT}/
    export ftp_proxy=http://${PROXYHOST}:${PROXYPORT}/

    export SVN_CONFIG_DIR=${OE_BUILD_DIR}/subversion_config
    export GIT_CONFIG_DIR=${OE_BUILD_DIR}/git_config

    export GIT_PROXY_COMMAND="${GIT_CONFIG_DIR}/git-proxy.sh"

    config_svn_proxy
    config_git_proxy
fi

#--------------------------------------------------------------------------
# Set up the bitbake path to find the OpenEmbedded recipes.
#--------------------------------------------------------------------------
export BBPATH=${OE_BUILD_DIR}:${OE_SOURCE_DIR}/openembedded-core/meta${BBPATH_EXTRA}

#--------------------------------------------------------------------------
# Reconfigure dash
#--------------------------------------------------------------------------
if [ "$(readlink /bin/sh)" = "dash" ] ; then
    sudo aptitude install expect -y
    expect -c 'spawn sudo dpkg-reconfigure -freadline dash; send "n\n"; interact;'
fi


#--------------------------------------------------------------------------
# If an env already exists, use it, otherwise generate it
#--------------------------------------------------------------------------

if [ -e ${OE_ENV_FILE} ] ; then
    . ${OE_ENV_FILE}
fi

if [ x"${BASE_VERSION}" != x"${SCRIPTS_BASE_VERSION}" ] ; then
	echo "BASE_VERSION mismatch, recreating ${OE_ENV_FILE}"
	rm -f ${OE_ENV_FILE}

elif [ x"${DISTRO_DIRNAME}" != x"${SCRIPTS_DISTRO_DIRNAME}" ] ; then
  echo "DISTRO name has changed, recreating ${OE_ENV_FILE}"
  rm -f ${OE_ENV_FILE}
fi

if [ -e ${OE_ENV_FILE} ] ; then
    . ${OE_ENV_FILE}
else

    #--------------------------------------------------------------------------
    # Specify distribution information
    #--------------------------------------------------------------------------

    echo "export SCRIPTS_BASE_VERSION=${BASE_VERSION}" > ${OE_ENV_FILE}
    echo "export SCRIPTS_DISTRO_DIRNAME=\"${DISTRO_DIRNAME}\"" >> ${OE_ENV_FILE}


    echo "${OE_ENV_FILE} created"

    #--------------------------------------------------------------------------
    # Write out the OE bitbake configuration file.
    #--------------------------------------------------------------------------
    mkdir -p ${OE_BUILD_DIR}/conf

    SITE_CONF=${OE_BUILD_DIR}/conf/site.conf
    cat > $SITE_CONF <<_EOF

SCONF_VERSION = "1"

# Where to store sources
DL_DIR = "${OE_SOURCE_DIR}/downloads"

# Where to save shared state
SSTATE_DIR = "${OE_BUILD_DIR}/build/sstate-cache"

# Which files do we want to parse:
BBFILES ?= "${OE_SOURCE_DIR}/openembedded-core/meta/recipes-*/*/*.bb"

TMPDIR = "${OE_BUILD_TMPDIR}"

# Go through the Firewall
#HTTP_PROXY        = "http://${PROXYHOST}:${PROXYPORT}/"

_EOF

    echo "${SITE_CONF} has been updated"

fi # if -e ${OE_ENV_FILE}

###############################################################################
# UPDATE_ALL() - Make sure everything is up to date
###############################################################################
function oe_update_all()
{
    git submodule update
}

function oe_update_all_submodules_to_master
{
  git submodule foreach "git checkout master && git pull"
}

###############################################################################
# CLEAN_OE() - Delete TMPDIR
###############################################################################
function oe_clean()
{
    echo "Cleaning ${OE_BUILD_TMPDIR}"
    rm -rf ${OE_BUILD_TMPDIR}
}


###############################################################################
# OE_CONFIG() - Configure OE for a target
# machine is first parameter
###############################################################################
function oe_setup()
{
    git submodule init
    git submodule update

}

###############################################################################
# CONFIG_SVN_PROXY() - Configure subversion proxy information
###############################################################################
function oe_config_svn_proxy()
{
    if [ ! -f ${SVN_CONFIG_DIR}/servers ]
    then
        mkdir -p ${SVN_CONFIG_DIR}
        cat >> ${SVN_CONFIG_DIR}/servers <<_EOF
[global]
http-proxy-host = ${PROXYHOST}
http-proxy-port = ${PROXYPORT}
_EOF
    fi
}


###############################################################################
# CONFIG_GIT_PROXY() - Configure GIT proxy information
###############################################################################
function oe_config_git_proxy()
{
    if [ ! -f ${GIT_CONFIG_DIR}/git-proxy.sh ]
    then
        mkdir -p ${GIT_CONFIG_DIR}
        cat > ${GIT_CONFIG_DIR}/git-proxy.sh <<_EOF
if [ -x /bin/env ] ; then
    exec /bin/env corkscrew ${PROXYHOST} ${PROXYPORT} \$*
else
    exec /usr/bin/env corkscrew ${PROXYHOST} ${PROXYPORT} \$*
fi
_EOF
        chmod +x ${GIT_CONFIG_DIR}/git-proxy.sh
        export GIT_PROXY_COMMAND=${GIT_CONFIG_DIR}/git-proxy.sh
    fi
}

function oe_partition_sd_3()
{
  # create 3 partitions
  # taken from a standalone script
  # (c) 2009 Graeme Gregory
  # This script is GPLv3 licensed!

  if [ ! $1 ]; then
    echo "Usage: antero_partition_sd /dev/sdX"
    echo "Warning, make sure you specify your SD card and not a workstation disk"
    echo
    return 1
  fi

  DRIVE=$1

  sudo umount ${DRIVE}1 2>/dev/null
  sudo umount ${DRIVE}2 2>/dev/null
  sudo umount ${DRIVE}3 2>/dev/null

  sudo dd if=/dev/zero of=$DRIVE bs=1024 count=1024

  SIZE=`sudo fdisk -l $DRIVE | grep Disk | awk '{print $5}'`

  echo DISK SIZE - $SIZE bytes

  CYLINDERS=`echo $SIZE/255/63/512 | bc`
  CYLINDER_SIZE=`echo $SIZE/$CYLINDERS | bc`
  CYLINDERS_ROOTFS=`echo 700*1024*1024/$CYLINDER_SIZE | bc`

  echo CYLINDERS - $CYLINDERS
  echo CYLINDERS in rootfs - $CYLINDERS_ROOTFS

  {
  echo ,9,0x0C,*
  echo ,$CYLINDERS_ROOTFS,0x83,-
  echo ,,0x83,-
  } | sudo sfdisk -D -H 255 -S 63 -C $CYLINDERS $DRIVE

  sudo mkfs.vfat -F 32 -n "omap-boot" ${DRIVE}1
  sudo mke2fs -j -L "omap-rootfs" ${DRIVE}2
  sudo mke2fs -j -L "omap-data" ${DRIVE}3
}

function oe_partition_sd()
{
  # create 2 partitions
  # taken from a standalone script
  # (c) 2009 Graeme Gregory
  # This script is GPLv3 licensed!

  if [ ! $1 ]; then
    echo "Usage: antero_partition_sd /dev/sdX"
    echo "Warning, make sure you specify your SD card and not a workstation disk"
    echo
    return 1
  fi

  DRIVE=$1

  sudo umount ${DRIVE}1 2>/dev/null
  sudo umount ${DRIVE}2 2>/dev/null

  sudo dd if=/dev/zero of=$DRIVE bs=1024 count=1024

  SIZE=`sudo fdisk -l $DRIVE | grep Disk | awk '{print $5}'`

  echo DISK SIZE - $SIZE bytes

  CYLINDERS=`echo $SIZE/255/63/512 | bc`
  CYLINDER_SIZE=`echo $SIZE/$CYLINDERS | bc`
  CYLINDERS_ROOTFS=`echo 512*1024*1024/$CYLINDER_SIZE | bc`

  echo CYLINDERS - $CYLINDERS
  echo CYLINDERS in rootfs - $CYLINDERS_ROOTFS

  {
  echo ,9,0x0C,*
  echo ,,0x83,-
  } | sudo sfdisk -D -H 255 -S 63 -C $CYLINDERS $DRIVE

  sudo mkfs.vfat -F 32 -n "omap-boot" ${DRIVE}1
  sudo mke2fs -j -L "omap-rootfs" ${DRIVE}2
}

function oe_install_sd_rootfs_systemd_image
{
  echo "Installing rootfs files ..."
  if [ ! -e /media/omap-rootfs ]; then
    echo "/media/omap-rootfs not found, please insert or partition SD card"
    return 1
  fi

  sudo rm -rf /media/omap-rootfs/*
  cd /media/omap-rootfs/
  sudo tar -xjvf ${OE_DEPLOY_DIR}/systemd-image-beagleboard.tar.bz2
  cd -
}

function oe_install_sd_rootfs_systemd_gnome_image
{
  echo "Installing rootfs files ..."
  if [ ! -e /media/omap-rootfs ]; then
    echo "/media/omap-rootfs not found, please insert or partition SD card"
    return 1
  fi

  sudo rm -rf /media/omap-rootfs/*
  cd /media/omap-rootfs/
  sudo tar -xjvf ${OE_DEPLOY_DIR}/systemd-GNOME-image-beagleboard.tar.bz2
  cd -
}

function oe_install_sd_boot
{
  cp ${OE_DEPLOY_DIR}/MLO /media/omap-boot/MLO
  cp ${OE_DEPLOY_DIR}/u-boot.img /media/omap-boot/
  cp ${OE_DEPLOY_DIR}/uImage-beagleboard.bin /media/omap-boot/uImage
}

function oe_sync_feed()
{
  bitbake package-index
  rsync -av --delete ${OE_BUILD_TMPDIR}-eglibc/deploy/ipk/ /var/www/oe-build-core/
}


###############################################################################
# setup for cross compiling programs manually
# the following variables are needed to cross compile kernel/u-boot,
# most applications, Qt apps, etc.
###############################################################################

BUILD_ARCH=`uname -m`
CROSS_COMPILER_PATH=${OE_BUILD_TMPDIR}-eglibc/sysroots/${BUILD_ARCH}-linux/usr/bin/armv7a-vfp-neon-angstrom-linux-gnueabi
OE_STAGING_PATH=${OE_BUILD_TMPDIR}-eglibc/sysroots/${BUILD_ARCH}-linux/usr/bin
export PATH=$CROSS_COMPILER_PATH:$OE_STAGING_PATH:$PATH
export ARCH=arm
export CROSS_COMPILE=arm-angstrom-linux-gnueabi-

export PKG_CONFIG_PATH=${OE_BUILD_TMPDIR}-eglibc/sysroots/cm-x270/usr/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=${OE_BUILD_TMPDIR}-eglibc/sysroots/cm-x270

# FIXME, the rest needs finished
export QMAKESPEC="${TOPDIR}/tmp/sysroots/armv7a-angstrom-linux-gnueabi/usr/share/qt4/mkspecs/linux-gnueabi-oe-g++"

export OE_QMAKE_CC=arm-angstrom-linux-gnueabi-gcc
export OE_QMAKE_CXX=arm-angstrom-linux-gnueabi-g++
export OE_QMAKE_LINK=arm-angstrom-linux-gnueabi-g++
export OE_QMAKE_LIBDIR_QT="${TOPDIR}/tmp/sysroots/armv7a-angstrom-linux-gnueabi/usr/lib"
export OE_QMAKE_INCDIR_QT="${TOPDIR}/tmp/sysroots/armv7a-angstrom-linux-gnueabi/usr/include/qt4"
export OE_QMAKE_MOC="${TOPDIR}/tmp/sysroots/x86_64-linux/usr/bin/moc4"
export OE_QMAKE_UIC="${TOPDIR}/tmp/sysroots/x86_64-linux/usr/bin/uic4"
export OE_QMAKE_UIC3="${TOPDIR}/tmp/sysroots/x86_64-linux/usr/bin/uic34"
export OE_QMAKE_RCC="${TOPDIR}/tmp/sysroots/x86_64-linux/usr/bin/rcc4"
export OE_QMAKE_QDBUSCPP2XML="${TOPDIR}/tmp/sysroots/x86_64-linux/usr/bin/qdbuscpp2xml4"
export OE_QMAKE_QDBUSXML2CPP="${TOPDIR}/tmp/sysroots/x86_64-linux/usr/bin/qdbusxml2cpp4"
export OE_QMAKE_QT_CONFIG="{TOPDIR}/tmp/sysroots/x86_64-linux/usr/share/qtopia/mkspecs/qconfig.pri"




