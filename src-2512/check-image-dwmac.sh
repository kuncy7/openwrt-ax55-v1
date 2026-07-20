#!/bin/sh
# Sprawdza, czy obraz sysupgrade zawiera sterownik DWMAC (bez flashowania).
# Uzycie: ./check-image-dwmac.sh <plik-sysupgrade.bin>
[ -f "$1" ] || { echo "podaj plik sysupgrade"; exit 1; }
T=$(mktemp -d); tar xf "$1" -C "$T" 2>/dev/null || { echo "to nie jest obraz sysupgrade (tar)"; exit 1; }
K=$(find "$T" -name kernel | head -1)
[ -n "$K" ] || { echo "brak jadra w obrazie"; exit 1; }
python3 - "$K" <<'PY'
import sys,lzma
d=open(sys.argv[1],'rb').read()
for i in range(len(d)-16):
    if d[i]==0x6d and d[i+1]==0 and d[i+2]==0 and d[i+3]==0x80:
        try:
            out=lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(d[i:])
            if len(out)>4000000:
                open(sys.argv[1]+".raw","wb").write(out); break
        except Exception: pass
PY
R="$K.raw"
[ -f "$R" ] || { echo "nie udalo sie rozpakowac jadra"; rm -rf "$T"; exit 1; }
echo "--- sterowniki w jadrze obrazu ---"
OK=1
for s in ipq5018-gmac-dwmac stmmaceth; do
    n=$(strings -a "$R" | grep -c "$s")
    [ "$n" -gt 0 ] || OK=0
    printf "  %-20s %s\n" "$s" "$([ "$n" -gt 0 ] && echo OBECNY || echo BRAK)"
done
rm -rf "$T"
[ "$OK" = 1 ] && echo ">>> OK - ethernet powinien dzialac" || echo ">>> ZLE - brak sterownika DWMAC, ethernet NIE zadziala"
