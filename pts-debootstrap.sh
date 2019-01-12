#!/bin/sh
#
# pts-debootstrap.sh: portable debootstrap for i386 and amd64
# by pts@fazekas.hu at Wed Jul 18 01:42:11 CEST 2018
#
# If you've checked out the entire repo, you can run this script directly:
#
#   $ sudo ./pts-debootstrap.sh slink slink_dir
#
# It also works without the .sh:
#
#   $ sudo ./pts-debootstrap    slink slink_dir
#
# However, you don't need to check out the repo to run this script:
#
#   $ rm -f pts-debootstrap
#   $ wget https://raw.githubusercontent.com/pts/pts-debootstrap/master/pts-debootstrap
#   $ chmod u+x pts-debootstrap
#   $ sudo ./pts-debootstrap    slink slink_dir
#
# In this case this script will be downloaded from GitHub by pts-deboostrap.
#
# This script is a shell script which can be run by bash, zsh, dash, pdksh,
# mksh and busybox sh. However, in the first big `if' it locates a busybox
# sh named pts-debootstrap, and (re)runs itself with that busybox sh. For
# external commands (e.g. cp, wget, chroot) it also uses the applets built in
# to the busybox named pts-debootstrap. For compiling pts-deboostrap, see
# compile_busybox.sh.
#
# TODO(pts): Omit the warning when configuring packages for slink.
# TODO(pts): When installing trusty to a trusty host, omit killing processes:
#            [30898.009903] init: upstart-udev-bridge main process (13467) terminated with status 1
#            [30898.010287] init: upstart-socket-bridge main process (13472) terminated with status 1
#            [30898.010625] init: upstart-file-bridge main process (13473) terminated with status 1
#

if true; then

VERSION='1.0.89-pts4'

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
# Some operations below change the current directory, so we make
# $PTS_DEBOOTSTRAP_BUSYBOX absolute.
test "${PTS_DEBOOTSTRAP_BUSYBOX#/}" = "$PTS_DEBOOTSTRAP_BUSYBOX" &&
	PTS_DEBOOTSTRAP_BUSYBOX="$PWD/$PTS_DEBOOTSTRAP_BUSYBOX"
export PTS_DEBOOTSTRAP_BUSYBOX
unset OLD_PATH
OLD_PATH="$PATH"
export PATH=/dev/null/missing  # Don't look for commands in /usr/bin etc.
unset DEBOOTSTRAP_DIR LANG LANGUAGE LC_CTYPE LC_ALL LD_PRELOAD LD_LIBRARY_PATH
DEBOOTSTRAP_DIR="${PTS_DEBOOTSTRAP_BUSYBOX%/*}"
export LC_ALL=C

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

########################################################################### functions

############################################################### smallutils

smallyes() {
	YES="${1-y}"
	while echo "$YES" 2>/dev/null ; do : ; done
}

in_path () {
	# Works for busybox sh, not bash.
	test "$(type "$1")" = "$1 is a shell function" && return 0
	local OLD_IFS="$IFS"
	IFS=":"
	for dir in $PATH; do
		if [ -e "$dir/$1" ]; then
			IFS="$OLD_IFS"
			return 0
		fi
	done
	IFS="$OLD_IFS"
	return 1
}

############################################################### interaction

error () {
	# <error code> <name> <string> <args>
	local err="$1"
	local name="$2"
	local fmt="$3"
	shift; shift; shift
	if [ "$USE_DEBIANINSTALLER_INTERACTION" ]; then
		(echo "E: $name"
		for x in "$@"; do echo "EA: $x"; done
		echo "EF: $fmt") >&4
	else
		(printf "E: $fmt\n" "$@") >&4
	fi
	exit $err
}

warning () {
	# <name> <string> <args>
	local name="$1"
	local fmt="$2"
	shift; shift
	if [ "$USE_DEBIANINSTALLER_INTERACTION" ]; then
		(echo "W: $name"
		for x in "$@"; do echo "WA: $x"; done
		echo "WF: $fmt") >&4
	else
		printf "W: $fmt\n" "$@" >&4
	fi
}

info () {
	# <name> <string> <args>
	local name="$1"
	local fmt="$2"
	shift; shift
	if [ "$USE_DEBIANINSTALLER_INTERACTION" ]; then
		(echo "I: $name"
		for x in "$@"; do echo "IA: $x"; done
		echo "IF: $fmt") >&4
	else
		printf "I: $fmt\n" "$@" >&4
	fi
}

PROGRESS_NOW=0
PROGRESS_END=0
PROGRESS_NEXT=""
PROGRESS_WHAT=""

progress_next () {
	PROGRESS_NEXT="$1"
}

wgetprogress () {
	[ ! "$VERBOSE" ] && QSWITCH="-q"
	local ret=0
	if [ "$USE_DEBIANINSTALLER_INTERACTION" ] && [ "$PROGRESS_NEXT" ]; then
		wget "$@" 2>&1 >/dev/null | pkgdetails "WGET%" $PROGRESS_NOW $PROGRESS_NEXT $PROGRESS_END >&3
		ret=$?
	else
		wget $QSWITCH "$@" 
		ret=$?
	fi
	return $ret
}

progress () {
	# <now> <end> <name> <string> <args>
	local now="$1"
	local end="$2"
	local name="$3"
	local fmt="$4"
	shift; shift; shift; shift
	if [ "$USE_DEBIANINSTALLER_INTERACTION" ]; then
		PROGRESS_NOW="$now"
		PROGRESS_END="$end"
		PROGRESS_NEXT=""
		(echo "P: $now $end $name"
		for x in "$@"; do echo "PA: $x"; done
		echo "PF: $fmt") >&3
	fi
}

dpkg_progress () {
	# <now> <end> <name> <desc> UNPACKING|CONFIGURING
	local now="$1"
	local end="$2"
	local name="$3"
	local desc="$4"
	local action="$5"
	local expect=

	if [ "$action" = UNPACKING ]; then
		expect=half-installed
	elif [ "$action" = CONFIGURING ]; then
		expect=half-configured
	fi

	dp () {
		now="$(($now + ${1:-1}))"
	}

	exitcode=0
	while read status pkg qstate; do
		if [ "$status" = "EXITCODE" ]; then
			exitcode="$pkg"
			continue
		fi
		[ "$qstate" = "$expect" ] || continue
		case $qstate in
		    half-installed)
			dp; progress "$now" "$end" "$name" "$desc"
			info "$action" "Unpacking %s..." "${pkg%:}"
			expect=unpacked
			;;
		    unpacked)
			expect=half-installed
			;;
		    half-configured)
			dp; progress "$now" "$end" "$name" "$desc"
			info "$action" "Configuring %s..." "${pkg%:}"
			expect=installed
			;;
		    installed)
			expect=half-configured
			;;
		esac
	done
	return $exitcode
}

############################################################# set variables

default_mirror () {
	DEF_MIRROR="$1"
}

FINDDEBS_NEEDS_INDICES=false
finddebs_style () {
	case "$1" in
	    hardcoded)
		;;
	    from-indices)
		FINDDEBS_NEEDS_INDICES=true
		;;
	    *)
		error 1 BADFINDDEBS "unknown finddebs style"
		;;
	 esac
}

mk_download_dirs () {
	if [ $DLDEST = "apt_dest" ]; then
		mkdir -p "$TARGET/$APTSTATE/lists/partial"
		mkdir -p "$TARGET/var/cache/apt/archives/partial"
	fi
}

download_style () {
	case "$1" in
	    apt)
		if [ "$2" = "var-state" ]; then
			APTSTATE=var/state/apt
		else
			APTSTATE=var/lib/apt
		fi
		DLDEST=apt_dest
		export APTSTATE DLDEST DEBFOR
		;;
	    *)
		error 1 BADDLOAD "unknown download style"
		;;
	esac
}

keyring () {
	if [ -z "$KEYRING" ]; then
		if [ -e "$1" ]; then
			KEYRING="$1"
		elif [ -z "$DISABLE_KEYRING" ]; then
			if [ -n "$DEF_HTTPS_MIRROR" ] && [ -z "$USER_MIRROR" ] && [ -z "$FORCE_KEYRING" ]; then
				info KEYRING "Keyring file not available at %s; switching to https mirror %s" "$1" "$DEF_HTTPS_MIRROR"
				USER_MIRROR="$DEF_HTTPS_MIRROR"
			else
				warning KEYRING "Cannot check Release signature; keyring file not available %s" "$1"
				if [ -n "$FORCE_KEYRING" ]; then
					error 1 KEYRING "Keyring-based check was requested; aborting accordingly"
				fi
			fi
		fi
	fi
}

########################################################## variant handling

doing_variant () {
	if [ "$1" = "$VARIANT" ]; then return 0; fi
	if [ "$1" = "-" ] && [ "$VARIANT" = "" ]; then return 0; fi
	return 1
}

SUPPORTED_VARIANTS="-"
variants () {
	SUPPORTED_VARIANTS="$*"
	for v in $*; do
		if doing_variant "$v"; then return 0; fi
	done
	error 1 UNSUPPVARIANT "unsupported variant"
}

################################################# work out names for things

mirror_style () {
	case "$1" in
	    release)
		DOWNLOAD_INDICES=download_release_indices
		DOWNLOAD_DEBS=download_release
		;;
	    main)
		DOWNLOAD_INDICES=download_main_indices
		DOWNLOAD_DEBS=download_main
		;;
	    *)
		error 1 BADMIRROR "unknown mirror style"
		;;
	esac
	export DOWNLOAD_INDICES
	export DOWNLOAD_DEBS
}

force_md5 () {
	DEBOOTSTRAP_CHECKSUM_FIELD=MD5SUM
	export DEBOOTSTRAP_CHECKSUM_FIELD
}

verify_checksum () {
	# args: dest checksum size
	local expchecksum="$2"
	local expsize="$3"
	if [ "$DEBOOTSTRAP_CHECKSUM_FIELD" = "MD5SUM" ]; then
		relchecksum=`md5sum < "$1" | sed 's/ .*$//'`
	else
		relchecksum=`sha${SHA_SIZE}sum < "$1" | sed 's/ .*$//'`
	fi
	relsize=`wc -c < "$1"`
	if [ "$expsize" -ne "$relsize" ] || [ "$expchecksum" != "$relchecksum" ]; then
		return 1
	fi
	return 0
}

get () {
	# args: from dest 'nocache'
	# args: from dest [checksum size] [alt {checksum size type}]
	local displayname
	local versionname
	if [ "${2%.deb}" != "$2" ]; then
		displayname="$(echo "$2" | sed 's,^.*/,,;s,_.*$,,')"
		versionname="$(echo "$2" | sed 's,^.*/,,' | cut -d_ -f2 | sed 's/%3a/:/')"
	else
		displayname="$(echo "$1" | sed 's,^.*/,,')"
	fi

	if [ -e "$2" ]; then
		if [ -z "$3" ]; then
			return 0
		elif [ "$3" = nocache ]; then
			rm -f "$2"
		else
			info VALIDATING "Validating %s %s" "$displayname" "$versionname"
			if verify_checksum "$2" "$3" "$4"; then
				return 0
			else
				rm -f "$2"
			fi
		fi
	fi
	# Drop 'nocache' option
	if [ "$3" = nocache ]; then
		set "$1" "$2"
	fi

	if [ "$#" -gt 5 ]; then
		local st=3
		if [ "$5" = "-" ]; then st=6; fi
		local order="$(a=$st; while [ "$a" -le $# ]; do eval echo \"\${$(($a+1))}\" $a;
		a=$(($a + 3)); done | sort -n | sed 's/.* //')"
	else
		local order=3
	fi
	for a in $order; do
		local checksum="$(eval echo \${$a})"
		local siz="$(eval echo \${$(( $a+1 ))})"
		local typ="$(eval echo \${$(( $a+2 ))})"
		local from
		local dest
		local iters=0

		case "$typ" in
		    xz)  from="$1.xz"; dest="$2.xz" ;;
		    bz2) from="$1.bz2"; dest="$2.bz2" ;;
		    gz)  from="$1.gz"; dest="$2.gz" ;;
		    *)   from="$1"; dest="$2" ;;
		esac

		if [ "${dest#/}" = "$dest" ]; then
			dest="./$dest"
		fi
		local dest2="$dest"
		if [ -d "${dest2%/*}/partial" ]; then
			dest2="${dest2%/*}/partial/${dest2##*/}"
		fi

		while [ "$iters" -lt 10 ]; do
			info RETRIEVING "Retrieving %s %s" "$displayname" "$versionname"
			if ! just_get "$from" "$dest2"; then continue 2; fi
			if [ "$checksum" != "" ]; then
				info VALIDATING "Validating %s %s" "$displayname" "$versionname"
				if verify_checksum "$dest2" "$checksum" "$siz"; then
					checksum=""
				fi
			fi
			if [ -z "$checksum" ]; then
				[ "$dest2" = "$dest" ] || mv "$dest2" "$dest"
				case "$typ" in
				    gz)  gunzip "$dest" ;;
				    bz2) bunzip2 "$dest" ;;
				    xz)  unxz "$dest" ;;
				esac
				return 0
			else
				rm -f "$dest2"
				warning RETRYING "Retrying failed download of %s" "$from"
				iters="$(($iters + 1))"
			fi
		done
		warning CORRUPTFILE "%s was corrupt" "$from"
	done
	return 1
}

just_get () {
	# args: from dest
	local from="$1"
	local dest="$2"
	mkdir -p "${dest%/*}"
	if [ "${from#null:}" != "$from" ]; then
		error 1 NOTPREDL "%s was not pre-downloaded" "${from#null:}"
	elif [ "${from#http://}" != "$from" ] || [ "${from#ftp://}" != "$from" ]; then
		# http/ftp mirror
		if wgetprogress -O "$dest" "$from"; then
			return 0
		else
			rm -f "$dest"
			return 1
		fi
	elif [ "${from#https://}" != "$from" ] ; then
		# http/ftp mirror
		if wgetprogress $CHECKCERTIF $CERTIFICATE $PRIVATEKEY -O "$dest" "$from"; then
			return 0
		else
			rm -f "$dest"
			return 1
		fi
	elif [ "${from#file:}" != "$from" ]; then
		local base="${from#file:}"
		if [ "${base#//}" != "$base" ]; then
			base="/${from#file://*/}"
		fi
		if [ -e "$base" ]; then
			cp "$base" "$dest"
			return 0
		else
			return 1
		fi
	elif [ "${from#ssh:}" != "$from" ]; then
		local ssh_dest="$(echo $from | sed -e 's#ssh://##' -e 's#/#:/#')"
		if [ -n "$ssh_dest" ]; then
			scp "$ssh_dest" "$dest"
			return 0
		else
			return 1
		fi
	else
		error 1 UNKNOWNLOC "unknown location %s" "$from"
	fi
}

download () {
	mk_download_dirs
	"$DOWNLOAD_DEBS" $(echo "$@" | tr ' ' '\n' | sort)
}

download_indices () {
	mk_download_dirs
	"$DOWNLOAD_INDICES" $(echo "$@" | tr ' ' '\n' | sort)
}

debfor () {
	(while read pkg path; do
		for p in "$@"; do
			[ "$p" = "$pkg" ] || continue;
			echo "$path"
		done
	 done <"$TARGET/debootstrap/debpaths"
	)
}

apt_dest () {
	# args:
	#   deb package version arch mirror path
	#   pkg suite component arch mirror path
	#   rel suite mirror path
	case "$1" in
	    deb)
		echo "/var/cache/apt/archives/${2}_${3}_${4}.deb" | sed 's/:/%3a/'
		;;
	    pkg)
		local m="$5"
		m="debootstrap.invalid"
		#if [ "${m#http://}" != "$m" ]; then
		#	m="${m#http://}"
		#elif [ "${m#file://}" != "$m" ]; then
		#	m="file_localhost_${m#file://*/}"
		#elif [ "${m#file:/}" != "$m" ]; then
		#	m="file_localhost_${m#file:/}"
		#fi

		printf "%s" "$APTSTATE/lists/"
		echo "${m}_$6" | sed 's/\//_/g'
		;;
	    rel)
		local m="$3"
		m="debootstrap.invalid"
		#if [ "${m#http://}" != "$m" ]; then
		#	m="${m#http://}"
		#elif [ "${m#file://}" != "$m" ]; then
		#	m="file_localhost_${m#file://*/}"
		#elif [ "${m#file:/}" != "$m" ]; then
		#	m="file_localhost_${m#file:/}"
		#fi
		printf "%s" "$APTSTATE/lists/"
		echo "${m}_$4" | sed 's/\//_/g'
		;;
	esac
}

################################################################## download

get_release_checksum () {
	local reldest="$1"
	local path="$2"
	if [ "$DEBOOTSTRAP_CHECKSUM_FIELD" = MD5SUM ]; then
		local match="^[Mm][Dd]5[Ss][Uu][Mm]"
	else
		local match="^[Ss][Hh][Aa]$SHA_SIZE:"
	fi
	sed -n "/$match/,/^[^ ]/p" < "$reldest" | \
		while read a b c; do
			if [ "$c" = "$path" ]; then echo "$a $b"; fi
		done | head -n 1
}

extract_release_components () {
	local reldest="$1"; shift
	TMPCOMPONENTS="$(sed -n 's/Components: *//p' "$reldest")"
	for c in $TMPCOMPONENTS ; do
		eval "
		case \"\$c\" in
		    $USE_COMPONENTS)
			COMPONENTS=\"\$COMPONENTS \$c\"
			;;
		esac
		"
	done
	COMPONENTS="$(echo $COMPONENTS)"
	if [ -z "$COMPONENTS" ]; then
		mv "$reldest" "$reldest.malformed"
		error 1 INVALIDREL "Invalid Release file, no valid components"
	fi
}

CODENAME=""
validate_suite () {
	local reldest="$1"

	CODENAME=$(sed -n "s/^Codename: *//p" "$reldest")
	local suite=$(sed -n "s/^Suite: *//p" "$reldest")

	if [ "$SUITE" != "$suite" ] && [ "$SUITE" != "$CODENAME" ]; then
		error 1 WRONGSUITE "Asked to install suite %s, but got %s (codename: %s) from mirror" "$SUITE" "$suite" "$CODENAME"
	fi
}

split_inline_sig () {
	local inreldest="$1"
	local reldest="$2"
	local relsigdest="$3"

	# Note: InRelease files are fun since one needs to remove the
	# last newline from the PGP SIGNED MESSAGE part, while keeping
	# the PGP SIGNATURE part intact. This shell implementation
	# should work on most if not all systems, instead of trying to
	# sed/tr/head, etc.
	rm -f "$reldest" "$relsigdest"
	nl=""
	state=pre-begin
	while IFS= read -r line; do
		case "${state}" in
		    pre-begin)
			if [ "x${line}" = "x-----BEGIN PGP SIGNED MESSAGE-----" ]; then
				state=begin
			fi
			;;
		    begin)
			if [ "x${line}" = "x" ]; then
				state=data
			fi
			;;
		    data)
			if [ "x${line}" = "x-----BEGIN PGP SIGNATURE-----" ]; then
				printf "%s\n" "${line}" > "$relsigdest"
				state=signature
			else
				printf "${nl}%s" "${line}" >> "$reldest"
				nl="\n"
			fi
			;;
		    signature)
			printf "%s\n" "${line}" >> "$relsigdest"
			if [ "x${line}" = "x-----END PGP SIGNATURE-----" ]; then
				break
			fi
		esac
	done < "$inreldest"
}

download_release_sig () {
	local m1="$1"
	local inreldest="$2"
	local reldest="$3"
	local relsigdest="$4"

	progress 0 100 DOWNREL "Downloading Release file"
	progress_next 100
	if get "$m1/dists/$SUITE/InRelease" "$inreldest" nocache; then
		split_inline_sig "$inreldest" "$reldest" "$relsigdest"
		progress 100 100 DOWNREL "Downloading Release file"
	else
		get "$m1/dists/$SUITE/Release" "$reldest" nocache ||
			error 1 NOGETREL "Failed getting release file %s" "$m1/dists/$SUITE/Release"
		progress 100 100 DOWNREL "Downloading Release file"
	fi
	if [ -n "$KEYRING" ] && [ -z "$DISABLE_KEYRING" ]; then
		progress 0 100 DOWNRELSIG "Downloading Release file signature"
		if ! [ -f "$relsigdest" ]; then
			progress_next 50
			get "$m1/dists/$SUITE/Release.gpg" "$relsigdest" nocache ||
				error 1 NOGETRELSIG "Failed getting release signature file %s" \
				"$m1/dists/$SUITE/Release.gpg"
			progress 50 100 DOWNRELSIG "Downloading Release file signature"
		fi

		info RELEASESIG "Checking Release signature"
		# Don't worry about the exit status from gpgv; parsing the output will
		# take care of that.
		(gpgv --status-fd 1 --keyring "$KEYRING" --ignore-time-conflict \
		 "$relsigdest" "$reldest" || true) | read_gpg_status
		progress 100 100 DOWNRELSIG "Downloading Release file signature"
	fi
}

download_release_indices () {
	local m1="${MIRRORS%% *}"
	local inreldest="$TARGET/$($DLDEST rel "$SUITE" "$m1" "dists/$SUITE/InRelease")"
	local reldest="$TARGET/$($DLDEST rel "$SUITE" "$m1" "dists/$SUITE/Release")"
	local relsigdest="$TARGET/$($DLDEST rel "$SUITE" "$m1" "dists/$SUITE/Release.gpg")"

	download_release_sig "$m1" "$inreldest" "$reldest" "$relsigdest"

	validate_suite "$reldest"

	extract_release_components $reldest

	local totalpkgs=0
	for c in $COMPONENTS; do
		local subpath="$c/binary-$ARCH/Packages"
		local xzi="`get_release_checksum "$reldest" "$subpath.xz"`"
		local bz2i="`get_release_checksum "$reldest" "$subpath.bz2"`"
		local gzi="`get_release_checksum "$reldest" "$subpath.gz"`"
		local normi="`get_release_checksum "$reldest" "$subpath"`"
		local i=
		if [ "$normi" != "" ]; then
			i="$normi"
		elif [ "$bz2i" != "" ]; then
			i="$bz2i"
		elif [ "$xzi" != "" ]; then
			i="$xzi"
		elif [ "$gzi" != "" ]; then
			i="$gzi"
		fi
		if [ "$i" != "" ]; then
			totalpkgs="$(( $totalpkgs + ${i#* } ))"
		else
			mv "$reldest" "$reldest.malformed"
			error 1 MISSINGRELENTRY "Invalid Release file, no entry for %s" "$subpath"
		fi
	done

	local donepkgs=0
	local pkgdest
	progress 0 $totalpkgs DOWNPKGS "Downloading Packages files"
	for c in $COMPONENTS; do
		local subpath="$c/binary-$ARCH/Packages"
		local path="dists/$SUITE/$subpath"
		local xzi="`get_release_checksum "$reldest" "$subpath.xz"`"
		local bz2i="`get_release_checksum "$reldest" "$subpath.bz2"`"
		local gzi="`get_release_checksum "$reldest" "$subpath.gz"`"
		local normi="`get_release_checksum "$reldest" "$subpath"`"
		local ext=
		local i=
		if [ "$normi" != "" ]; then
			ext="$ext $normi ."
			i="$normi"
		fi
		if [ "$xzi" != "" ]; then
			ext="$ext $xzi xz"
			i="${i:-$xzi}"
		fi
		if [ "$bz2i" != "" ]; then
			ext="$ext $bz2i bz2"
			i="${i:-$bz2i}"
		fi
		if [ "$gzi" != "" ]; then
			ext="$ext $gzi gz"
			i="${i:-$gzi}"
		fi
		progress_next "$(($donepkgs + ${i#* }))"
		for m in $MIRRORS; do
			pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m" "$path")"
			if get "$m/$path" "$pkgdest" $ext; then break; fi
		done
		if [ ! -f "$pkgdest" ]; then
			error 1 COULDNTDL "Couldn't download %s" "$path"
		fi
		donepkgs="$(($donepkgs + ${i#* }))"
		progress $donepkgs $totalpkgs DOWNPKGS "Downloading Packages files"
	done
}

get_package_sizes () {
	# mirror pkgdest debs..
	local m="$1"; shift
	local pkgdest="$1"; shift
	pkgdetails PKGS "$m" "$pkgdest" "$@" | (
		newleft=""
		totaldebs=0
		countdebs=0
		while read p details; do
			if [ "$details" = "-" ]; then
				newleft="$newleft $p"
			else
				size="${details##* }";
				totaldebs="$(($totaldebs + $size))"
				countdebs="$(($countdebs + 1))"
			fi
		done
		echo "$countdebs $totaldebs$newleft"
	)
}

# note, leftovers come back on fd5 !!
download_debs () {
	local m="$1"
	local pkgdest="$2"
	shift; shift

	pkgdetails PKGS "$m" "$pkgdest" "$@" | (
		leftover=""
		while read p ver arc mdup fil checksum size; do
			if [ "$ver" = "-" ]; then
				leftover="$leftover $p"
			else
				progress_next "$(($dloaddebs + $size))"
				local debdest="$($DLDEST deb "$p" "$ver" "$arc" "$m" "$fil")"
				if get "$m/$fil" "$TARGET/$debdest" "$checksum" "$size"; then
					dloaddebs="$(($dloaddebs + $size))"
					echo >>$TARGET/debootstrap/deburis "$p $ver $m/$fil"
					echo >>$TARGET/debootstrap/debpaths "$p $debdest"
				else
					warning COULDNTDL "Couldn't download package %s (ver %s arch %s)" "$p" "$ver" "$arc"
					leftover="$leftover $p"
				fi
			fi
		done
		echo >&5 ${leftover# }
	)
}

download_release () {
	local m1="${MIRRORS%% *}"

	local numdebs="$#"

	local countdebs=0
	progress $countdebs $numdebs SIZEDEBS "Finding package sizes"

	local totaldebs=0
	local leftoverdebs="$*"

	# Fix possible duplicate package names, which would screw up counts:
	leftoverdebs=$(printf "$leftoverdebs"|tr ' ' '\n'|sort -u|tr '\n' ' ')
	numdebs=$(printf "$leftoverdebs"|wc -w)

	for c in $COMPONENTS; do
		if [ "$countdebs" -ge "$numdebs" ]; then break; fi

		local path="dists/$SUITE/$c/binary-$ARCH/Packages"
		local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m1" "$path")"
		if [ ! -e "$pkgdest" ]; then continue; fi

		info CHECKINGSIZES "Checking component %s on %s..." "$c" "$m1"

		leftoverdebs="$(get_package_sizes "$m1" "$pkgdest" $leftoverdebs)"

		countdebs=$(($countdebs + ${leftoverdebs%% *}))
		leftoverdebs=${leftoverdebs#* }

		totaldebs=${leftoverdebs%% *}
		leftoverdebs=${leftoverdebs#* }

		progress $countdebs $numdebs SIZEDEBS "Finding package sizes"
	done

	if [ "$countdebs" -ne "$numdebs" ]; then
		error 1 LEFTOVERDEBS "Couldn't find these debs: %s" "$leftoverdebs"
	fi

	local dloaddebs=0

	progress $dloaddebs $totaldebs DOWNDEBS "Downloading packages"
	:>$TARGET/debootstrap/debpaths

	pkgs_to_get="$*"
	for c in $COMPONENTS; do
	    local path="dists/$SUITE/$c/binary-$ARCH/Packages"
	    for m in $MIRRORS; do
		local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m" "$path")"
		if [ ! -e "$pkgdest" ]; then continue; fi
		pkgs_to_get="$(download_debs "$m" "$pkgdest" $pkgs_to_get 5>&1 1>&6)"
		if [ -z "$pkgs_to_get" ]; then break; fi
	    done 6>&1
	    if [ -z "$pkgs_to_get" ]; then break; fi
	done
	progress $dloaddebs $totaldebs DOWNDEBS "Downloading packages"
	if [ "$pkgs_to_get" != "" ]; then
		error 1 COULDNTDLPKGS "Couldn't download packages: %s" "$pkgs_to_get"
	fi
}

download_main_indices () {
	local m1="${MIRRORS%% *}"
	local comp="${USE_COMPONENTS}"
	progress 0 100 DOWNMAINPKGS "Downloading Packages file"
	progress_next 100

	if [ -z "$comp" ]; then comp=main; fi
	COMPONENTS="$(echo $comp | tr '|' ' ')"

	export COMPONENTS
	for m in $MIRRORS; do
	    for c in $COMPONENTS; do
		local path="dists/$SUITE/$c/binary-$ARCH/Packages"
		local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m" "$path")"
		if get "$m/${path}.gz" "${pkgdest}.gz"; then
			rm -f "$pkgdest"
			gunzip "$pkgdest.gz"
		elif get "$m/$path" "$pkgdest"; then
			true
		fi
	    done
	done
	progress 100 100 DOWNMAINPKGS "Downloading Packages file"
}

download_main () {
	local m1="${MIRRORS%% *}"

	:>$TARGET/debootstrap/debpaths
	for p in "$@"; do
	    for c in $COMPONENTS; do
		local details=""
		for m in $MIRRORS; do
			local path="dists/$SUITE/$c/binary-$ARCH/Packages"
			local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m" "$path")"
			if [ ! -e "$pkgdest" ]; then continue; fi
			details="$(pkgdetails PKGS "$m" "$pkgdest" "$p")"
			if [ "$details" = "$p -" ]; then
				details=""
				continue
			fi
			size="${details##* }"; details="${details% *}"
			checksum="${details##* }"; details="${details% *}"
			local debdest="$($DLDEST deb $details)"
			if get "$m/${details##* }" "$TARGET/$debdest" "$checksum" "$size"; then
				echo >>$TARGET/debootstrap/debpaths "$p $debdest"
				details="done"
				break
			fi
		done
		if [ "$details" != "" ]; then
			break
		fi
	    done
	    if [ "$details" != "done" ]; then
		error 1 COULDNTDL "Couldn't download %s" "$p"
	    fi
	done
}

###################################################### deb choosing support

get_debs () {
	local field="$1"
	shift
	local m1 c
	for m1 in $MIRRORS; do
		for c in $COMPONENTS; do
			local path="dists/$SUITE/$c/binary-$ARCH/Packages"
			local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m1" "$path")"
			echo $(pkgdetails FIELD "$field" "$m1" "$pkgdest" "$@" | sed 's/ .*//')
		done
	done
}

################################################################ extraction

# Raw .deb extractors
extract_deb_field () {
	local pkg="$1"
	local field="$2"
	local tarball=$(ar -t "$pkg" | grep "^control\.tar")

	case "$tarball" in
		control.tar.gz) cat_cmd=zcat ;;
		control.tar.xz) cat_cmd=xzcat ;;
		control.tar) cat_cmd=cat ;;
		*) error 1 UNKNOWNCONTROLCOMP "Unknown compression type for %s in %s" "$tarball" "$pkg" ;;
	esac

	if type $cat_cmd >/dev/null 2>&1; then
		ar -p "$pkg" "$tarball" | $cat_cmd |
		    tar -O -xf - control ./control 2>/dev/null |
		    grep -i "^$field:" | sed -e 's/[^:]*: *//' | head -n 1
	else
		error 1 UNPACKCMDUNVL "Extracting %s requires the %s command, which is not available" "$pkg" "$cat_cmd"
	fi
}

extract_deb_data () {
	local pkg="$1"
	local tarball=$(ar -t "$pkg" | grep "^data.tar")

	case "$tarball" in
		data.tar.gz) cat_cmd=zcat ;;
		data.tar.bz2) cat_cmd=bzcat ;;
		data.tar.xz) cat_cmd=xzcat ;;
		data.tar) cat_cmd=cat ;;
		*) error 1 UNKNOWNDATACOMP "Unknown compression type for %s in %s" "$tarball" "$pkg" ;;
	esac

	if type $cat_cmd >/dev/null 2>&1; then
		# Ignoring errors in tar because mawk_1.3.3-2_i386.deb in
		# Debian slink causes a short read, which busybox tar fails on.
		ar -p "$pkg" "$tarball" | $cat_cmd | tar -xf - ||:
	else
		error 1 UNPACKCMDUNVL "Extracting %s requires the %s command, which is not available" "$pkg" "$cat_cmd"
	fi
}

valid_extractor () { :; }

choose_extractor () { :; }

extract () { (
	cd "$TARGET"
	local p=0 cat_cmd
	for pkg in $(debfor "$@"); do
		p="$(($p + 1))"
		progress "$p" "$#" EXTRACTPKGS "Extracting packages"
		packagename="$(echo "$pkg" | sed 's,^.*/,,;s,_.*$,,')"
		info EXTRACTING "Extracting %s..." "$packagename"
		extract_deb_data "./$pkg"
	done
); }

in_target_nofail () {
	if ! $CHROOT_CMD "$@" 2>/dev/null; then
		true
	fi
	return 0
}

in_target_failmsg () {
	local code="$1"
	local msg="$2"
	local arg="$3"
	shift; shift; shift
	if ! $CHROOT_CMD "$@"; then
		warning "$code" "$msg" "$arg"
		# Try to point user at actual failing package.
		msg="See %s for details"
		if [ -e "$TARGET/debootstrap/debootstrap.log" ]; then
			arg="$TARGET/debootstrap/debootstrap.log"
			local pkg="$(grep '^dpkg: error processing ' "$TARGET/debootstrap/debootstrap.log" | head -n 1 | sed 's/\(error processing \)\(package \|archive \)/\1/' | cut -d ' ' -f 4)"
			if [ -n "$pkg" ]; then
				msg="$msg (possibly the package $pkg is at fault)"
			fi
		else
			arg="the log"
		fi
		warning "$code" "$msg" "$arg"
		return 1
	fi
	return 0
}

in_target () {
	in_target_failmsg IN_TARGET_FAIL "Failure trying to run: %s" "$CHROOT_CMD $*" "$@"
}

###################################################### standard setup stuff

conditional_cp () {
	if [ ! -e "$2/$1" ]; then
		if [ -L "$1" ] && [ -e "$1" ]; then
			cat "$1" >"$2/$1"
		elif [ -e "$1" ]; then
			cp -a "$1" "$2/$1"
		fi
	fi
}

mv_invalid_to () {
	local m="$1"
	m="$(echo "${m#http://}" | tr '/' '_' | sed 's/_*//')"
	(cd "$TARGET/$APTSTATE/lists"
	 for a in debootstrap.invalid_*; do
		 mv "$a" "${m}_${a#*_}"
	 done
	)
}

setup_apt_sources () {
	mkdir -p "$TARGET/etc/apt"
	for m in "$@"; do
		local cs=""
		for c in ${COMPONENTS:-$USE_COMPONENTS}; do
			local path="dists/$SUITE/$c/binary-$ARCH/Packages"
			local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m" "$path")"
			if [ -e "$pkgdest" ]; then cs="$cs $c"; fi
		done
		if [ "$cs" != "" ]; then echo "deb $m $SUITE$cs"; fi
	done > "$TARGET/etc/apt/sources.list"
}

setup_etc () {
	mkdir -p "$TARGET/etc"

	conditional_cp /etc/resolv.conf "$TARGET"
	conditional_cp /etc/hostname "$TARGET"

	if [ "$DLDEST" = apt_dest ] && [ ! -e "$TARGET/etc/apt/sources.list" ]; then
		setup_apt_sources "http://debootstrap.invalid/"
	fi
}

UMOUNT_DIRS=

umount_exit_function () {
	local realdir
	for dir in $UMOUNT_DIRS; do
		realdir="$(in_target_nofail readlink -f "$dir")"
		[ -z "$realdir" ] && [ -d "$TARGET/$dir" ] && realdir="$dir"
		[ "$realdir" ] || continue
		( cd / ; umount "$TARGET/${realdir#/}" ) || true
	done
}

umount_on_exit () {
	if [ "$UMOUNT_DIRS" ]; then
		UMOUNT_DIRS="$UMOUNT_DIRS $1"
	else
		UMOUNT_DIRS="$1"
		on_exit umount_exit_function
	fi
}

clear_mtab () {
	if [ -f "$TARGET/etc/mtab" ] && [ ! -h "$TARGET/etc/mtab" ]; then
		rm -f "$TARGET/etc/mtab"
	fi
}

setup_proc () {
	case "$HOST_OS" in
	    *freebsd*)
		umount_on_exit /dev
		umount_on_exit /proc
		umount "$TARGET/proc" 2>/dev/null || true
		if [ "$HOST_OS" = kfreebsd ]; then
			in_target mount -t linprocfs proc /proc
		else
			mount -t linprocfs proc $TARGET/proc
		fi
		;;
	    hurd*)
		# firmlink $TARGET/{dev,servers,proc} to the system ones.
		settrans -a "$TARGET/dev" /hurd/firmlink /dev
		settrans -a "$TARGET/servers" /hurd/firmlink /servers
	        settrans -a "$TARGET/proc" /hurd/firmlink /proc
		;;
	    *)
		umount_on_exit /dev/pts
		umount_on_exit /dev/shm
		umount_on_exit /proc/bus/usb
		umount_on_exit /proc
		umount "$TARGET/proc" 2>/dev/null || true
		in_target mount -t proc proc /proc
		if [ -d "$TARGET/sys" ] && \
		   grep -q '[[:space:]]sysfs' /proc/filesystems 2>/dev/null; then
			umount_on_exit /sys
			umount "$TARGET/sys" 2>/dev/null || true
			in_target mount -t sysfs sysfs /sys
		fi
		on_exit clear_mtab
		;;
	esac
	umount_on_exit /lib/init/rw
}

setup_proc_fakechroot () {
	rm -rf "$TARGET/proc"
	ln -s /proc "$TARGET"
}

# create the static device nodes
setup_devices () {
	if doing_variant fakechroot; then
		setup_devices_fakechroot
		return 0
	fi

	case "$HOST_OS" in
	    kfreebsd*)
		;;
	    freebsd)
		;;
	    hurd*)
		;;
	    *)
		setup_devices_simple
		;;
	esac
}

# enable the dynamic device nodes
setup_dynamic_devices () {
	if doing_variant fakechroot; then
		return 0
	fi

	case "$HOST_OS" in
	    kfreebsd*)
		in_target mount -t devfs devfs /dev ;;
	    freebsd)
		mount -t devfs devfs $TARGET/dev ;;
	    hurd*)
	        # Use the setup-translators of the hurd package
	        in_target /usr/lib/hurd/setup-translators -k ;;
	esac
}

setup_devices_simple () {
	# The list of devices that can be created in a container comes from
	# src/core/cgroup.c in the systemd source tree.
	mknod -m 666 $TARGET/dev/null	c 1 3
	mknod -m 666 $TARGET/dev/zero	c 1 5
	mknod -m 666 $TARGET/dev/full	c 1 7
	mknod -m 666 $TARGET/dev/random	c 1 8
	mknod -m 666 $TARGET/dev/urandom	c 1 9
	mknod -m 666 $TARGET/dev/tty	c 5 0
	mkdir $TARGET/dev/pts/ $TARGET/dev/shm/
	# Inside a container, we might not be allowed to create /dev/ptmx.
	# If not, do the next best thing.
	if ! mknod -m 666 $TARGET/dev/ptmx c 5 2; then
		warning MKNOD "Could not create /dev/ptmx, falling back to symlink. This chroot will require /dev/pts mounted with ptmxmode=666"
		ln -s pts/ptmx $TARGET/dev/ptmx
	fi
	ln -s /proc/self/fd   $TARGET/dev/fd
	ln -s /proc/self/fd/0 $TARGET/dev/stdin
	ln -s /proc/self/fd/1 $TARGET/dev/stdout
	ln -s /proc/self/fd/2 $TARGET/dev/stderr
}

setup_devices_fakechroot () {
	rm -rf "$TARGET/dev"
	ln -s /dev "$TARGET"
}

setup_dselect_method () {
	case "$1" in
	    apt)
		mkdir -p "$TARGET/var/lib/dpkg"
		echo "apt apt" > "$TARGET/var/lib/dpkg/cmethopt"
		chmod 644 "$TARGET/var/lib/dpkg/cmethopt"
		;;
	    *)
		error 1 UNKNOWNDSELECT "unknown dselect method"
		;;
	esac
}

# Find out where the runtime dynamic linker and the shared libraries
# can be installed on each architecture: native, multilib and multiarch.
# This data can be verified by checking the files in the debian/sysdeps/
# directory of the glibc package.
#
# This function must be updated to support any new architecture which
# either installs the RTLD in a directory different from /lib or builds
# multilib library packages.
setup_merged_usr() {
	if [ "$MERGED_USR" = "no" ]; then return 0; fi

	local link_dir
	case $ARCH in
	    hurd-*)	return 0 ;;
	    amd64)	link_dir="lib32 lib64 libx32" ;;
	    i386)	link_dir="lib64 libx32" ;;
	    mips|mipsel)
			link_dir="lib32 lib64" ;;
	    mips64*|mipsn32*)
			link_dir="lib32 lib64 libo32" ;;
	    powerpc)	link_dir="lib64" ;;
	    ppc64)	link_dir="lib32 lib64" ;;
	    ppc64el)	link_dir="lib64" ;;
	    s390x)	link_dir="lib32" ;;
	    sparc)	link_dir="lib64" ;;
	    sparc64)	link_dir="lib32 lib64" ;;
	    x32)	link_dir="lib32 lib64 libx32" ;;
	esac
	link_dir="bin sbin lib $link_dir"

	local dir
	for dir in $link_dir; do
		ln -s usr/$dir $TARGET/$dir
		mkdir -p $TARGET/usr/$dir
	done
}

##################################################### dependency resolution

resolve_deps () {
	local m1="${MIRRORS%% *}"

	local PKGS="$*"
	local ALLPKGS="$PKGS";
	local ALLPKGS2="";
	while [ "$PKGS" != "" ]; do
		local NEWPKGS=""
		for c in ${COMPONENTS:-$USE_COMPONENTS}; do
			local path="dists/$SUITE/$c/binary-$ARCH/Packages"
			local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m1" "$path")"
			NEWPKGS="$NEWPKGS $(pkgdetails GETDEPS "$pkgdest" $PKGS)"
		done
		PKGS=$(echo "$PKGS $NEWPKGS" | tr ' ' '\n' | sort | uniq)
		local REALPKGS=""
		for c in ${COMPONENTS:-$USE_COMPONENTS}; do
			local path="dists/$SUITE/$c/binary-$ARCH/Packages"
			local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m1" "$path")"
			REALPKGS="$REALPKGS $(pkgdetails PKGS REAL "$pkgdest" $PKGS | sed -n 's/ .*REAL.*$//p')"
		done
		PKGS="$REALPKGS"
		ALLPKGS2=$(echo "$PKGS $ALLPKGS" | tr ' ' '\n' | sort | uniq)
		PKGS=$(without "$ALLPKGS2" "$ALLPKGS")
		ALLPKGS="$ALLPKGS2"
	done
	echo $ALLPKGS
}

setup_available () {
	local m1="${MIRRORS%% *}"

	for c in ${COMPONENTS:-$USE_COMPONENTS}; do
		local path="dists/$SUITE/$c/binary-$ARCH/Packages"
		local pkgdest="$TARGET/$($DLDEST pkg "$SUITE" "$c" "$ARCH" "$m1" "$path")"
		# XXX: What if a package is in more than one component?
		# -- cjwatson 2009-07-29
		pkgdetails STANZAS "$pkgdest" "$@"
	done >"$TARGET/var/lib/dpkg/available"

	for pkg; do
		echo "$pkg install"
	done | in_target dpkg --set-selections
}

get_next_predep () {
	local stanza="$(in_target_nofail dpkg --predep-package)"
	[ "$stanza" ] || return 1
	echo "$stanza" | grep '^Package:' | sed 's/^Package://; s/^ *//'
}

################################################################### helpers

# Return zero if it is possible to create devices and execute programs in
# this directory. (Both may be forbidden by mount options, e.g. nodev and
# noexec respectively.)
check_sane_mount () {
	mkdir -p "$1"

	case "$HOST_OS" in
	    *freebsd*|hurd*)
		;;
	    *)
		mknod "$1/test-dev-null" c 1 3 || return 1
		if ! echo test > "$1/test-dev-null"; then
			rm -f "$1/test-dev-null"
			return 1
		fi
		rm -f "$1/test-dev-null"
		;;
	esac

	SH="$PTS_DEBOOTSTRAP_BUSYBOX sh"
	[ -x "$PTS_DEBOOTSTRAP_BUSYBOX" ] || SH="/bin/sh"

	cat > "$1/test-exec" <<EOF
#! $SH
:
EOF
	chmod +x "$1/test-exec"
	if ! "$1/test-exec"; then
		rm -f "$1/test-exec"
		return 1
	fi
	rm -f "$1/test-exec"

	return 0
}

read_gpg_status () {
	badsig=
	unkkey=
	validsig=
	while read prefix keyword keyid rest; do
		[ "$prefix" = '[GNUPG:]' ] || continue
		case $keyword in
		    BADSIG)	badsig="$keyid" ;;
		    NO_PUBKEY)	unkkey="$keyid" ;;
		    VALIDSIG)	validsig="$keyid" ;;
		esac
	done
	if [ "$validsig" ]; then
		info VALIDRELSIG "Valid Release signature (key id %s)" "$validsig"
	elif [ "$badsig" ]; then
		error 1 BADRELSIG "Invalid Release signature (key id %s)" "$badsig"
	elif [ "$unkkey" ]; then
		error 1 UNKNOWNRELSIG "Release signed by unknown key (key id %s)" "$unkkey"
	else
		if in_path gpgv; then  #### pts #### TODO(pts): Remove this feature, we don't have gpgv.
			error 1 SIGCHECK "Error executing gpgv to check Release signature"
		fi
	fi
}

without () {
	# usage:  without "a b c" "a d" -> "b" "c"
	(echo $1 | tr ' ' '\n' | sort | uniq;
	 echo $2 $2 | tr ' ' '\n') | sort | uniq -u | tr '\n' ' '
	echo
}

# Formerly called 'repeat', but that's a reserved word in zsh.
repeatn () {
	local n="$1"
	shift
	while [ "$n" -gt 0 ]; do
		if "$@"; then
			break
		else
			n="$(( $n - 1 ))"
			sleep 1
		fi
	done
	if [ "$n" -eq 0 ]; then return 1; fi
	return 0
}

N_EXIT_THINGS=0
exit_function () {
	local n=0
	while [ "$n" -lt "$N_EXIT_THINGS" ]; do
		(eval $(eval echo \${EXIT_THING_$n}) 2>/dev/null || true)
		n="$(( $n + 1 ))"
	done
	N_EXIT_THINGS=0
}

trap "exit_function" 0
trap "exit 129" 1
trap "error 130 INTERRUPTED \"Interrupt caught ... exiting\"" 2
trap "exit 131" 3
trap "exit 143" 15

on_exit () {
	eval `echo EXIT_THING_${N_EXIT_THINGS}=\"$1\"`
	N_EXIT_THINGS="$(( $N_EXIT_THINGS + 1 ))"
}

############################################################## fakechroot tools

install_fakechroot_tools () {
	if [ "$VARIANT" = "fakechroot" ]; then
		export PATH=/usr/sbin:/sbin:$PATH
	fi

	mv "$TARGET/sbin/ldconfig" "$TARGET/sbin/ldconfig.REAL"
	echo \
"#!/bin/sh
echo
echo \"Warning: Fake ldconfig called, doing nothing\"" > "$TARGET/sbin/ldconfig"
	chmod 755 "$TARGET/sbin/ldconfig"

	echo \
"/sbin/ldconfig
/sbin/ldconfig.REAL
fakechroot" >> "$TARGET/var/lib/dpkg/diversions"

	mv "$TARGET/usr/bin/ldd" "$TARGET/usr/bin/ldd.REAL"
	cat << 'END' > "$TARGET/usr/bin/ldd"
#!/usr/bin/perl

# fakeldd
#
# Replacement for ldd with usage of objdump
#
# (c) 2003-2005 Piotr Roszatycki <dexter@debian.org>, BSD


my %libs = ();

my $status = 0;
my $dynamic = 0;
my $biarch = 0;

my $ldlinuxsodir = "/lib";
my @ld_library_path = qw(/usr/lib /lib);


sub ldso($) {
	my ($lib) = @_;
	my @files = ();

	if ($lib =~ /^\//) {
	    $libs{$lib} = $lib;
	    push @files, $lib;
	} else {
	    foreach my $ld_path (@ld_library_path) {
		next unless -f "$ld_path/$lib";
		my $badformat = 0;
		open OBJDUMP, "objdump -p $ld_path/$lib 2>/dev/null |";
	 	while (my $line = <OBJDUMP>) {
		    if ($line =~ /file format (\S*)$/) {
				$badformat = 1 unless $format eq $1;
				last;
		    }
		}
		close OBJDUMP;
		next if $badformat;
		$libs{$lib} = "$ld_path/$lib";
		push @files, "$ld_path/$lib";
	    }
	    objdump(@files);
	}
}


sub objdump(@) {
	my (@files) = @_;
	my @libs = ();

	foreach my $file (@files) {
	    open OBJDUMP, "objdump -p $file 2>/dev/null |";
	    while (my $line = <OBJDUMP>) {
		$line =~ s/^\s+//;
		my @f = split (/\s+/, $line);
		if ($line =~ /file format (\S*)$/) {
		    if (not $format) {
			$format = $1;
			if ($unamearch eq "x86_64" and $format eq "elf32-i386") {
			    my $link = readlink "/lib/ld-linux.so.2";
			    if ($link =~ /^\/emul\/ia32-linux\//) {
				$ld_library_path[-2] = "/emul/ia32-linux/usr/lib";
				$ld_library_path[-1] = "/emul/ia32-linux/lib";
			    }
			} elsif ($unamearch =~ /^(sparc|sparc64)$/ and $format eq "elf64-sparc") {
			    $ldlinuxsodir = "/lib64";
			    $ld_library_path[-2] = "/usr/lib64";
			    $ld_library_path[-1] = "/lib64";
			}
		    } else {
			next unless $format eq $1;
		    }
		}
		if (not $dynamic and $f[0] eq "Dynamic") {
		    $dynamic = 1;
		}
		next unless $f[0] eq "NEEDED";
		if ($f[1] =~ /^ld-linux(\.|-)/) {
		    $f[1] = "$ldlinuxsodir/" . $f[1];
		}
		if (not defined $libs{$f[1]}) {
		    $libs{$f[1]} = undef;
		    push @libs, $f[1];
		}
	    }
	    close OBJDUMP;
	}

	foreach my $lib (@libs) {
	    ldso($lib);
	}
}


if ($#ARGV < 0) {
	print STDERR "fakeldd: missing file arguments\n";
	exit 1;
}

while ($ARGV[0] =~ /^-/) {
	my $arg = $ARGV[0];
	shift @ARGV;
	last if $arg eq "--";
}

open LD_SO_CONF, "/etc/ld.so.conf";
while ($line = <LD_SO_CONF>) {
	chomp $line;
	unshift @ld_library_path, $line;
}
close LD_SO_CONF;

unshift @ld_library_path, split(/:/, $ENV{LD_LIBRARY_PATH});

$unamearch = `/bin/uname -m`;
chomp $unamearch;

foreach my $file (@ARGV) {
	my $address;
	%libs = ();
	$dynamic = 0;

	if ($#ARGV > 0) {
		print "$file:\n";
	}

	if (not -f $file) {
		print STDERR "ldd: $file: No such file or directory\n";
		$status = 1;
		next;
	}

	objdump($file);

	if ($dynamic == 0) {
		print "\tnot a dynamic executable\n";
		$status = 1;
	} elsif (scalar %libs eq "0") {
		print "\tstatically linked\n";
	}

	if ($format =~ /^elf64-/) {
		$address = "0x0000000000000000";
	} else {
		$address = "0x00000000";
	}

	foreach $lib (keys %libs) {
		if ($libs{$lib}) {
			printf "\t%s => %s (%s)\n", $lib, $libs{$lib}, $address;
		} else {
			printf "\t%s => not found\n", $lib;
		}
	}
}

exit $status;
END
	chmod 755 "$TARGET/usr/bin/ldd"

	echo \
"/usr/bin/ldd
/usr/bin/ldd.REAL
fakechroot" >> "$TARGET/var/lib/dpkg/diversions"

}

###########################################################################  end of functions

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
	SCRIPT=
	FORCE_SCRIPT="$DEBOOTSTRAP_DIR/suite-script"
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

	SCRIPT="$1"
	if test "$4"; then
		FORCE_SCRIPT="$4"
		SCRIPT=
	elif test "${1%*/}" != "$1"; then
		FORCE_SCRIPT="$SCRIPT"
		SCRIPT=
	else
		FORCE_SCRIPT=
	fi
	if test "$FORCE_SCRIPT"; then
		test -e "$FORCE_SCRIPT" || error 1 NOSCRIPT "No such script: %s" "$FORCE_SCRIPT"
	elif test -z "$SCRIPT"; then
		error 1 EMPTYSCRIPT "Empty script value specified."
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
  #echo "FORCE_SCRIPT=$FORCE_SCRIPT" >&4
  #echo "DEF0_MIRROR=$DEF0_MIRROR" >&4
fi
info DEF0MIRROR "Using mirror: $DEF0_MIRROR"

get_script_by_mirror () {
	if [ "${DEF0_MIRROR%/ubuntu*}" != "$DEF0_MIRROR" ]; then
		SCRIPT="gutsy"
	elif [ "${DEF0_MIRROR%/tanglu*}" != "$DEF0_MIRROR" ]; then
		SCRIPT="aequorea"
	elif [ "${DEF0_MIRROR%/debian*}" != "$DEF0_MIRROR" ]; then
		SCRIPT="sid"
	else
		warning UNKNOWNDIST "Unknown Linux distribution based on mirror URL: %s" "$DEF0_MIRROR"
	fi
}

download_script () {
	SCRIPT_URL="$BASE_URL/pts-debootstrap.scripts/$SCRIPT"
	info SCRIPTDOWNLOAD "Downloading script: $SCRIPT_URL"
	# TODO(pts): Restore $LD_LIBRARY_PATH etc.
	set +e
	:
	SCRIPT="$(PATH="$OLD_PATH" command $DOWNLOAD "$SCRIPT_URL")"
	test $? = 0 || SCRIPT=""
	set -e
}

if test -z "$FORCE_SCRIPT"; then
	# $BASE_URL and $DOWNLOAD were set up by the pts_debootstrap_cmd in the pts-debootstrap busybox executable.
        if test "$BASE_URL" && test "$DOWNLOAD"; then
		download_script
		if test -z "$SCRIPT"; then
			get_script_by_mirror
			download_script
			if test -z "$SCRIPT"; then
				error 1 NOSCRIPTDOWNLOAD "E: script download failed: %s" "$SCRIPT_URL"
			fi
		fi
	elif test -d "$DEBOOTSTRAP_DIR/pts-debootstrap.scripts"; then
		FORCE_SCRIPT="$DEBOOTSTRAP_DIR/pts-debootstrap.scripts/$SCRIPT"
		if ! test -e "$FORCE_SCRIPT"; then
			get_script_by_mirror
			FORCE_SCRIPT="$DEBOOTSTRAP_DIR/pts-debootstrap.scripts/$SCRIPT"
			test -e "$FORCE_SCRIPT" || error 1 NOSCRIPT "No such script: %s" "$FORCE_SCRIPT"
		fi
		SCRIPT=
	else
		error 1 NOSCRIPTDIR "Script directory missing: %s" "$DEBOOTSTRAP_DIR/pts-debootstrap.scripts"
	fi
fi

#echo "SCRIPT=($SCRIPT)" >&4; echo "FORCE_SCRIPT=($FORCE_SCRIPT)" >&4; exit

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

if test "$FORCE_SCRIPT"; then
	. "$FORCE_SCRIPT"
else
	eval "$SCRIPT"
fi
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
		# TODO(pts): Fix this ($0).
		cp "$0"				 "$TARGET/debootstrap/debootstrap"
		cp -- "$DEBOOTSTRAP_DIR/functions"	 "$TARGET/debootstrap/functions"
		if test "$FORCE_SCRIPT"; then
			cp -- "$FORCE_SCRIPT"			 "$TARGET/debootstrap/suite-script"
		else
			echo -n "$SCRIPT" >"$TARGET/debootstrap/suite-script"
		fi
		chmod 755 "$TARGET/debootstrap/suite-script"
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
