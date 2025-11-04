# Building the OpenRPT CLI Utilities on Ubuntu 24.04

This document explains every change that was made to the original OpenRPT
sources so the project can be built as a command‑line–only toolchain on a
modern Ubuntu 24.04 system.  It also walks through the steps needed to repeat
the conversion and produce a `.deb` package when starting from the pristine
upstream tree.

The quick path is to run `scripts/convert_to_cli.sh`, which applies all of the
edits and performs the build automatically.  The manual instructions below
describe what that script does, file by file.

---

## 1. Prerequisites

Install the build toolchain and Qt 6 development headers:

```bash
sudo apt update
sudo apt install build-essential git devscripts debhelper qt6-base-dev qt6-base-dev-tools
```

You can optionally install `lintian` if you plan to review the resulting
package.

---

## 2. Project File Adjustments

### 2.1 `openrpt.pro`

Add a `cli_only` qmake configuration switch so the build system can be told to
skip every GUI subdirectory and focus exclusively on the importer/exporter
targets:

```diff
 T TEMPLATE = subdirs
-SUBDIRS = common ... OpenRPT/export
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
```

This keeps the default behaviour unchanged while letting us pass
`CONFIG+=cli_only` for a headless build.

### 2.2 `OpenRPT/import/import.pro` and `OpenRPT/export/export.pro`

Both qmake project files were updated to:

- drop the legacy shared-library link against `libopenrptcommon`,
- add the shared `common/dbtools.cpp` source instead,
- request C++17 (`CONFIG += c++17`) which matches modern Qt defaults,
- remove any reliance on `QtGui` by shrinking `QT +=` to `core xml sql` and
  explicitly subtracting `QT -= gui`, and
- unset `dll` because we only need normal executables.

These changes ensure the CLI tools only link against the Qt modules they use.

---

## 3. Source Code Modernisation

### 3.1 `OpenRPT/common/builtinSqlFunctions.cpp` & `.h`

- Replace the deprecated include `<QtGui>` / `<qstring.h>` with `<QString>`.
- Return an empty `QString()` instead of the removed `QString::null`.

This is required because Qt 6 no longer provides `QString::null` and moved many
text classes out of `QtGui`.

### 3.2 `OpenRPT/import/main.cpp`

- Remove the unused `<QRegExp>` include.
- Default‑construct `QString` variables instead of using `QString::null`.
- Replace all occurrences of the obsolete `endl` macro with the namespaced
  `Qt::endl` so the code keeps flushing behaviour with Qt 6.
- Emit Qt strings for error messages when reporting connection failures.

### 3.3 `OpenRPT/export/main.cpp`

- Drop unused `QString` variables that manually parsed the database URL.
- When reporting a failed connection, use the `QSqlDatabase` accessors directly
  and format the port number with `QByteArray::number`.

These edits keep the CLI tools compatible with Qt 6 while avoiding dependencies
on GUI modules.

---

## 4. Debian Packaging Refresh

The original packaging shipped multiple GUI applications and libraries.  We
replace that with a single `openrpt-cli` binary package:

- **`debian/control`** – reduce the source dependencies to
  `debhelper-compat (= 13)` and Qt 6, and define a single binary stanza for the
  CLI importer/exporter (depending on `libqt6sql6-psql`).
- **`debian/rules`** – simplify the rules file to use a dedicated `build-cli`
  directory, run `qmake6 CONFIG+=cli_only`, and collect `.deb` artifacts in
  `debian/artifacts/` to avoid sandbox write issues.
- **`debian/changelog`** – prepend a new release entry describing the CLI port.
- **`debian/openrpt-cli.install`** – new helper listing the two executables to
  install under `/usr/bin`.
- Remove no longer needed files (`debian/compat`, `libopenrpt*.install`, etc.).

At build time, `fakeroot debian/rules binary` will place the resulting
`openrpt-cli_*.deb` and matching debug package in `debian/artifacts/`.

---

## 5. Building the CLI Manually

With the edits above in place:

```bash
# From the repository root
fakeroot debian/rules clean
fakeroot debian/rules binary
```

The CLI tools can also be test-built directly, without packaging:

```bash
mkdir -p build-cli
cd build-cli
qmake6 CONFIG+=cli_only ../openrpt.pro
make -j"$(nproc)"
./bin/importrpt   # prints usage information
./bin/exportrpt   # prints usage information
```

---

## 6. Building the Full GUI/DB Suite (legacy package)

The graphical designer, renderer, and database tools still rely on the Qt 5
stack. Until the port to Qt 6 is completed, build them in a separate tree that
keeps the upstream packaging layout:

1. Install the Qt 5 toolchain alongside the CLI prerequisites:

   ```bash
   sudo apt install qtbase5-dev qttools5-dev qttools5-dev-tools libqt5sql5-psql
   ```

2. Start from a clean copy of the original sources **without** the CLI-only
   packaging changes (for example by cloning the repository to a new folder).

3. Create a shadow build directory named to match upstream expectations and
   build with Qt 5:

   ```bash
   mkdir -p ../openrpt-build-desktop
   cd ../openrpt-build-desktop
   qmake ../openrpt/openrpt.pro
   make -j"$(nproc)"
   ```

4. Produce the Debian package that ships the GUI tools and libraries:

   ```bash
   fakeroot debian/rules clean
   fakeroot debian/rules binary
   ```

   The resulting `.deb` files will land alongside the build directory (for
   example `../openrpt_<version>_amd64.deb`). This binary contains the classic
   OpenRPT application suite (writer, renderer, database utilities, etc.).

5. You can now install both packages side by side:

   ```bash
   sudo apt install ./debian/artifacts/openrpt-cli_*.deb \
                    ../openrpt_<version>_amd64.deb
   ```

> **Heads-up**: the legacy package still depends on Qt 5 and retains the
> historical `openrpt` packaging structure. When the GUI port to Qt 6 is
> complete, these instructions can be updated to converge on a single build.

## 7. Automated Conversion Script

To reproduce all of the above from a fresh checkout:

```bash
./scripts/convert_to_cli.sh
```

The script will:

1. Install the required packages (if `apt` is available).
2. Apply every patch listed in sections 2–4.
3. Remove the legacy Debian packaging fragments.
4. Trigger `fakeroot debian/rules binary` and leave the `.deb` files in
   `debian/artifacts/`.

Afterwards, the CLI utilities (`importrpt`, `exportrpt`) are both installed in
`debian/openrpt-cli/usr/bin/` inside the packaging staging area, and the
installable package is ready in `debian/artifacts/`.

---

## 8. Verification Checklist

- `build-cli/bin/importrpt` and `build-cli/bin/exportrpt` run and show usage
  text.
- `debian/artifacts/openrpt-cli_<version>_amd64.deb` exists.
- `dpkg-deb -c debian/artifacts/openrpt-cli_<version>_amd64.deb` lists only the
  two CLI binaries and documentation.

Following this manual or the script will let anyone with minimal Qt knowledge
compile and package the headless OpenRPT utilities on Ubuntu 24.04.
