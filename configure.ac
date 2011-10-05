AC_PREREQ([2.68])
AC_INIT([opengl-glib], [0.1], [blaz.tomazic@gmail.com])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([foreign -Wall -Werror])
AM_SILENT_RULES([yes])
AC_CONFIG_FILES([Makefile
				 gir/Makefile])

# Check for programs.
AC_PROG_CC
AM_PROG_CC_C_O
AM_PROG_VALAC
PKG_PROG_PKG_CONFIG

# Check for libraries.
PKG_CHECK_MODULES([GLIB], [glib-2.0])
AC_SUBST([GLIB_CFLAGS])
AC_SUBST([GLIB_LIBS])
PKG_CHECK_MODULES([GEE], [gee-1.0])
AC_SUBST([GEE_CFLAGS])
AC_SUBST([GEE_LIBS])

GENERATE_VALAPACKAGES="--pkg gee-1.0"
AC_SUBST([GENERATE_VALAPACKAGES])

# Check for headers
AC_PREPROC_IFELSE(
   [AC_LANG_PROGRAM([[#include <GL/gl.h>]])],
   [AC_MSG_RESULT([OK])],
   [AC_MSG_FAILURE([OpenGL headers are missing])])

AC_OUTPUT
