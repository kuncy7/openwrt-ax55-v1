# Archer AX55 v1 — pełny patch dla openwrt-25.12 (eko.one.pl)

Jeden scalony patch `ax55-v1-openwrt-2512-full.patch` na gałąź
`openwrt-25.12` (baza w momencie eksportu: `ab08f6a524`
"mac80211: ath9k: call reset on init").

Aplikacja (WYMAGA git apply, patch zawiera delty binarne BDF):

    git apply --check ax55-v1-openwrt-2512-full.patch   # próba na sucho
    git apply ax55-v1-openwrt-2512-full.patch

Zawartość (odpowiednik 28 commitów gałęzi ax55-2512):
- prerekwizyty z main (w main zmergowane przez #22381): backport PCS
  standalone, CLK recalc-rate, sterownik UNIPHY PCS, IPQ5018 DWMAC;
- wsparcie AX55 v1: DTS, obrazy, sysupgrade (dual-boot), USB (HS+SS),
  LED-y/przyciski, fabryczne MAC-i z tp_data (wzorzec board.d jak AX80: preinit mount + get_mac_binary, WiFi przez 11-ath11k-caldata, eth0 przypięty przez board.json);
- retarget patcha rtl8365mb (SGMII/HSGMII) na niepodzielony sterownik
  25.12 + poprawka nazw zegarów UNIPHY pod GCC 25.12;
- **fix BDF** (binarny): bez niego 2.4 GHz ma głuchy odbiornik
  (-86 dBm zamiast -42, przepustowość ~0).

Uwagi:
- Overclock 1.296 GHz NIE wchodzi (dokładany na poziomie buildera).
- Katalog `src/` w korzeniu repo to wariant mainline (PR #24197) —
  NIE aplikuje się na 25.12; do 25.12 służy wyłącznie ten katalog.
- Znany otwarty temat: sporadyczna degradacja trunku przy pierwszym
  boocie po wielogodzinnym wyłączeniu (badana na netdev; możliwa
  przyczyna sprzętowa egzemplarza). Nie blokuje normalnego użycia —
  reboot leczy.
