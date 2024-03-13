#! /bin/bash

set -e
echo Script to build Matter applications for different targets

_bld_help=0
_bld_host=0
_bld_rpi3=0
_bld_m5=0
_bld_bb=0
_bld_links=0
_bld_zap=0
_bld_clean=0
_bld_dsub=0
_bld_sync=0

_matter_git="/home/hcr/work/connectedhomeip"

_bb_sdk_env="/bigbend/bigbend_sdk/environment-setup-cortexa7t2hf-neon-vfpv4-lennox-linux-gnueabi"
_rpi3_sdk_env="/opt/rpi3/environment-setup-cortexa53-leos-linux"
_m5_sdk="/opt/esp-idf"

for i in $@
do
  if [ "$i" == "help" ]; then
    _bld_help=1
  fi

  if [ "$i" == "sync" ]; then
    _bld_sync=1
  fi

  if [ "$i" == "dsub" ]; then
    _bld_dsub=1
  fi

  if [ "$i" == "links" ]; then
    _bld_links=1
  fi

  if [ "$i" == "clean" ]; then
    _bld_clean=1
  fi

  if [ "$i" == "zap" ]; then
    _bld_zap=1
  fi

  if [ "$i" == "host" ]; then
    _bld_host=1
  fi

  if [ "$i" == "rpi3" ]; then
    _bld_rpi3=1
  fi

  if [ "$i" == "bb" ]; then
    _bld_bb=1
  fi

  if [ "$i" == "m5" ]; then
    _bld_m5=1
  fi
done

if [ $_bld_help -eq 0 ] && 
  [ $_bld_sync -eq 0 ] &&
  [ $_bld_dsub -eq 0 ] &&
  [ $_bld_links -eq 0 ] &&
  [ $_bld_zap -eq 0 ] && 
  [ $_bld_bb -eq 0 ] && 
  [ $_bld_rpi3 -eq 0 ] && 
  [ $_bld_m5 -eq 0 ] && 
  [ $_bld_host -eq 0 ]; then
  echo
  echo "Invalid usage"
  _bld_help=1
fi

if [ $_bld_help -eq 1 ]; then
  echo
  echo "Usage: bld [arguments]"
  echo
  echo "Supported arguments are,"
  echo "    help : Show this help screen"
  echo "   links : Setup links for samples"
  echo "     zap : Run zap tool"
  echo "      m5 : Build for M5Stack"
  echo "      bb : Build for BigBend"
  echo "    rpi3 : Build for RPi3B"
  echo "    host : Build for Host OS"
  echo "   clean : Clean the output folder before building"
  echo "    dsub : Delete submodules"
  echo "    sync : Sync repo with remote"
  echo
  exit 0
fi

check_and_clean()
{
  if [ $_bld_clean -eq 1 ] ; then
    echo Cleaning up the output folder $1
    rm -rf $1
  fi
}

strip_output()
{
  echo About to strip the output file $1 using $STRIP
  $STRIP -s $1
}

strip_outputs()
{
  echo Striping output from $1

  for output in chip-tool chip-lighting-app chip-bridge-app chip-all-clusters-app thermostat-app lx_mgw; do
    _file=$1/$output
    if [ -f "$_file" ]; then
      strip_output $_file
    fi
  done
}

build_for_rpi3()
{
  check_and_clean out/rpi3

  gn gen out/rpi3 --args='treat_warnings_as_errors=false target_os="linux" target_cpu="cortexa53"
    import("//build_overrides/build.gni")
    target_cflags=[
                    "-DCHIP_DEVICE_CONFIG_WIFI_STATION_IF_NAME=\"wlan0\"",
                    "-DCHIP_DEVICE_CONFIG_LINUX_DHCPC_CMD=\"udhcpc -b -i %s \"",
                    "-O3"
                    ]
    custom_toolchain="${build_root}/toolchain/custom"
    target_cc=getenv("CC")
    target_cxx=getenv("CXX")
    target_ar=getenv("AR")'

  ninja -C out/rpi3

  strip_outputs out/rpi3
}

build_for_bb()
{
  check_and_clean out/bb

  gn gen out/bb --args='treat_warnings_as_errors=false target_os="linux" target_cpu="cortex-a7"
    matter_commandline_enable_perfetto_tracing=false chip_build_tests=false chip_build_test_static_libraries=false
    chip_link_tests=false
    import("//build_overrides/build.gni")
    target_cflags=[
                    "-DCHIP_DEVICE_CONFIG_WIFI_STATION_IF_NAME=\"wlan0\"",
                    "-DCHIP_DEVICE_CONFIG_LINUX_DHCPC_CMD=\"udhcpc -b -i %s \"",
                    "-O3", 
                    "-Wno-format-security"
                    ]
    custom_toolchain="${build_root}/toolchain/custom"
    target_cc=getenv("CC")
    target_cxx=getenv("CXX")
    target_ar=getenv("AR")'

  ninja -C out/bb

  strip_outputs out/bb
}

setup_links()
{
    echo Setting up link to build overrides
    ln -s $_matter_git/examples/build_overrides build_overrides

    echo Creating link to the chip root
    mkdir third_party
    ln -s $_matter_git third_party/connectedhomeip

    echo Links created successfully
    exit 1
}

clean_sub_module()
{
	echo "Cleaning up submodule $1"

	echo "Removing the submodule entry from .git/config"
	git submodule deinit -f $1

	echo "Removing the submodule directory from the superproject's .git/modules directory"
	rm -rf .git/modules/$1

	echo "Removing the entry in .gitmodules and remove the submodule directory located at path/to/submodule"
	git rm -f $1

	echo "Cleaned submodule $1"
}

sync_remote()
{
  echo "Fetching upstream changes"
  git fetch upstream

  echo "Discarding working branch"
  git switch working
  git reset HEAD
  git stash

  echo "Synching master branch"
  git switch master
  git pull

  echo "Synching v1.1 branch"
  git switch v1.1-branch
  git pull

  echo "Synching working branch"
  git switch working
  git rebase v1.1-branch
  git stash pop

  echo "Working branch rebased to the latest as in v1.1-branch"
}

function check_and_clean() 
{
	_required="
		nlassert
		nlfaultinjection
		nlio
		nlunit-test
		qrcode
		m5stack-tft
		pigweed
		nanopb
		zap
		jsoncpp
		editline
		libwebsockets
	"
	_found=0

	for _module in $_required; 
	do
		if [ "$1" == *"$_module"* ]; then
			_found=1
		fi
	done

	if [ ! $_found -eq 1 ]; then
		clean_sub_module $1
	else
		echo "Skipping submodule $1"
	fi
}

delete_sub_modules()
{
	_file='.dsub_list'

	if [ ! -f "$_file" ]; then
		echo "Creating $_file with existing list of submodules"
		git config --file .gitmodules --get-regexp path | awk '{ print $2 }' >$_file
	fi

	while read -r _line; 
	do
		check_and_clean $_line
	done <$_file

	rm $_file
	exit 0
}

if [ $_bld_sync -eq 1 ]; then
  sync_remote
  exit 0
fi

if [ $_bld_dsub -eq 1 ]; then
  delete_sub_modules
fi

if [ $_bld_links -eq 1 ]; then
  setup_links
fi

if [ $_bld_m5 -eq 1 ]; then
  source $_m5_sdk/export.sh
fi

# For all the gn steps, we need pigweed / python for building data model
# source $_matter_git/scripts/activate.sh

if [ $_bld_zap -eq 1 ]; then
  XURL=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
  export DISPLAY=$XURL:0.0
  export LIBGL_ALWAYS_INDIRECT=1
  $_matter_git/scripts/tools/zap/run_zaptool.sh
fi

if [ $_bld_host -eq 1 ]; then
  gn gen out/host
  ninja -C out/host
fi

if [ $_bld_rpi3 -eq 1 ]; then
  source $_rpi3_sdk_env
  build_for_rpi3
fi

if [ $_bld_bb -eq 1 ]; then
  source $_bb_sdk_env
  source $_matter_git/scripts/activate.sh
  build_for_bb
fi

if [ $_bld_m5 -eq 1 ]; then
  export IDF_CCACHE_ENABLE=1
  idf.py set-target esp32
  rm sdkconfig
  idf.py -D 'SDKCONFIG_DEFAULTS=sdkconfig_m5stack.defaults' build
fi
