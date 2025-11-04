#!/usr/bin/env bash
set -euo pipefail

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

[[ -f openrpt.pro ]] || die "Run this script from inside the OpenRPT source tree."

if command -v git >/dev/null 2>&1; then
  if ! git diff --quiet; then
    warn "Working tree has local changes; the patch steps may fail.  Consider starting from a clean checkout."
  fi
fi

if command -v apt-get >/dev/null 2>&1; then
  info "Installing build prerequisites (requires sudo)…"
  sudo apt-get update
  sudo apt-get install -y build-essential devscripts debhelper qt6-base-dev qt6-base-dev-tools
else
  warn "apt-get not found; make sure the Qt 6 development packages and debhelper are installed."
fi

info "Removing legacy Debian packaging fragments…"
rm -f debian/compat \
      debian/libopenrpt-dev.dirs \
      debian/libopenrpt-dev.install \
      debian/libopenrpt1.install \
      debian/libopenrpt1.lintian-overrides \
      debian/openrpt.install

info "Applying CLI build system patches…"
patch -p1 <<'EOF'
diff --git a/openrpt.pro b/openrpt.pro
index bbda162..a6d3bb9 100644
--- a/openrpt.pro
+++ b/openrpt.pro
@@ -25,20 +25,25 @@ bundled_dmtx {
 }
 
 TEMPLATE = subdirs
-SUBDIRS = common \
-          graph \
-          MetaSQL \
-          MetaSQL/metasql_gui \
-          MetaSQL/importmql_gui \
-          $$DMTX_SRC \
-          OpenRPT/qzint \
-          OpenRPT/renderer \
-          OpenRPT/wrtembed \
-          OpenRPT/writer \
-          OpenRPT/renderapp \
-          OpenRPT/import \
-          OpenRPT/import_gui \
-          OpenRPT/export
-
-CONFIG += ordered
+cli_only {
+  SUBDIRS = OpenRPT/import \
+            OpenRPT/export
+} else {
+  SUBDIRS = common \
+            graph \
+            MetaSQL \
+            MetaSQL/metasql_gui \
+            MetaSQL/importmql_gui \
+            $$DMTX_SRC \
+            OpenRPT/qzint \
+            OpenRPT/renderer \
+            OpenRPT/wrtembed \
+            OpenRPT/writer \
+            OpenRPT/renderapp \
+            OpenRPT/import \
+            OpenRPT/import_gui \
+            OpenRPT/export
+}
 
+CONFIG += ordered
diff --git a/OpenRPT/import/import.pro b/OpenRPT/import/import.pro
index 18dfc9c..1747808 100644
--- a/OpenRPT/import/import.pro
+++ b/OpenRPT/import/import.pro
@@ -19,9 +19,10 @@
 #
 
 include( ../../global.pri )
+CONFIG -= dll
 
 TEMPLATE = app
-CONFIG += warn_on console
+CONFIG += warn_on console c++17
 
 TARGET = importrpt
 DESTDIR = ../../bin
@@ -30,17 +31,14 @@ OBJECTS_DIR = tmp
 UI_DIR = tmp
 
 # Input
-HEADERS += ../common/builtinSqlFunctions.h				# MANU
-SOURCES += main.cpp ../common/builtinSqlFunctions.cpp				# MANU
+HEADERS += ../common/builtinSqlFunctions.h \
+           ../../common/dbtools.h
 
-INCLUDEPATH += ../../common ../common
-QMAKE_LIBDIR = ../../lib $$QMAKE_LIBDIR
-LIBS += -lopenrptcommon
+SOURCES += main.cpp \
+           ../common/builtinSqlFunctions.cpp \
+           ../../common/dbtools.cpp
 
-win32-msvc* {
-  PRE_TARGETDEPS += ../../lib/openrptcommon.$${LIBEXT}
-} else {
-  PRE_TARGETDEPS += ../../lib/libopenrptcommon.$${LIBEXT}
-}
+INCLUDEPATH += ../../common ../common
 
-QT += xml sql
+QT += core xml sql
+QT -= gui
diff --git a/OpenRPT/export/export.pro b/OpenRPT/export/export.pro
index 6e18e9d..22dce81 100644
--- a/OpenRPT/export/export.pro
+++ b/OpenRPT/export/export.pro
@@ -19,9 +19,10 @@
 #
 
 include( ../../global.pri )
+CONFIG -= dll
 
 TEMPLATE = app
-CONFIG += warn_on console
+CONFIG += warn_on console c++17
 
 TARGET = exportrpt
 DESTDIR = ../../bin
@@ -30,19 +31,14 @@ OBJECTS_DIR = tmp
 UI_DIR = tmp
 
 # Input
-HEADERS = ../common/builtinSqlFunctions.h		# MANU
+HEADERS = ../common/builtinSqlFunctions.h \
+          ../../common/dbtools.h		# MANU
 
 SOURCES += main.cpp \
-           ../common/builtinSqlFunctions.cpp	# MANU
+           ../common/builtinSqlFunctions.cpp \
+           ../../common/dbtools.cpp	# MANU
 
 INCLUDEPATH += ../../common ../common
-QMAKE_LIBDIR = ../../lib $$QMAKE_LIBDIR
-LIBS += -lopenrptcommon
 
-win32-msvc* {
-  PRE_TARGETDEPS += ../../lib/openrptcommon.$${LIBEXT}
-} else {
-  PRE_TARGETDEPS += ../../lib/libopenrptcommon.$${LIBEXT}
-}
-
-QT += xml sql
+QT += core xml sql
+QT -= gui
diff --git a/OpenRPT/import/main.cpp b/OpenRPT/import/main.cpp
index 02a4cb9..bf8483c 100644
--- a/OpenRPT/import/main.cpp
+++ b/OpenRPT/import/main.cpp
@@ -22,7 +22,6 @@
 
 #include <QCoreApplication>
 #include <QString>
-#include <QRegExp>
 #include <QSqlDatabase>
 #include <QVariant>
 #include <QFile>
@@ -49,7 +48,7 @@ int main(int argc, char *argv[])
     QString passwd;
   	QString arguments;
 
-    QString xml_file = QString::null;
+    QString xml_file;
     int     report_grade = 0;
 
     for (int counter = 1; counter < argc; counter++)
@@ -70,9 +69,9 @@ int main(int argc, char *argv[])
         xml_file = arguments;
     }
 
-    QString report_name = QString::null;
-    QString report_desc = QString::null;
-    QString report_src  = QString::null;
+    QString report_name;
+    QString report_desc;
+    QString report_src;
 
     if(xml_file != "") {
         QFile file(xml_file);
@@ -94,19 +93,19 @@ int main(int argc, char *argv[])
                     report_src  = doc.toString();
 
                     if(report_name == "") {
-                        out << "The document " << xml_file << " does not have a report name defined." << endl;
+                        out << "The document " << xml_file << " does not have a report name defined." << Qt::endl;
                     }
                 } else {
-                    out << "XML Document " << xml_file << " does not have root node of report." << endl;
+                    out << "XML Document " << xml_file << " does not have root node of report." << Qt::endl;
                 }
             } else {
-                out << "Error parsing file " << xml_file << ": " << errMsg << " on line " << errLine << " column " << errCol << endl;
+                out << "Error parsing file " << xml_file << ": " << errMsg << " on line " << errLine << " column " << errCol << Qt::endl;
             }
         } else {
-            out << "Could not open the specified file: " << xml_file << endl;
+            out << "Could not open the specified file: " << xml_file << Qt::endl;
         }
     } else {
-        out << "You must specify an XML file to load by using the -f= parameter." << endl;
+        out << "You must specify an XML file to load by using the -f= parameter." << Qt::endl;
     }
 
     if(report_name == "" || report_src == "") {
@@ -123,7 +122,7 @@ int main(int argc, char *argv[])
       db = databaseFromURL( databaseURL );
       if (!db.isValid())
       {
-        out << "Could not load the specified database driver." << endl;
+        out << "Could not load the specified database driver." << Qt::endl;
         exit(-1);
       }
 
@@ -132,9 +131,9 @@ int main(int argc, char *argv[])
       db.setPassword(passwd);
       if (!db.open())
       {
-        out << "Host=" << db.hostName() << ", Database=" << db.databaseName() << ", port=" << db.port() << endl;
+        out << "Host=" << db.hostName() << ", Database=" << db.databaseName() << ", port=" << db.port() << Qt::endl;
         out << "Could not log into database.  System Error: "
-            << db.lastError().text() << endl;
+            << db.lastError().text() << Qt::endl;
         exit(-1);
       }
 
@@ -166,20 +165,20 @@ int main(int argc, char *argv[])
       
       if(!query.exec()) {
           QSqlError err = query.lastError();
-          out << "Error: " << err.driverText() << endl
-              << "\t" << err.databaseText() << endl;
+          out << "Error: " << err.driverText() << Qt::endl
+              << "\t" << err.databaseText() << Qt::endl;
           exit(-1);
       }
       
     }
     else if (databaseURL == "")
-      out << "You must specify a Database URL by using the -databaseURL= parameter." << endl;
+      out << "You must specify a Database URL by using the -databaseURL= parameter." << Qt::endl;
     else if (username == "")
-      out << "You must specify a Database Username by using the -username= parameter." << endl;
+      out << "You must specify a Database Username by using the -username= parameter." << Qt::endl;
     else if (passwd == "")
-      out << "You must specify a Database Password by using the -passwd= parameter." << endl;
+      out << "You must specify a Database Password by using the -passwd= parameter." << Qt::endl;
   }
   else
-    out << "Usage: import -databaseURL='$' -username='$' -passwd='$' -grade=# -f='$'" << endl;
+    out << "Usage: import -databaseURL='$' -username='$' -passwd='$' -grade=# -f='$'" << Qt::endl;
   return 0;
 }
diff --git a/OpenRPT/export/main.cpp b/OpenRPT/export/main.cpp
index 4dc2e36..2030919 100644
--- a/OpenRPT/export/main.cpp
+++ b/OpenRPT/export/main.cpp
@@ -59,10 +59,6 @@ int main(int argc, char *argv[])
 
     if (  (databaseURL != "") && (username != "") ) {
       QSqlDatabase db;
-      QString      protocol;
-      QString      hostName;
-      QString      dbName;
-      QString      port;
 
 // Open the Database Driver
       db = databaseFromURL(databaseURL);
@@ -73,18 +69,15 @@ int main(int argc, char *argv[])
       }
 
 //  Try to connect to the Database
-      bool valport = false;
-      int iport = port.toInt(&valport);
-      if(!valport) iport = 5432;
       db.setUserName(username);
       if(!passwd.isEmpty())
         db.setPassword(passwd);
       if (!db.open())
       {
         printf( "Host=%s, Database=%s, port=%s\n",
-                hostName.toLatin1().data(),
-                dbName.toLatin1().data(),
-                port.toLatin1().data() );
+                db.hostName().toLatin1().constData(),
+                db.databaseName().toLatin1().constData(),
+                QByteArray::number(db.port()).constData() );
 
         printf( "Could not log into database.  System Error: %s\n",
                 db.lastError().text().toLatin1().data() );
diff --git a/OpenRPT/common/builtinSqlFunctions.cpp b/OpenRPT/common/builtinSqlFunctions.cpp
index a0b64e7..0d5340c 100644
--- a/OpenRPT/common/builtinSqlFunctions.cpp
+++ b/OpenRPT/common/builtinSqlFunctions.cpp
@@ -16,7 +16,7 @@
  * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
  * Please contact info@openmfg.com with any questions on this license.
  */
-#include <QtGui>
+#include <QString>
 
 #include "builtinSqlFunctions.h"
 
@@ -254,5 +254,5 @@ QString getSqlFromTag(const QString & stTag, const QString & stDriver)
       return __SqlTable[i][__fieldSql];
     }
 
-  return QString::null;
+  return QString();
 }
diff --git a/OpenRPT/common/builtinSqlFunctions.h b/OpenRPT/common/builtinSqlFunctions.h
index 0164c61..92938a2 100644
--- a/OpenRPT/common/builtinSqlFunctions.h
+++ b/OpenRPT/common/builtinSqlFunctions.h
@@ -20,10 +20,9 @@
 #ifndef __BUILTIN_SQL_FUNCTIONS_H__
 #define __BUILTIN_SQL_FUNCTIONS_H__
 
-#include <qstring.h>
+#include <QString>
 
 QString getSqlFromTag(const QString &, const QString &);
 bool getSqlDriver(const QString &);
 
 #endif
-
diff --git a/debian/control b/debian/control
index 41995dc..e86bbb8 100644
--- a/debian/control
+++ b/debian/control
@@ -1,44 +1,17 @@
 Source: openrpt
-Section: misc
+Section: utils
 Priority: optional
-Maintainer: Debian xTuple Maintainers <pkg-xtuple-maintainers@lists.alioth.debian.org>
-Uploaders:
- Andrew Shadura <andrewsh@debian.org>,
- Daniel Pocock <daniel@pocock.pro>
-Build-Depends: debhelper (>= 9), libqt4-dev (>= 4.1.0), libdmtx-dev, dpkg-dev (>= 1.16.1~)
-Standards-Version: 3.9.5
+Maintainer: OpenRPT Maintainers <maintainers@example.com>
+Build-Depends: debhelper-compat (= 13), qt6-base-dev, qt6-base-dev-tools
+Standards-Version: 4.6.2
 Homepage: http://www.xtuple.com/openrpt/
-Vcs-Git: https://github.com/xtuple/openrpt
-Vcs-Browser: https://github.com/xtuple/openrpt
+Rules-Requires-Root: no
 
-Package: libopenrpt1
-Section: libs
+Package: openrpt-cli
 Architecture: any
-Pre-Depends: ${misc:Pre-Depends}
-Depends: ${shlibs:Depends}, ${misc:Depends}
-Description: graphical SQL report writer, designer and rendering library
- Graphical SQL report writer, designer and rendering engine, optimized
- for PostgreSQL. WYSIWYG display, GUI built with Qt. Reports can be saved
- as XML, either as files or in a database.
- .
- This package contains the shared libraries.
-
-Package: openrpt
-Architecture: any
-Depends: ${shlibs:Depends}, ${misc:Depends}, libqt4-sql-psql
-Description: graphical SQL report writer, designer and rendering engine
- Graphical SQL report writer, designer and rendering engine, optimized
- for PostgreSQL. WYSIWYG display, GUI built with Qt. Reports can be saved
- as XML, either as files or in a database.
-
-Package: libopenrpt-dev
-Section: libdevel
-Architecture: any
-Depends: libqt4-dev (>= 4.1.0), libdmtx-dev, ${misc:Depends}, libopenrpt1 (= ${binary:Version})
-Description: graphical SQL report writer, designer and rendering engine (development)
- Graphical SQL report writer, designer and rendering engine, optimized
- for PostgreSQL. WYSIWYG display, GUI built with Qt. Reports can be saved
- as XML, either as files or in a database.
- .
- This package contains the static development library and its headers.
-
+Depends: ${shlibs:Depends}, ${misc:Depends}, libqt6sql6-psql
+Description: command-line utilities for OpenRPT report import/export
+ OpenRPT provides tools for storing and retrieving report definitions
+ from a PostgreSQL database. This package contains the headless
+ importer (`importrpt`) and exporter (`exportrpt`) utilities which
+ allow managing report XML files entirely from the command line.
diff --git a/debian/rules b/debian/rules
old mode 100644
new mode 100755
index 3c85938..6dbcd6c
--- a/debian/rules
+++ b/debian/rules
@@ -1,34 +1,24 @@
 #!/usr/bin/make -f
 
-include /usr/share/dpkg/architecture.mk
-
-# this tells OpenRPT's build system not to build its own copy of libdmtx
-export USE_SYSTEM_DMTX=1
-
 %:
-	dh $@ --builddirectory=. --parallel
-
-override_dh_auto_clean:
-	rm -rf bin/* OpenRPT/Dmtx_Library
-	chmod -x OpenRPT/images/*.png
-	dh_auto_clean
+	dh $@ --builddirectory=build-cli
 
 override_dh_auto_configure:
-	lrelease */*/*.ts */*.ts
-	# convert to dynamic linking
-	#find . -name '*.pro' -a -not -path './.pc/*' -exec sed -i.orig -e 's/staticlib/dll/g' -e 's/lib\([A-Za-z]*\)\.a/lib\1.so/'  {} \;
-	dh_auto_configure
+	mkdir -p build-cli
+	cd build-cli && qmake6 CONFIG+=cli_only ../openrpt.pro
 
-override_dh_auto_install:
-	mv bin/graph bin/openrpt-graph
-	mkdir -p debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)
-	mv lib/lib*.so* debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)
-	dh_auto_install
-	#find . -name '*.pro' -a -not -path './.pc/*' -exec test -e {}.orig \; -a -exec mv -f {}.orig {} \;
+override_dh_auto_build:
+	$(MAKE) -C build-cli
 
-get-orig-source:
-	@d=$$(readlink -e $(MAKEFILE_LIST)); \
-	cd $${d%/*}/..; \
-	debian/get-orig-source.sh $(CURDIR) +dfsg
+override_dh_auto_install:
+	@true
 
-.PHONY: override_dh_auto_configure override_dh_auto_install override_dh_auto_clean get-orig-source
+override_dh_auto_clean:
+	if [ -f build-cli/Makefile ]; then \
+		$(MAKE) -C build-cli clean; \
+	fi
+	rm -rf build-cli
+
+override_dh_builddeb:
+	mkdir -p $(CURDIR)/debian/artifacts
+	dh_builddeb --destdir=$(CURDIR)/debian/artifacts
diff --git a/debian/changelog b/debian/changelog
index c920a4c..1d6e118 100644
--- a/debian/changelog
+++ b/debian/changelog
@@ -1,3 +1,10 @@
+openrpt (3.3.13-1ubuntu24cli1) unstable; urgency=medium
+
+  * Build CLI-only importer/exporter against Qt 6 for Ubuntu 24.04.
+  * Simplify Debian packaging to ship the headless openrpt-cli binary.
+
+ -- OpenRPT Maintainers <maintainers@example.com>  Tue, 04 Nov 2025 10:48:30 +0000
+
 openrpt (3.3.13-1) unstable; urgency=medium
 
   * Placeholder
EOF

info "Writing new debian/openrpt-cli.install…"
cat <<'EOF' > debian/openrpt-cli.install
build-cli/bin/importrpt usr/bin
build-cli/bin/exportrpt usr/bin
EOF

chmod 755 debian/rules

info "Running Debian package build…"
fakeroot debian/rules clean
fakeroot debian/rules binary

info "Done. Packages are available in debian/artifacts/:"
ls -1 debian/artifacts || true
