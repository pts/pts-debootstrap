#!/bin/sh
#
# pts-debootstrap: portable debootstrap for i386 and amd64
# by pts@fazekas.hu at Wed Jul 18 01:42:11 CEST 2018
#
# TODO(pts): Omit the warning when configuring packages for slink.
# TODO(pts): When installing trusty to a trusty host, omit killing processes:
#            [30898.009903] init: upstart-udev-bridge main process (13467) terminated with status 1
#            [30898.010287] init: upstart-socket-bridge main process (13472) terminated with status 1
#            [30898.010625] init: upstart-file-bridge main process (13473) terminated with status 1
#

if true; then

VERSION='1.0.89-pts3'

unset F
if test "${PTS_DEBOOTSTRAP_BUSYBOX%/*}" = "$PTS_DEBOOTSTRAP_BUSYBOX"; then
  unset BASE_URL
  F="$0"
  test "${0#*/}" = "$0" && F="$(IFS=":"; for D in $PATH; do if test -e "$D/$0"; then echo "$D/$0"; exit; fi; done)"
  if test "$F" && test -f "$F"; then
    PTS_DEBOOTSTRAP_BUSYBOX="${F%/*}"/busybox.pts-debootstrap
    export PTS_DEBOOTSTRAP_BUSYBOX
    test -f "$PTS_DEBOOTSTRAP_BUSYBOX" && test -x "$PTS_DEBOOTSTRAP_BUSYBOX" &&
        exec "$PTS_DEBOOTSTRAP_BUSYBOX" sh "$F" "$@"
    PTS_DEBOOTSTRAP_BUSYBOX="${F%/*}"/pts-debootstrap
    test -f "$PTS_DEBOOTSTRAP_BUSYBOX" && test -x "$PTS_DEBOOTSTRAP_BUSYBOX" &&
        exec "$PTS_DEBOOTSTRAP_BUSYBOX" sh "$F" "$@"
  fi
  echo "E: busybox not found in: $0"
  exit 121
fi
export PTS_DEBOOTSTRAP_BUSYBOX
export PATH=/dev/null/missing  # Don't look for commands in /usr/bin etc.
unset DEBOOTSTRAP_DIR LANG LANGUAGE LC_CTYPE LC_ALL LD_PRELOAD LD_LIBRARY_PATH
DEBOOTSTRAP_DIR="${PTS_DEBOOTSTRAP_BUSYBOX%/*}"
export LC_ALL=C

if ! test -f "$DEBOOTSTRAP_DIR/functions"; then
  echo "E: missing functions file: $DEBOOTSTRAP_DIR/functions"
  exit 121
fi

# Shell builtins: true, false, pwd, printf, [, [[, test, echo, cd, exit,
# exec.
for F in ar bunzip2 bzcat cat chmod chown chroot cp cut env grep gunzip \
    head id ln md5sum mkdir mknod mount mv pkgdetails readlink rm rmdir \
    sed sh sleep sort sync tar touch tr umount uname uniq unxz wc \
    wget xzcat yes zcat sha1sum sha256sum sha512sum; do
  eval "$F () { \"\$PTS_DEBOOTSTRAP_BUSYBOX\" busybox $F \"\$@\"; }"
done

# TODO(pts): Always mention $TARGET/debootstrap/debootstrap.log on error exit.
set -e

###########################################################################

. "$DEBOOTSTRAP_DIR/functions"
exec 4>&1

export LANG=C LANGUAGE=C LC_ALL=C
USE_COMPONENTS=main
KEYRING=""
DISABLE_KEYRING=""
FORCE_KEYRING=""
VARIANT=""
MERGED_USR="no"
ARCH=i386  #ARCH=""   #### pts ####
HOST_OS=""  # TODO(pts): Remove non-Linux code.
KEEP_DEBOOTSTRAP_DIR=""
USE_DEBIANINSTALLER_INTERACTION=""
SECOND_STAGE_ONLY=""
PRINT_DEBS=""
CHROOTDIR=""
MAKE_TARBALL=""
UNPACK_TARBALL=""
ADDITIONAL=""
EXCLUDE=""
VERBOSE=""
CERTIFICATE=""
CHECKCERTIF=""
PRIVATEKEY=""

export LANG USE_COMPONENTS
umask 022

###########################################################################

## phases:
##   finddebs dldebs printdebs first_stage second_stage

RESOLVE_DEPS=true

WHAT_TO_DO="finddebs dldebs first_stage second_stage"
am_doing_phase () {
	# usage:   if am_doing_phase finddebs; then ...; fi
	local x;
	for x in "$@"; do
		if echo " $WHAT_TO_DO " | grep -q " $x "; then return 0; fi
	done
	return 1
}

###########################################################################

usage_err()
{
	info USAGE1 "usage: [OPTION]... <suite> <target> [<mirror> [<script>]]"
	info USAGE2 "Try \`${0##*/} --help' for more information."
	error "$@"
}

usage()
{
	echo "Usage: ${0##*/} [OPTION]... <suite> <target> [<mirror> [<script>]]"
	echo "Bootstrap a Debian base system into a target directory."
	echo
	cat <<EOF
      --help                 display this help and exit
      --version              display version information and exit
      --verbose              don't turn off the output of wget

      --download-only        download packages, but don't perform installation
      --print-debs           print the packages to be installed, and exit

      --arch=A               set the architecture to install (use if no dpkg)
                               [ --arch=powerpc ]

      --include=A,B,C        adds specified names to the list of base packages
      --exclude=A,B,C        removes specified packages from the list
      --components=A,B,C     use packages from the listed components of the
                             archive
      --variant=X            use variant X of the bootstrap scripts
                             (currently supported variants: buildd, fakechroot,
                              minbase)
      --merged-usr           make /{bin,sbin,lib}/ symlinks to /usr/
      --keyring=K            check Release files against keyring K
      --no-check-gpg         avoid checking Release file signatures
      --force-check-gpg      force checking Release file signatures
                             (also disables automatic fallback to HTTPS in case
                             of a missing keyring), aborting otherwise
      --no-resolve-deps      don't try to resolve dependencies automatically

      --unpack-tarball=T     acquire .debs from a tarball instead of http
      --make-tarball=T       download .debs and create a tarball (tgz format)
      --second-stage-target=DIR
                             Run second stage in a subdirectory instead of root
                               (can be used to create a foreign chroot)
                               (requires --second-stage)
      --extractor=TYPE       override automatic .deb extractor selection
                               (supported: ar)
      --debian-installer     used for internal purposes by debian-installer
      --private-key=file     read the private key from file
      --certificate=file     use the client certificate stored in file (PEM)
      --no-check-certificate do not check certificate against certificate authorities
EOF
}

###########################################################################

if [ $# != 0 ] ; then
    while true ; do
	case "$1" in
	    --help)
		usage
		exit 0
		;;
	    --version)
		echo "debootstrap $VERSION"
		exit 0
		;;
	    --debian-installer)
		if ! (echo -n "" >&3) 2>/dev/null; then
			error 1 ARG_DIBYHAND "If running debootstrap by hand, don't use --debian-installer"
		fi
		USE_DEBIANINSTALLER_INTERACTION=yes
		shift
		;;
	    --foreign)
		if [ "$PRINT_DEBS" != "true" ]; then
			WHAT_TO_DO="finddebs dldebs first_stage"
		fi
		shift
		;;
	    --second-stage)
		WHAT_TO_DO="second_stage"
		SECOND_STAGE_ONLY=true
		shift
		;;
	    --second-stage-target|--second-stage-target=?*)
		if [ "$SECOND_STAGE_ONLY" != "true" ] ; then
			error 1 STAGE2ONLY "option %s only applies in the second stage" "$1"
		fi
		if [ "$1" = "--second-stage-target" -a -n "$2" ] ; then
			CHROOTDIR="$2"
			shift 2
		elif [ "$1" != "${1#--second-stage-target=}" ]; then
			CHROOTDIR="${1#--second-stage-target=}"
			shift
		else
			error 1 NEEDARG "option requires an argument: %s" "$1"
		fi
		;;
	    --print-debs)
		WHAT_TO_DO="finddebs printdebs kill_target"
		PRINT_DEBS=true
		shift
		;;
	    --download-only)
		WHAT_TO_DO="finddebs dldebs"
		shift
		;;
	    --make-tarball|--make-tarball=?*)
		WHAT_TO_DO="finddebs dldebs maketarball kill_target"
		if [ "$1" = "--make-tarball" -a -n "$2" ] ; then
			MAKE_TARBALL="$2"
			shift 2
		elif [ "$1" != "${1#--make-tarball=}" ]; then
			MAKE_TARBALL="${1#--make-tarball=}"
			shift
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		;;
	    --resolve-deps)
		# redundant, but avoids breaking compatibility
		RESOLVE_DEPS=true
		shift
		;;
	    --no-resolve-deps)
		RESOLVE_DEPS=false
		shift
		;;
	    --keep-debootstrap-dir)
		KEEP_DEBOOTSTRAP_DIR=true
		shift
		;;
	    --arch|--arch=?*)
		if [ "$1" = "--arch" -a -n "$2" ] ; then
			ARCH="$2"
			shift 2
                elif [ "$1" != "${1#--arch=}" ]; then
			ARCH="${1#--arch=}"
			shift
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		;;
	    --extractor|--extractor=?*)  # Ignore. Use the built-in extract_deb_* using ar.
		if [ "$1" = "--extractor" -a -n "$2" ] ; then
			shift 2
		elif [ "$1" != "${1#--extractor=}" ]; then
			shift
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		;;
	    --unpack-tarball|--unpack-tarball=?*)
		if [ "$1" = "--unpack-tarball" -a -n "$2" ] ; then
			UNPACK_TARBALL="$2"
			shift 2
		elif [ "$1" != "${1#--unpack-tarball=}" ]; then
			UNPACK_TARBALL="${1#--unpack-tarball=}"
			shift
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		if [ ! -f "$UNPACK_TARBALL" ] ; then
			error 1 NOTARBALL "%s: No such file or directory" "$UNPACK_TARBALL"
		fi
		;;
	    --include|--include=?*)
		if [ "$1" = "--include" -a -n "$2" ]; then
			ADDITIONAL="$2"
			shift 2
                elif [ "$1" != "${1#--include=}" ]; then
			ADDITIONAL="${1#--include=}"
			shift 1
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		ADDITIONAL="$(echo "$ADDITIONAL" | tr , " ")"
		;;
	    --exclude|--exclude=?*)
		if [ "$1" = "--exclude" -a -n "$2" ]; then
			EXCLUDE="$2"
			shift 2
                elif [ "$1" != "${1#--exclude=}" ]; then
			EXCLUDE="${1#--exclude=}"
			shift 1
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		EXCLUDE="$(echo "$EXCLUDE" | tr , " ")"
		;;
	    --verbose)
		VERBOSE=true
		export VERBOSE
		shift 1
		;;
	    --components|--components=?*)
		if [ "$1" = "--components" -a -n "$2" ]; then
			USE_COMPONENTS="$2"
			shift 2
                elif [ "$1" != "${1#--components=}" ]; then
			USE_COMPONENTS="${1#--components=}"
			shift 1
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		USE_COMPONENTS="$(echo "$USE_COMPONENTS" | tr , "|")"
		;;
	    --variant|--variant=?*)
		if [ "$1" = "--variant" -a -n "$2" ]; then
			VARIANT="$2"
			shift 2
                elif [ "$1" != "${1#--variant=}" ]; then
			VARIANT="${1#--variant=}"
			shift 1
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		;;
            --merged-usr)
		MERGED_USR=yes
		shift
		;;
	    --no-merged-usr)
		MERGED_USR=no
		shift
		;;
	    --keyring|--keyring=?*)
		if ! gpgv --version >/dev/null 2>&1; then
			error 1 NEEDGPGV "gpgv not installed, but required for Release verification"
		fi
		if [ "$1" = "--keyring" -a -n "$2" ]; then
			KEYRING="$2"
			shift 2
                elif [ "$1" != "${1#--keyring=}" ]; then
			KEYRING="${1#--keyring=}"
			shift 1
		else
			error 1 NEEDARG "option requires an argument %s" "$1"
		fi
		;;
	    --no-check-gpg)
			shift 1
			DISABLE_KEYRING=1
		;;
	    --force-check-gpg)
			shift 1
			FORCE_KEYRING=1
		;;
	    --certificate|--certificate=?*)
		if [ "$1" = "--certificate" -a -n "$2" ]; then
			CERTIFICATE="--certificate=$2"
			shift 2
		elif [ "$1" != "${1#--certificate=}" ]; then
			CERTIFICATE="--certificate=${1#--certificate=}" 
			shift 1
		else
		       error 1 NEEDARG "option requires an argument %s" "$1" 
		fi
		;;
	    --private-key|--private-key=?*)
		if [ "$1" = "--private-key" -a -n "$2" ]; then
			PRIVATEKEY="--private-key=$2"
			shift 2
		elif [ "$1" != "${1#--private-key=}" ]; then
			PRIVATEKEY="--private-key=${1#--private-key=}" 
			shift 1
		else
		       error 1 NEEDARG "option requires an argument %s" "$1" 
		fi
		;;
	    --no-check-certificate)
		CHECKCERTIF="--no-check-certificate"
		shift
		;;
	    -*)
		error 1 BADARG "unrecognized or invalid option %s" "$1"
		;;
	    *)
		break
		;;
	esac
    done
fi

###########################################################################

if [ -n "$DISABLE_KEYRING" -a -n "$FORCE_KEYRING" ]; then
	error 1 BADARG "Both --no-check-gpg and --force-check-gpg specified, please pick one (at most)"
fi

###########################################################################

if [ "$SECOND_STAGE_ONLY" = "true" ]; then
	SUITE=$(cat "$DEBOOTSTRAP_DIR/suite")
	ARCH=$(cat "$DEBOOTSTRAP_DIR/arch")
	if [ -e "$DEBOOTSTRAP_DIR/variant" ]; then
		VARIANT=$(cat "$DEBOOTSTRAP_DIR/variant")
		SUPPORTED_VARIANTS="$VARIANT"
	fi
	if [ -z "$CHROOTDIR" ]; then
		TARGET=/
	else
		TARGET="$CHROOTDIR"
	fi
	SCRIPT="$DEBOOTSTRAP_DIR/suite-script"
else
	if [ -z "$1" ] || [ -z "$2" ]; then
		usage_err 1 NEEDSUITETARGET "You must specify a suite and a target."
	fi
	SUITE="$1"
	TARGET="$2"
	USER_MIRROR="$3"
	TARGET="${TARGET%/}"
	if [ "${TARGET#/}" = "${TARGET}" ]; then
		if [ "${TARGET%/*}" = "$TARGET" ] ; then
			TARGET="$(echo "`pwd`/$TARGET")"
		else
			TARGET="$(cd "${TARGET%/*}"; echo "`pwd`/${TARGET##*/}")"
		fi
	fi

	SCRIPT="$DEBOOTSTRAP_DIR/scripts/$1"
	if [ -n "$VARIANT" ] && [ -e "${SCRIPT}.${VARIANT}" ]; then
		SCRIPT="${SCRIPT}.${VARIANT}"
		SUPPORTED_VARIANTS="$VARIANT"
	fi
	if [ "$4" != "" ]; then
		SCRIPT="$4"
	fi
fi

###########################################################################

# TODO(pts): Better detect FreeBSD modules.
#	for module in linprocfs fdescfs tmpfs linsysfs; do
#		kldstat -m "$module" > /dev/null 2>&1 || warning SANITYCHECK "Probably required module %s is not loaded" "$module"
#	done

#### pts ####
debootstrap_chroot () {
  local CPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  if [ "$TARGET" = "/" ]; then
    PATH="$CPATH" "$@"
  else
    PATH="$CPATH" chroot "$TARGET" "$@"
  fi
}
CHROOT_CMD=debootstrap_chroot

if [ -z "$SHA_SIZE" ]; then
	SHA_SIZE=256
fi
DEBOOTSTRAP_CHECKSUM_FIELD="SHA$SHA_SIZE"

export ARCH SUITE TARGET CHROOT_CMD SHA_SIZE DEBOOTSTRAP_CHECKSUM_FIELD

if am_doing_phase first_stage second_stage; then
	if [ `id -u` -ne 0 ]; then
		error 1 NEEDROOT "debootstrap can only run as root"
	fi
	# Ensure that we can create working devices and executables on the target.
	if ! check_sane_mount "$TARGET"; then
		error 1 NOEXEC "Cannot install into target '$TARGET' mounted with noexec or nodev"
	fi
fi

###########################################################################

# Set $DEF0_MIRROR by trying various distributions.
if test "$USER_MIRROR"; then
  DEF0_MIRROR="$USER_MIRROR"
else
  DEF0_MIRROR=
  for TRY_MIRROR in \
      http://archive.debian.org/debian \
      http://archive.ubuntu.com/ubuntu \
      http://old-releases.ubuntu.com/ubuntu \
      http://ports.ubuntu.com/ubuntu-ports \
      http://archive.tanglu.org/tanglu \
  ; do
    GOT="$(wget -q -O - "$TRY_MIRROR/dists/$SUITE/main/binary-$ARCH/Release" 2>/dev/null | grep '^Architecture: ' ||:)"
    if [ "$GOT" ]; then
      DEF0_MIRROR="$TRY_MIRROR"
      break
    fi
  done
  unset TRY_MIRROR GOT
  #echo "SCRIPT=$SCRIPT" >&4
  #echo "DEF0_MIRROR=$DEF0_MIRROR" >&4
fi
info DEF0MIRROR "Using mirror: $DEF0_MIRROR"

if [ ! -e "$SCRIPT" ]; then
	if [ "${DEF0_MIRROR%/ubuntu*}" != "$DEF0_MIRROR" ]; then
		SCRIPT="${SCRIPT%/*}/gutsy"
	elif [ "${DEF0_MIRROR%/tanglu*}" != "$DEF0_MIRROR" ]; then
		SCRIPT="${SCRIPT%/*}/aequorea"
	elif [ "${DEF0_MIRROR%/debian*}" != "$DEF0_MIRROR" ]; then
		SCRIPT="${SCRIPT%/*}/sid"
	else
		warning UNKNOWNDIST "Unknown Linux distribution based on mirror URL: $DEF0_MIRROR"
	fi
fi
#echo "SCRIPT=$SCRIPT" >&4
#echo "DEF0_MIRROR=$DEF0_MIRROR" >&4
if [ ! -e "$SCRIPT" ]; then
	error 1 NOSCRIPT "No such script: %s" "$SCRIPT"
fi

###########################################################################

if [ "$TARGET" != "" ]; then
	mkdir -p "$TARGET/debootstrap"
fi

###########################################################################

# Use of fd's by functions/scripts:
#
#    stdin/stdout/stderr: used normally
#    fd 4: I:/W:/etc information
#    fd 5,6: spare for functions
#    fd 7,8: spare for scripts

if [ "$USE_DEBIANINSTALLER_INTERACTION" = yes ]; then
	#    stdout=stderr: full log of debootstrap run
	#    fd 3: I:/W:/etc information
	exec 4>&3
elif am_doing_phase printdebs; then
	#    stderr: I:/W:/etc information
	#    stdout: debs needed
	exec 4>&2
else
	#    stderr: used in exceptional circumstances only
	#    stdout: I:/W:/etc information
	#    $TARGET/debootstrap/debootstrap.log: full log of debootstrap run
	exec 4>&1
	exec >>"$TARGET/debootstrap/debootstrap.log"
	exec 2>&1
fi

###########################################################################

if [ "$UNPACK_TARBALL" ]; then
	if [ "${UNPACK_TARBALL#/}" = "$UNPACK_TARBALL" ]; then
		error 1 TARPATH "Tarball must be given a complete path"
	fi
	if [ "${UNPACK_TARBALL%.tar}" != "$UNPACK_TARBALL" ]; then
		(cd "$TARGET" && tar -xf "$UNPACK_TARBALL")
	elif [ "${UNPACK_TARBALL%.tgz}" != "$UNPACK_TARBALL" ]; then
		(cd "$TARGET" && zcat "$UNPACK_TARBALL" | tar -xf -)
	else
		error 1 NOTTAR "Unknown tarball: must be either .tar or .tgz"
	fi
fi

###########################################################################

. "$SCRIPT"
DEF_MIRROR="$DEF0_MIRROR"
DEF_HTTPS_MIRROR="https://${DEF0_MIRROR#*://}"
unset DEF0_MIRROR

if [ "$SECOND_STAGE_ONLY" = "true" ]; then
	MIRRORS=null:
else
	MIRRORS="$DEF_MIRROR"
	if [ "$USER_MIRROR" != "" ]; then
		MIRRORS="$USER_MIRROR"
		MIRRORS="${MIRRORS%/}"
	fi
fi

export MIRRORS

ok=false
for v in $SUPPORTED_VARIANTS; do
	if doing_variant $v; then ok=true; fi
done
if ! $ok; then
	error 1 UNSUPPVARIANT "unsupported variant"
fi

###########################################################################

if am_doing_phase finddebs; then
	if [ "$FINDDEBS_NEEDS_INDICES" = "true" ] || \
	   [ "$RESOLVE_DEPS" = "true" ]; then
		download_indices
		GOT_INDICES=true
	fi

	work_out_debs

	base=$(without "$base $ADDITIONAL" "$EXCLUDE")

	if [ "$RESOLVE_DEPS" = true ]; then
		requiredX=$(echo $(echo $required | tr ' ' '\n' | sort | uniq))
		baseX=$(echo $(echo $base | tr ' ' '\n' | sort | uniq))

		baseN=$(without "$baseX" "$requiredX")
		baseU=$(without "$baseX" "$baseN")

		if [ "$baseU" != "" ]; then
			info REDUNDANTBASE "Found packages in base already in required: %s" "$baseU"
		fi

		info RESOLVEREQ "Resolving dependencies of required packages..."
		required=$(resolve_deps $requiredX)
		info RESOLVEBASE "Resolving dependencies of base packages..."
		base=$(resolve_deps $baseX)
		base=$(without "$base" "$required")

		requiredX=$(without "$required" "$requiredX")
		baseX=$(without "$base" "$baseX")
		if [ "$requiredX" != "" ]; then
			info NEWREQUIRED "Found additional required dependencies: %s" "$requiredX"
		fi
		if [ "$baseX" != "" ]; then
			info NEWBASE "Found additional base dependencies: %s" "$baseX"
		fi
	fi

	all_debs="$required $base"
fi

if am_doing_phase printdebs; then
	echo "$all_debs"
fi

if am_doing_phase dldebs; then
	if [ "$GOT_INDICES" != "true" ]; then
		download_indices
	fi
	download $all_debs
fi

if am_doing_phase maketarball; then
	(cd $TARGET;
	 tar czf - var/lib/apt var/cache/apt) >$MAKE_TARBALL
fi

if am_doing_phase first_stage; then
	choose_extractor

	# first stage sets up the chroot -- no calls should be made to
	# "chroot $TARGET" here; but they should be possible by the time it's
	# finished
	first_stage_install

	if ! am_doing_phase second_stage; then
		cp "$0"				 "$TARGET/debootstrap/debootstrap"
		cp "$DEBOOTSTRAP_DIR/functions"	 "$TARGET/debootstrap/functions"
		cp $SCRIPT			 "$TARGET/debootstrap/suite-script"
		echo "$ARCH"			>"$TARGET/debootstrap/arch"
		echo "$SUITE"			>"$TARGET/debootstrap/suite"
		[ "" = "$VARIANT" ] ||
		echo "$VARIANT"			>"$TARGET/debootstrap/variant"
		echo "$required"		>"$TARGET/debootstrap/required"
		echo "$base"			>"$TARGET/debootstrap/base"

		chmod 755 "$TARGET/debootstrap/debootstrap"
	fi
fi

if am_doing_phase second_stage; then
	if [ "$SECOND_STAGE_ONLY" = true ]; then
		required="$(cat "$DEBOOTSTRAP_DIR/required")"
		base="$(cat "$DEBOOTSTRAP_DIR/base")"
		all_debs="$required $base"
	fi

	# second stage uses the chroot to clean itself up -- has to be able to
	# work from entirely within the chroot (in case we've booted into it,
	# possibly over NFS eg)

	second_stage_install

	# create sources.list
	# first, kill debootstrap.invalid sources.list
	if [ -e "$TARGET/etc/apt/sources.list" ]; then
		rm -f "$TARGET/etc/apt/sources.list"
	fi
	if [ "${MIRRORS#http://}" != "$MIRRORS" ]; then
		setup_apt_sources "${MIRRORS%% *}"
		mv_invalid_to "${MIRRORS%% *}"
	else
		setup_apt_sources "$DEF_MIRROR"
		mv_invalid_to "$DEF_MIRROR"
	fi

	if [ -e "$TARGET/debootstrap/debootstrap.log" ]; then
		if [ "$KEEP_DEBOOTSTRAP_DIR" = true ]; then
			cp "$TARGET/debootstrap/debootstrap.log" "$TARGET/var/log/bootstrap.log"
		else
			# debootstrap.log is still open as stdout/stderr and needs
			# to remain so, but after unlinking it some NFS servers
			# implement this by a temporary file in the same directory,
			# which makes it impossible to rmdir that directory.
			# Moving it instead works around the problem.
			mv "$TARGET/debootstrap/debootstrap.log" "$TARGET/var/log/bootstrap.log"
		fi
	fi
	sync

	if [ "$KEEP_DEBOOTSTRAP_DIR" = true ]; then
		if [ -x "$TARGET/debootstrap/debootstrap" ]; then
			chmod 644 "$TARGET/debootstrap/debootstrap"
		fi
	else
		rm -rf "$TARGET/debootstrap"
	fi
fi

if am_doing_phase kill_target; then
	if [ "$KEEP_DEBOOTSTRAP_DIR" != true ]; then
		info KILLTARGET "Deleting target directory"
		rm -rf "$TARGET"
	fi
fi

exit  # Make the shell script editable while running.
fi
