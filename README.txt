pts-debootstrap: portable debootstrap for i386 and amd64
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
pts-debootstrap is set of portable tools for creating chroot environments
for Debian, Ubuntu and Tanglu Linux distributions. pts-debootstrap is based
on Debian's debootstrap tool, and it adds portability (it runs on any Linux
i386 or amd64 system, and it doesn't need any package installation), and it
improves compatibility with older Debian and Ubuntu releases.

Features of pts-debootstrap:

* It supports very old Debian and Ubuntu releases (see below) by using the
  correct download URL for them.
* It runs on any Linux i386 and amd64 system. It's self-contained, thus it
  doesn't use any of the system packages (such as tar, gzip, dpkg-deb).
  (This is implemented by shipping a copy of statically-lined i386 busybox.)
* It runs in any directory, it doesn't need installation.
* Clears the environment variables so chroot creation is reproducible.
* It supports only i386 and amd64 host systems and chroot environments.
* It may also run on a FreeBSD host system in Linux emulation mode (not
  tested).

Installation to any directory, as a regular user:

  $ rm -f pts-debootstrap
  $ wget https://raw.githubusercontent.com/pts/pts-debootstrap/master/pts-debootstrap
  $ chmod u+x pts-debootstrap
  $ ./pts-debootstrap --help

Please note that by downloading only the pts-debootstrap executable above,
it will download pts-debootstrap.sh (and also the distribution suite script
file) from GitHub for each invocation. If you don't want that, you can check
out the repo, and run it from there:

  $ git clone https://github.com/pts/pts-debootstrap
  $ cd pts-debootstrap
  $ ./pts-debootstrap --help

Usage for creating a chroot with the oldest supported Debian (slink,
Debian 2.1, released on 1999-03-09), i386:

  $ sudo ./pts-debootstrap slink slink_dir
  ...
  $ sudo ./pts-debootstrap busybox chroot slink_dir

Alternatively, you may specify the suite as debian/slink or debian/2.1
instead of debian/slink. The list of releases (e.g. 2.1) are hardcoded for
Debian, Ubuntu and Tanglu.

Please note that in slink (Debian 2.1) and potato (Debian 2.2), UIDs larger
than 65535 are not supported by the glibc. The oldest Debian which works
with UIDs larger than 65535 is woody (Debian 3.0).

Earlier versions of Debian (such as hamm (Debian 2.0) and bo (Debian 1.3) and
rex (Debian 1.2) and buzz (Debian 1.1) don't work, because a debootstrap
install script has never been written for them.

Usage for creating a chroot with the oldest supported Ubuntu (breezy,
Ubuntu 5.10, released on 2005-10-12), i386:

  $ sudo ./pts-debootstrap breezy breezy_dir
  ...
  $ sudo ./pts-debootstrap busybox chroot breezy_dir

The default target architecture for pts-debootstrap is i386. Specify
`--arch amd64' to get amd64 (x86_64). (Other architectures don't work
out-of-the-box, because debootstrap runs code both inside and outside the
chroot.) The oldest version of Debian on amd64 is etch (Debian 4.0), and the
oldest supported version of Ubuntu on amd64 is breezy (Ubuntu 5.10).

  $ sudo ./pts-debootstrap --arch amd64 etch etch_dir

  $ sudo ./pts-debootstrap --arch amd64 breezy breezy_dir

To start intalling packages, run `apt-get update' in the chroot first.
Example:

  $ sudo ./pts-debootstrap busybox chroot breezy_dir apt-get update
  $ sudo ./pts-debootstrap busybox chroot breezy_dir apt-get install gcc

Earlier versions of Ubuntu (such as hoary (Ubuntu 5.04) and warty (Ubuntu
4.10)) don't work because they have glibc version 2.3.2, which is
incompatible with the modern Linux vdso (which cannot be disabled on modern
Linux systems), and they report the following error in .../debootstrap.log:

  Inconsistency detected by ld.so: rtld.c: 1192: dl_main: Assertion `(void *) ph->p_vaddr == _rtld_local._dl_sysinfo_dso' failed!

Running debootstrap or pts-debootstrap for a distribution with a glibc
incompatible with the vdso typically reports the following error on stderr:

  W: Failure trying to run: env PATH=/usr/... .../chroot /... mount -t proc proc /proc

The following releases of Tanglu Linux are supported:

* aequorea (Tanglu 1.0, 2014-04-22)
* bartholomea (Tanglu 2.0, 2014-12-13)
* chromodoris (Tanglu 3.0, 2015-08-05)
* dasyatis (Tanglu 4.0, 2017-06-11)

__END__
