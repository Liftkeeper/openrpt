#
# OpenRPT report writer and rendering engine
# Copyright (C) 2001-2016 by OpenMFG, LLC
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
# Please contact info@openmfg.com with any questions on this license.
#

#
# This file is included by all the other project files
# and is where options or configurations that affect all
# of the projects can be place.
#

CONFIG += release dll
# TEMPORARY HACK
win32 {
  CONFIG -= dll
  CONFIG += staticlib
}
macx {
  CONFIG -= dll
  CONFIG += staticlib
}

# NO_PNG removes dependency on libpng for Zint
DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0 NO_PNG

# expose generated headers from the common library when shadow building
# Make shadow builds aware of generated headers from the common library.
isEqual(TEMPLATE, subdirs) {
  # nothing
} else {
  shadow_dirs = $$OUT_PWD
  shadow_dirs += $$clean_path($$OUT_PWD/..)
  shadow_dirs += $$clean_path($$OUT_PWD/../..)

  for(shadow_dir, shadow_dirs) {
    common_dir = $$shadow_dir/common
    tmp_dir = $$common_dir/tmp
    exists($$common_dir) {
      INCLUDEPATH += $$common_dir
      DEPENDPATH += $$common_dir
    }
    exists($$tmp_dir) {
      INCLUDEPATH += $$tmp_dir
      DEPENDPATH += $$tmp_dir
    }
  }

  INCLUDEPATH = $$unique(INCLUDEPATH)
  DEPENDPATH = $$unique(DEPENDPATH)
}

LIBEXT = $${QMAKE_EXTENSION_SHLIB}
win32-g++:LIBEXT = a
macx:LIBEXT      = a
isEmpty( LIBEXT ) {
  win32:LIBEXT = a
  unix:LIBEXT  = so
}

LIBDMTX = -ldmtx

# OpenRPT includes an embedded copy of libdmtx for platforms where this
# library is not already available. Set the environment variable
# USE_SYSTEM_DMTX in the build env to build against the system library.
USE_SYSTEM_DMTX = $$(USE_SYSTEM_DMTX)
isEmpty( USE_SYSTEM_DMTX ) {
  CONFIG += bundled_dmtx
}

macx:exists(macx.pri) {
  include(macx.pri)
}

win32:exists(win32.pri) {
  include(win32.pri)
}

unix:exists(unix.pri) {
  include(unix.pri)
}
