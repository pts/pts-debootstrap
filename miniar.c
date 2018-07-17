/*
 * miniar.c: ar(1) which works with debootstrap
 * by pts@fazekas.hu at Wed Jul 18 00:14:37 CEST 2018
 *
 * This is free software, under GNU GPL >=2. NO WARRANTY. Use at your own risk!
 *
 * Compilation: xstatic gcc -ansi -pedantic -s -O2 -W -Wall -Wextra -Werror -o miniar.xstatic miniar.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static __attribute__((noreturn)) void die(const char *msg) {
  fwrite("fatal: ", 1, 7, stderr);
  fwrite(msg, 1, strlen(msg), stderr);
  putc('\n', stderr);
  exit(120);
}

int main(int argc, char **argv) {
  char cmd, buf[60], *p, *fnend, **ap, is_found;
  FILE *f;
  int got;
  long size;

  (void)argc;
  if (!argv[0] || !argv[1] || argv[1][0] != '-' ||
      ((cmd = argv[1][1]) != 't' && cmd != 'p') ||
      (cmd == 't' && (!argv[2] || argv[3]))) {
    die("usage: miniar {-t <archive>|-p <archive> [<member> ...]}");
  }
  if (!(f = fopen(argv[2], "rb"))) {
    die("error opening archive");
  }
  if (8 != fread(buf, 1, 8, f) || 0 != memcmp(buf, "!<arch>\n", 8)) {
    die("bad archive header");
  }
  is_found = cmd == 't';
  for (;;) {
    if ((got = getc(f)) < 0) break;
    if (got == '\n') {
      if ((got = getc(f)) < 0) break;
    }
    buf[0] = got;
    if (fread(buf + 1, 1, 59, f) != 59 ||
        buf[58] != '`' || buf[59] != '\n') {
      die("bad member header");
    }
    /* Example buf: "control.tar.gz  1488715767  0     0     100644  1019      `\n". */
    for (p = buf + 16; p != buf && p[-1] == ' '; --p) {}
    fnend = p;
    *p = '\0';
    /* Now buf contains the filename. */
    for (p = buf + 48, size = 0;
         *p - '0' + 0U <= 9;
         size = size * 10 + *p++ - '0') {}
    /* Now size contains the file size. */
    /*fprintf(stderr, "file=(%s) size=(%ld)\n", buf, size);*/
    if (cmd == 't') {
      *fnend++ = '\n';
      fwrite(buf, 1, fnend - buf, stdout);
    } else {
      for (ap = argv + 3; *ap && 0 != strcmp(buf, *ap); ++ap) {}
      cmd = !*ap; /* 1: don't print member; 0: print member */
      if (cmd == 0) is_found = 1;
    }
    for (; size > 0; --size) {
      if ((got = getc(f)) < 0) {
        die("EOF in member");
      }
      if (cmd == 0) putchar(got);
    }
  }
  if (!is_found) {
    die("member not found");
  }
  /*fclose(f);*/ /* No need to call, we are exiting. */
  return 0;
}
