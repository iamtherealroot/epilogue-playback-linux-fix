#!/usr/bin/env bash

set -euo pipefail

PLAYBACK="${1:-usr/bin/Playback}"
OFFSET=$((0x32929f))

EXPECTED="4885ed0f8468010000"
PATCHED="83fd020f8668010000"

# Original Playback binary investigated/tested
KNOWN_SHA256="372684bbb5dd180fcb018270b1fe3274df578108600da1f0cf959e63ab28e94b"

echo "Epilogue Playback Linux SIGSEGV Workaround"
echo "=========================================="
echo

if [ ! -f "$PLAYBACK" ]; then
    echo "ERROR: Playback binary not found:"
    echo "  $PLAYBACK"
    echo
    echo "Usage:"
    echo "  $0 /path/to/Playback"
    exit 1
fi

echo "Playback binary:"
echo "  $PLAYBACK"
echo

SHA256=$(sha256sum "$PLAYBACK" | awk '{print $1}')

echo "SHA-256:"
echo "  $SHA256"
echo

if [ "$SHA256" = "$KNOWN_SHA256" ]; then
    echo "Known tested Playback binary detected."
else
    echo "WARNING: SHA-256 does not match the tested binary."
    echo "The byte sequence will still be checked before patching."
fi

echo

CURRENT=$(xxd -p -l 9 -s "$OFFSET" "$PLAYBACK")

echo "Bytes at patch location 0x32929f:"
echo "  $CURRENT"
echo

if [ "$CURRENT" = "$PATCHED" ]; then
    echo "Playback is already patched."
    exit 0
fi

if [ "$CURRENT" != "$EXPECTED" ]; then
    echo "ERROR: Unexpected machine code at patch location."
    echo
    echo "Expected:"
    echo "  $EXPECTED"
    echo
    echo "Found:"
    echo "  $CURRENT"
    echo
    echo "This is probably a different Playback build."
    echo "No changes were made."
    exit 1
fi

BACKUP="${PLAYBACK}.backup"

if [ -e "$BACKUP" ]; then
    echo "ERROR: Backup already exists:"
    echo "  $BACKUP"
    echo
    echo "Move/remove the existing backup before applying the patch."
    exit 1
fi

echo "Creating backup:"
echo "  $BACKUP"

cp --preserve=all "$PLAYBACK" "$BACKUP"

echo
echo "Applying patch..."

printf '\x83\xfd\x02\x0f\x86' | \
    dd of="$PLAYBACK" \
       bs=1 \
       seek="$OFFSET" \
       conv=notrunc \
       status=none

echo "Verifying..."

CURRENT=$(xxd -p -l 9 -s "$OFFSET" "$PLAYBACK")

if [ "$CURRENT" != "$PATCHED" ]; then
    echo
    echo "ERROR: Verification failed."
    echo "Restoring original binary..."

    cp --preserve=all "$BACKUP" "$PLAYBACK"

    exit 1
fi

echo
echo "SUCCESS!"
echo
echo "Playback has been patched."
echo
echo "Original:"
echo "  $BACKUP"
echo
echo "Patched:"
echo "  $PLAYBACK"
echo
echo "Patched bytes:"
echo "  $CURRENT"
