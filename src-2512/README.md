# Archer AX55 v1 — patch dla openwrt-25.12 (eko.one.pl)

Zawartość katalogu:
- `ax55-v1-openwrt-2512-full.patch` — jeden scalony patch, czysto
  tekstowy (aplikuje się i `git apply`, i `patch -p1`); baza w
  momencie eksportu: `ab08f6a524` na `openwrt-25.12`.
- `board-tplink_ax55v1.ipq5018`, `board-tplink_ax55v1.qcn6122` —
  binaria BDF (osobno, poza patchem).

Instalacja:

    git apply ax55-v1-openwrt-2512-full.patch        # lub patch -p1
    mkdir -p package/firmware/ipq-wifi/files
    cp board-tplink_ax55v1.* package/firmware/ipq-wifi/files/

Patch dodaje w Makefile ipq-wifi kopiowanie `files/*` do build dir
i pozycję `tplink_ax55v1` w ALLWIFIBOARDS — pliki podłożone jak wyżej
trafią do pakietu `ipq-wifi-tplink_ax55v1`.

md5 binariów:
    1727903fb83a987388faef60c7307d0c  board-tplink_ax55v1.ipq5018
    218eff8dd33789a973d123bc68c2b4ac  board-tplink_ax55v1.qcn6122

Uwagi:
- BDF-y są obowiązkowe: bez nich 2.4 GHz ma głuchy odbiornik
  (-86 dBm zamiast -42). Docelowo wejdą przez firmware_qca-wireless
  (PR #143) - wtedy zwykły bump ipq-wifi zamiast plików w files/.
- Overclock 1.296 GHz NIE wchodzi (dokładany na poziomie buildera).
- Katalog `src/` w korzeniu repo to wariant mainline (PR #24197) —
  nie aplikuje się na 25.12; do 25.12 służy wyłącznie ten katalog.
- Znany otwarty temat: sporadyczna degradacja trunku przy pierwszym
  boocie po wielogodzinnym wyłączeniu (badana na netdev; możliwa
  przyczyna sprzętowa egzemplarza). Reboot leczy.
