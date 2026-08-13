# Epilogue Playback Linux SIGSEGV Workaround

Unofficial Linux workaround for a reproducible segmentation fault in
Epilogue Playback while processing the mGBA core option:

```text
mgba_frameskip_threshold
```

The issue was reproduced and investigated using GDB on Linux Mint 22.3.

A small binary patch prevents Playback from dereferencing the invalid
value `0x2` as a pointer.

> [!WARNING]
> This is an unofficial community workaround.
>
> This project is not affiliated with, maintained by, or endorsed by
> Epilogue.
>
> Do **not** apply the patch blindly to other Playback versions.
> Binary offsets can change between releases.

---

## Table of Contents

- [Problem](#problem)
- [Symptoms](#symptoms)
- [Root Cause](#root-cause)
- [GDB Analysis](#gdb-analysis)
- [Affected mGBA Option](#affected-mgba-option)
- [Binary Patch](#binary-patch)
- [Automatic Patch Script](#automatic-patch-script)
- [Manual Patch](#manual-patch)
- [Verification](#verification)
- [Restoring the Original Binary](#restoring-the-original-binary)
- [Tested Environment](#tested-environment)
- [Known Binary](#known-binary)
- [Disclaimer](#disclaimer)

---

# Problem

Epilogue Playback crashes on Linux with a segmentation fault (`SIGSEGV`).

The crash occurs while Playback creates or processes the configuration
interface for the mGBA core.

GDB identifies the crash at:

```asm
cmpb $0x0,0x0(%rbp)
```

At the time of the crash:

```text
rbp = 0x2
```

Playback therefore attempts to access memory address:

```text
0x2
```

which is not a valid userspace pointer.

The result is:

```text
SIGSEGV
```

---

# Symptoms

Playback may start and then unexpectedly terminate.

When executed under GDB, the crash appears similar to:

```text
Thread 1 "Playback" received signal SIGSEGV, Segmentation fault.

0x000055555587d2a8 in ?? ()
```

Register inspection shows:

```text
rbp = 0x2
```

The failing instruction is:

```asm
cmpb $0x0,0x0(%rbp)
```

This instruction attempts to read from the address stored in `rbp`.

Because:

```text
rbp = 0x2
```

Playback attempts to dereference address `0x2`.

---

# Root Cause

The affected function loads a value from offset `+0x18` of an mGBA
configuration option structure.

The relevant code is:

```asm
mov    0x18(%rbp),%rbp
test   %rbp,%rbp
je     ...
cmpb   $0x0,0x0(%rbp)
```

Normally, the value at offset `+0x18` appears to be expected to contain
either:

- a valid pointer
- or `NULL`

However, for the affected mGBA option, the value is:

```text
0x2
```

The existing check only tests whether the pointer is zero:

```asm
test %rbp,%rbp
je   ...
```

Since `0x2 != 0`, execution continues.

Playback then executes:

```asm
cmpb $0x0,(%rbp)
```

which attempts to access:

```text
0x0000000000000002
```

and causes the segmentation fault.

---

# GDB Analysis

The crash was inspected using GDB.

Backtrace:

```text
#0  0x000055555587d2a8 in ?? ()
#1  0x000055555588291f in ?? ()
#2  QObject::event(QEvent*)
#3  QApplicationPrivate::notify_helper(QObject*, QEvent*)
#4  QCoreApplication::notifyInternal2(QObject*, QEvent*)
#5  QCoreApplicationPrivate::sendPostedEvents(...)
#6  ...
#12 QCoreApplication::exec()
#13 0x0000555555667a43 in ?? ()
```

The relevant register state at the crash was:

```text
rbp = 0x2
rsi = 0x7
rcx = 0x1
rdx = 0x3e
```

The failing code:

```asm
mov    0x18(%rbp),%rbp
test   %rbp,%rbp
je     ...
cmpb   $0x0,0x0(%rbp)
```

After:

```asm
mov 0x18(%rbp),%rbp
```

the value of `rbp` becomes:

```text
0x2
```

The subsequent NULL check does not catch this value.

---

# Affected mGBA Option

A breakpoint was placed before the affected function was called.

The relevant structure contained:

```text
mgba_frameskip_threshold
```

with the visible label:

```text
Frameskip Grenzwert (%)
```

Additional values included:

```text
performance
15
18
21
24
27
```

The important structure entry was:

```text
offset +0x18 = 0x2
```

Example GDB output:

```text
(gdb) x/s *(char **)($rsi+0x00)
"mgba_frameskip_threshold"

(gdb) x/s *(char **)($rsi+0x08)
"Frameskip Grenzwert (%)"

(gdb) x/gx $rsi+0x18
0x0000000000000002

(gdb) x/s *(char **)($rsi+0x28)
"performance"

(gdb) x/s *(char **)($rsi+0x30)
"15"
```

Other mGBA options inspected during debugging did not contain the same
invalid pointer-like value at this position.

For example:

```text
mgba_gb_model
mgba_use_bios
mgba_skip_bios
```

did not reproduce the same condition.

---

# Binary Patch

The affected code in the tested Playback binary is located around:

```text
0x32929f
```

Original instructions:

```asm
32929b: mov    0x18(%rbp),%rbp
32929f: test   %rbp,%rbp
3292a2: je     329410
3292a8: cmpb   $0x0,0x0(%rbp)
```

Original bytes:

```text
48 85 ed 0f 84 68 01 00 00
```

The workaround replaces the NULL-only check with:

```asm
cmp $0x2,%ebp
jbe 329410
```

Patched instructions:

```asm
32929f: cmp    $0x2,%ebp
3292a2: jbe    329410
```

Patched bytes:

```text
83 fd 02 0f 86 68 01 00 00
```

This causes the code to skip the dereference when the value is:

```text
0x0
0x1
0x2
```

and therefore prevents address `0x2` from being accessed.

After applying this modification, Playback was successfully started and
tested on the affected system.

---

# Automatic Patch Script

The recommended way to apply the workaround is with a script that first
verifies the binary before modifying it.

Create:

```text
patch-playback.sh
```

with the following contents:

```bash
#!/usr/bin/env bash

set -euo pipefail

PLAYBACK="${1:-usr/bin/Playback}"

OFFSET=$((0x32929f))

EXPECTED="4885ed0f8468010000"
PATCHED="83fd020f8668010000"

if [ ! -f "$PLAYBACK" ]; then
    echo "ERROR: Playback binary not found:"
    echo "$PLAYBACK"
    exit 1
fi

echo "Playback binary:"
echo "$PLAYBACK"
echo

echo "Calculating SHA-256..."
sha256sum "$PLAYBACK"
echo

CURRENT=$(xxd -p -l 9 -s "$OFFSET" "$PLAYBACK")

echo "Bytes at patch location:"
echo "$CURRENT"
echo

if [ "$CURRENT" = "$PATCHED" ]; then
    echo "Playback is already patched."
    exit 0
fi

if [ "$CURRENT" != "$EXPECTED" ]; then
    echo "ERROR: Unexpected bytes at patch location."
    echo
    echo "Expected:"
    echo "$EXPECTED"
    echo
    echo "Found:"
    echo "$CURRENT"
    echo
    echo "This may be a different Playback version."
    echo "No changes were made."
    exit 1
fi

BACKUP="${PLAYBACK}.backup"

if [ -e "$BACKUP" ]; then
    echo "ERROR: Backup already exists:"
    echo "$BACKUP"
    echo
    echo "No changes were made."
    exit 1
fi

echo "Creating backup..."
cp --preserve=all "$PLAYBACK" "$BACKUP"

echo "Applying patch..."

printf '\x83\xfd\x02\x0f\x86' | \
    dd of="$PLAYBACK" \
       bs=1 \
       seek="$OFFSET" \
       conv=notrunc \
       status=none

echo "Verifying patch..."

CURRENT=$(xxd -p -l 9 -s "$OFFSET" "$PLAYBACK")

if [ "$CURRENT" != "$PATCHED" ]; then
    echo "ERROR: Patch verification failed."
    echo "Restoring backup..."

    cp --preserve=all "$BACKUP" "$PLAYBACK"

    exit 1
fi

echo
echo "Patch successfully applied."
echo
echo "Original binary:"
echo "$BACKUP"
echo
echo "Patched binary:"
echo "$PLAYBACK"
```

Make the script executable:

```bash
chmod +x patch-playback.sh
```

Then run:

```bash
./patch-playback.sh /path/to/squashfs-root/usr/bin/Playback
```

---

# Manual Patch

The modification can also be applied manually.

**Make a backup first:**

```bash
cp usr/bin/Playback usr/bin/Playback.backup
```

Verify the original bytes:

```bash
xxd -g1 -l 9 -s 0x32929f usr/bin/Playback
```

Expected output:

```text
48 85 ed 0f 84 68 01 00 00
```

Apply the patch:

```bash
printf '\x83\xfd\x02\x0f\x86' | \
dd of=usr/bin/Playback \
bs=1 \
seek=$((0x32929f)) \
conv=notrunc \
status=none
```

Verify:

```bash
xxd -g1 -l 9 -s 0x32929f usr/bin/Playback
```

Expected patched bytes:

```text
83 fd 02 0f 86 68 01 00 00
```

---

# Verification

The patched area can be disassembled with:

```bash
objdump -d usr/bin/Playback \
  --start-address=0x32929b \
  --stop-address=0x3292b5
```

The relevant output should contain:

```asm
32929b: mov    0x18(%rbp),%rbp
32929f: cmp    $0x2,%ebp
3292a2: jbe    329410
3292a8: cmpb   $0x0,0x0(%rbp)
```

Playback should then start without the previously observed SIGSEGV.

---

# Restoring the Original Binary

If the patch causes problems, restore the backup:

```bash
cp usr/bin/Playback.backup usr/bin/Playback
```

Alternatively, extract a clean copy of Playback from the original
AppImage again.

---

# Tested Environment

The workaround was tested on:

| Component | Configuration |
|---|---|
| Operating System | Linux Mint 22.3 (Zena) |
| Ubuntu base | Noble |
| Architecture | x86-64 |
| Kernel | 7.0.0-28-generic |
| Desktop | Cinnamon |
| Display session | X11 |
| RAM | 31 GiB |
| GPU | NVIDIA GeForce GTX 1660 SUPER |
| VRAM | 6 GiB |
| NVIDIA driver | 595.84 |
| CUDA reported by NVIDIA-SMI | 13.2 |

Playback binary:

```text
ELF 64-bit LSB pie executable
x86-64
dynamically linked
stripped
```

Build ID:

```text
b405076f2e5397acecac54579f7125e9d33e9750
```

---

# Known Binary

SHA-256 of the original binary used during the investigation:

```text
372684bbb5dd180fcb018270b1fe3274df578108600da1f0cf959e63ab28e94b
```

File:

```text
Playback
```

This hash should be used to determine whether another user has the same
binary that was investigated here.

A different SHA-256 hash does **not** automatically mean that the bug is
absent, but the hard-coded patch offset should not be assumed to be
correct for another binary.

---

# Why the Patch Is Version-Specific

Playback is a PIE executable and the addresses displayed by GDB while
the application is running differ from the file offsets shown by
`objdump`.

During debugging, the relevant runtime address was approximately:

```text
0x55555587d29f
```

The corresponding location in the executable file was:

```text
0x32929f
```

The patch modifies the executable file at:

```text
0x32929f
```

This location may change when Playback is rebuilt or updated.

For this reason, **do not apply this patch to an unknown Playback
version without verifying the original machine code first.**

---

# Technical Interpretation

This workaround does not fix the underlying data structure or the code
that produces the value `0x2`.

Instead, it prevents the affected function from treating very small
integer values as valid memory addresses.

The actual upstream fix should ideally determine why the
`mgba_frameskip_threshold` option provides:

```text
0x2
```

at a location that is subsequently interpreted as a pointer.

Possible upstream solutions may include:

1. correcting the construction or interpretation of the mGBA option
   structure;
2. correctly handling the option type represented by `0x2`;
3. validating the field before treating it as a string pointer.

Therefore, this repository should be considered a **workaround and
technical investigation**, not an upstream source-code fix.

---

# Reporting the Issue

Users experiencing the same problem are encouraged to report it to
Epilogue and include:

- Linux distribution
- kernel version
- Playback version
- Playback binary SHA-256
- GPU
- graphics driver
- whether the crash occurs with `mgba_frameskip_threshold`
- GDB backtrace, if available

This will help determine which Playback versions and Linux
configurations are affected.

---

# Disclaimer

This repository contains an **unofficial community workaround**.

It is not affiliated with, maintained by, sponsored by, or endorsed by
Epilogue.

No Epilogue binaries, firmware, ROMs, or other proprietary files are
distributed by this project.

The patch modifies the user's own locally installed Playback binary.

Use it at your own risk.

Always keep a backup of the original executable.

---

# Credits

Issue investigation, GDB analysis and workaround developed through
manual debugging of the Linux version of Epilogue Playback.

Special thanks to the Epilogue team for developing Playback and the
GB Operator ecosystem.
