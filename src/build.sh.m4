#!/bin/bash

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# m4_ignore(
echo "This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11  #)Created by argbash-init v2.10.0
# ARG_OPTIONAL_BOOLEAN([check-dependencies], , [Check whether all dependencies needed for the script are installed], [on])
# ARG_OPTIONAL_BOOLEAN([check-compatibility], , [Check whether the kernel is compatible with this module], [on])
# ARG_OPTIONAL_BOOLEAN([force], , [Whether to force creation of DKMS Module], [off])
# ARG_OPTIONAL_BOOLEAN([safe-mode], , [Add a configuration to the DKMS Module so that it will be installed only for your specific kernel major-version], [on])
# ARG_OPTIONAL_SINGLE([kernel-version], , [Specify Kernel Version, will be auto-detected otherwise], [auto])
# ARGBASH_SET_DELIM([ =])
# ARG_OPTION_STACKING([getopt])
# ARG_HELP([Build the DKMS Module])
# ARGBASH_GO

# [ <-- needed because of Argbash

PACKAGE_VERSION="1.0"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SOURCE_DIR="${SCRIPT_DIR}/src"
DIST_DIR="${SCRIPT_DIR}/dist"
WORK_DIR="/tmp/i2c-i8042-dkms"

trap "exit 1" TERM
export TOP_PID=$$

_die() {
	kill -s TERM $TOP_PID
}

_log() {
	echo "${3:-}[${1}] ${2}"
}

_log_info() {
	_log "INFO" "${1}" "${2:-}"
}

_log_error() {
	_log "ERROR" "${1}" "${2:-}"
}

_log_done() {
	_log "DONE" "${1}" "${2:-}"
}

_check_dependency (){
	type "${1}" &> /dev/null;
}

_dependency_fulfilled() {
	_log_info "Dependency '${1}' is fulfilled!" "  > "
}

_dependency_missing() {
	_log_error "Dependency '${1}' is missing!" "  > "
	_die
}

_compatible_equal () {
	if [[ "${1}" == "${2}" ]]; then
		return "0"
	else
		return "1"
	fi
}

_is_compatible() {
	_log_info "${1} (${2}) is compatible!" "  > "
}

_not_compatible() {
	_log_error "${1} (${2}) is not compatible! (Should be ${3})" "  > "
	_die
}

_not_patchable() {
	_log_error "Could not patch ${1}! Aborting..." "  > "
	_die
}

_not_downloadable() {
	_log_error "Could not download ${1}! Aborting..." "  > "
	_die
}

if [[ ${_arg_check_dependencies} == "on" ]]; then
	_log_info "Running dependency check..."
	DEPENDENCIES=(sudo uname cat dmidecode wget bc sed)
	for DEPENDENCY in ${DEPENDENCIES[@]}; do
	  _check_dependency "${DEPENDENCY}" && _dependency_fulfilled "${DEPENDENCY}" || _dependency_missing "${DEPENDENCY}"
	done
else 
	_log_info "Skipping dependency check..."
fi

if [[ ${_arg_check_compatibility} == "on" ]]; then
	_log_info "Running compatibility check..."
	if [[ -f "/sys/class/dmi/id/product_name" ]];then
		PRODUCT_NAME=$(cat "/sys/class/dmi/id/product_name")
	else 
		PRODUCT_NAME=$(sudo dmidecode -s system-product-name)
	fi

	if [[ -f "/sys/class/dmi/id/sys_vendor" ]];then
		SYS_VENDOR=$(cat "/sys/class/dmi/id/sys_vendor")
	else 
		SYS_VENDOR=$(sudo dmidecode -s system-manufacturer)
	fi
	COMPATIBLE_SYS_VENVOR=("System Vendor" "${SYS_VENDOR}" "LENOVO")
	COMPATIBLE_PRODUCT_NAME=("System Vendor" "${PRODUCT_NAME}" "82YU")
	COMPTABILES=(COMPATIBLE_SYS_VENVOR COMPATIBLE_PRODUCT_NAME)
	COMPATIBLES_EQUALS=(COMPTABILES)
	declare -n OUTER INNER
	for OUTER in "${COMPATIBLES_EQUALS[@]}"; do
	    for INNER in "${OUTER[@]}"; do
	        _compatible_equal "${INNER[1]}" "${INNER[2]}" && _is_compatible "${INNER[0]}" ${INNER[1]} || _not_compatible "${INNER[0]}" "${INNER[1]}" "${INNER[2]}"
	    done
	done
else 
	_log_info "Skipping compatibility check..."
fi

if [[ "${_arg_kernel_version}" == 'auto' ]]; then
	_log_info "Detecting Kernel Version..."
	KERNEL_RELEASE=$(uname -r)
	KERNEL_VERSION=${KERNEL_RELEASE%%-*}
	KERNEL_VERSION=${KERNEL_VERSION%.*}
else
	KERNEL_VERSION="${_arg_kernel_version}"
fi
_log_done "Kernel Version: ${KERNEL_VERSION}" "  > "

if [[ -d "${DIST_DIR}/${KERNEL_VERSION}" && "${_arg_force}" == 'off' ]]; then
		_log_error "There already is a compiled DKMS package for your kernel version! Aborting..."  "  > "
		_log_info "Run the script with --force to force an overwrite!"  "  > "
		_die
fi

_log_info "Creating Workdir..."
rm -rf "${WORK_DIR}" || true
mkdir "${WORK_DIR}"
_log_done "Workdir '${WORK_DIR}' created!" "  > "

if [[ "$(echo "${KERNEL_VERSION} >= 6.1" | bc)" == 1 ]]; then
	wget -q "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/input/serio/i8042-acpipnpio.h?h=v${KERNEL_VERSION}" -O "${WORK_DIR}/i8042-acpipnpio.h" \
	 && _log_done "Downloaded i8042-acpipnpio.h!" "  > " || _not_downloadable "i8042-acpipnpio.h" "  > "
fi
wget -q "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/input/serio/i8042.c?h=v${KERNEL_VERSION}" -O "${WORK_DIR}/i8042.c" \
 && _log_done "Downloaded i8042.c!" "  > " || _not_downloadable "i8042.c" "  > "
wget -q "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/input/serio/i8042.h?h=v${KERNEL_VERSION}" -O "${WORK_DIR}/i8042.h" \
 && _log_done "Downloaded i8042.h!" "  > " || _not_downloadable "i8042.h" "  > "

_log_info "Patching downloaded kernel files..."

#if [[ "$(echo "${KERNEL_VERSION} >= 6.1" | bc)" == 1 ]]; then
#	I8042_ACPIPNPIO_PATCHFILE="patch/${KERNEL_VERSION}/i8042-acpipnpio.h.patch"
#	if [[ ! -f "${SOURCE_DIR}/${I8042_ACPIPNPIO_PATCHFILE}" ]]; then
#		_log_info "No i8042-acpipnpio.h patchfile found for kernel version ${KERNEL_VERSION}, trying generic patchfile..." "  > "
#		I8042_ACPIPNPIO_PATCHFILE="patch/i8042-acpipnpio.h.patch"
#	fi
#	patch --dry-run --quiet "${WORK_DIR}/i8042-acpipnpio.h" "${SOURCE_DIR}/${I8042_ACPIPNPIO_PATCHFILE}" &> /dev/null \
#	 && patch --quiet "${WORK_DIR}/i8042-acpipnpio.h" "${SOURCE_DIR}/${I8042_ACPIPNPIO_PATCHFILE}" && _log_done "Patched i8042-acpipnpio.h!" "  > " \
#	 ||  _not_patchable "i8042-acpipnpio.h"
#fi

I8042_PATCHFILE="patch/${KERNEL_VERSION}/i8042.c.patch"
if [[ ! -f "${SOURCE_DIR}/${I8042_PATCHFILE}" ]]; then
	_log_info "No i8042.c patchfile found for kernel version ${KERNEL_VERSION}, trying generic patchfile..." "  > "
	I8042_PATCHFILE="patch/i8042.c.patch"
fi
patch --dry-run --quiet "${WORK_DIR}/i8042.c" "${SOURCE_DIR}/${I8042_PATCHFILE}" &> /dev/null \
 && patch --quiet "${WORK_DIR}/i8042.c" "${SOURCE_DIR}/${I8042_PATCHFILE}" && _log_done "Patched i8042.c!" "  > " \
 ||  _not_patchable "i8042.c"



_log_info "Creating DKMS Module..."
cp "${SOURCE_DIR}/Makefile" "${WORK_DIR}/Makefile"
cp "${SOURCE_DIR}/dkms.conf" "${WORK_DIR}/dkms.conf"
if [[ "${_arg_safe_mode}" == 'on' ]]; then
	echo "" >> "${WORK_DIR}/dkms.conf"
	echo "BUILD_EXCLUSIVE_KERNEL=\"^${KERNEL_VERSION}.*\"" >> "${WORK_DIR}/dkms.conf"
	PACKAGE_VERSION="${PACKAGE_VERSION}-${KERNEL_VERSION}"
fi
sed -i "s/PACKAGE_VERSION=\"@PACKAGE_VERSION@\"/PACKAGE_VERSION=\"${PACKAGE_VERSION}\"/g" "${WORK_DIR}/dkms.conf"
rm -f ${WORK_DIR}/*.orig

if [[ -d "${DIST_DIR}/${KERNEL_VERSION}" && "${_arg_force}" == 'on' ]]; then
	rm -rf "${DIST_DIR}/${KERNEL_VERSION}"
fi
mv "${WORK_DIR}" "${DIST_DIR}/${KERNEL_VERSION}"
_log_done "DKMS Package created!" "  > "
_log_done "All done!"

# ] <-- needed because of Argbash




