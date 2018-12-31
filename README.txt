pts-debootstrap: portable debootstrap for i386 and amd64
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
pts-debootstrap is set of portable tools for creating chroot environments
for Debian and Ubuntu Linux distributions. pts-debootstrap is based on
Debian's debootstrap tool, and it adds portability (it runs on any Linux i386
or amd64 system, and it doesn't need any package installation), and it
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

  $ rm -f pts-debootstrap-latest.sfx.7z
  $ wget http://pts.50.hu/files/pts-debootstrap/pts-debootstrap-latest.sfx.7z
  $ chmod u+x pts-debootstrap-latest.sfx.7z
  $ ./pts-debootstrap-latest.sfx.7z -y  # Created directory pts-debootstrap
  $ pts-debootstrap/bin/sh pts-debootstrap/pts-debootstrap --help

Usage for creating a chroot with the oldest supported Debian (potato,
Debian 2.2, released on 2000-08-15), i386:

  $ sudo pts-debootstrap/bin/sh pts-debootstrap/pts-debootstrap potato potato_dir
  ...
  $ sudo pts-debootstrap/bin/chroot potato_dir

Usage for creating a chroot with the oldest supported Ubuntu (breezy,
Ubuntu 5.10, released on 2005-10-12), i386:

  $ sudo pts-debootstrap/bin/sh pts-debootstrap/pts-debootstrap breezy breezy_dir
  ...
  $ sudo pts-debootstrap/bin/chroot breezy_dir

To start intalling packages, run `apt-get update' in the chroot first.
Example:

  $ sudo pts-debootstrap/bin/chroot breezy_dir apt-get update
  $ sudo pts-debootstrap/bin/chroot breezy_dir apt-get install gcc

__END__
