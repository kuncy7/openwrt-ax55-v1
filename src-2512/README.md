# Archer AX55 v1 — patch dla openwrt-25.12

Zawartość katalogu:
- `ax55-v1-openwrt-2512-full.patch` — jeden scalony patch, czysto
  tekstowy (bez sekcji binarnych); baza w
  momencie eksportu: `ab08f6a524` na `openwrt-25.12`.
- `board-tplink_ax55v1.ipq5018`, `board-tplink_ax55v1.qcn6122` —
  binaria BDF (osobno, poza patchem).

Instalacja (UWAGA: uzyj `git apply`, nie `patch -p1`):

    git apply --check ax55-v1-openwrt-2512-full.patch   # proba na sucho
    git apply ax55-v1-openwrt-2512-full.patch
    mkdir -p package/firmware/ipq-wifi/files
    cp board-tplink_ax55v1.* package/firmware/ipq-wifi/files/

Dlaczego `git apply`: jest atomowy - przy niepasujacym kontekscie
przerywa z bledem. `patch -p1` odrzuca pojedynczy hunk do `.rej`
i idzie dalej, wiec build sie *uda*, ale np. bez symboli DWMAC -
efekt: brak `eth0`, a w konsekwencji `rtl8365mb: unable to register
switch` (DSA nie ma conduitu). Jesli mimo wszystko uzywasz `patch`,
sprawdz potem: `find . -name '*.rej'`.

Weryfikacja PRZED flashem - w zbudowanym kernelu musza byc:

    grep -E "CONFIG_(DWMAC_IPQ5018|PCS_QCA_UNIPHY|STMMAC_ETH)" \
        build_dir/target-*/linux-qualcommax_ipq50xx/linux-6.12.*/.config

Szybka kontrola GOTOWEGO OBRAZU (bez flashowania) - rozpakowuje jadro
z sysupgrade.bin i sprawdza, czy sterownik tam jest:

    ./check-image-dwmac.sh <plik-sysupgrade.bin>

Musi wypisac OBECNY dla `ipq5018-gmac-dwmac` i `stmmaceth`. Jesli
wypisze BRAK - sterownik nie zostal skompilowany i ethernet nie
zadziala, niezaleznie od DTS.

Patch dodaje w Makefile ipq-wifi kopiowanie `files/*` do build dir
i pozycje `tplink_ax55v1` w ALLWIFIBOARDS - pliki podlozone jak wyzej
trafia do pakietu `ipq-wifi-tplink_ax55v1`.

md5 binariów:
    b541dc294dba577d720d8d88e5940fc8  board-tplink_ax55v1.ipq5018
    30deb3062b590e48e4fb6e9084d2a488  board-tplink_ax55v1.qcn6122

Uwagi:
- BDF-y są obowiązkowe: bez nich 2.4 GHz ma głuchy odbiornik
  (-86 dBm zamiast -42). Wersja z 21.07.2026 uzupełnia dodatkowo
  wyzerowane tablice mocy — bez tego firmware ograniczał oba pasma
  do 13 dBm zamiast 20 (2.4 GHz) i 23 (5 GHz). Docelowo wejdą przez
  firmware_qca-wireless (PR #143) - wtedy zwykły bump ipq-wifi zamiast
  plików w files/.
- Overclock 1.296 GHz NIE wchodzi (dokładany na poziomie buildera).
- Katalog `src/` w korzeniu repo to wariant mainline (PR #24197) —
  nie aplikuje się na 25.12; do 25.12 służy wyłącznie ten katalog.
- DWMAC i qca-nss-dp to konkurencyjne stosy ethernetowe - dla AX55 v1
  musi byc DWMAC, dlatego w DEVICE_PACKAGES jest `-kmod-qca-nss-dp`.
- Znany otwarty temat: sporadyczna degradacja trunku przy pierwszym
  boocie po wielogodzinnym wyłączeniu (badana na netdev; możliwa
  przyczyna sprzętowa egzemplarza). Reboot leczy.
