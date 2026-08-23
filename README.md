# OpenLogi Control dla Omarchy 4.0

<p align="center">
  <strong>Nowoczesny plugin do Omarchy 4.0 dla urządzeń Logitech MX z pełnym wsparciem dla OpenLogi, Smart Ring (Action Ring) oraz gestów.</strong>
</p>

---

## 🌟 Dlaczego OpenLogi zamiast Solaar?

W tradycyjnym `solaar` przycisk **Smart Ring / Action Ring** (np. w myszkach MX Master 3, MX Master 3S, MX Master 4) często nie jest poprawnie wykrywany jako fizyczny przycisk ani nie wspiera pełnych gestów pod Waylandem/Hyprlandem. 

**OpenLogi** ([github.com/AprilNEA/OpenLogi](https://github.com/AprilNEA/OpenLogi)) to nowoczesna, napisana w Ruście alternatywa dla Logi Options+, która natywnie i sprzętowo obsługuje:
- **Smart Ring (Action Ring)**: Radialne koło akcji z **8 slotami** (`Góra`, `Prawy-Góra`, `Prawo`, `Prawy-Dół`, `Dół`, `Lewy-Dół`, `Lewo`, `Lewy-Góra`).
- **5-kierunkowe Gesty**: Niezależne akcje dla przeciągnięcia w górę, dół, lewo, prawo oraz pojedynczego kliknięcia.
- **Haptykę**: Sprzężenie zwrotne przy nawigacji po Smart Ring.
- **Pełne DPI**: Płynna regulacja do 8000 DPI (krok 50 DPI) + szybkie presety.
- **SmartShift**: Przełączanie trybu zapadkowego i płynnego kółka z regulacją progu czułości.
- **Płynne Przewijanie (Hi-Res)** & Odwracanie osi Y i rolki kciuka.
- **Klawiatury MX**: Podświetlenie, zamiana klawiszy Fn, blokady Caps/Win.
- **Zero Telemetrii i Chmury**: 100% lokalna konfiguracja w formacie `~/.config/openlogi/config.toml`.

---

## 🚀 Instalacja

### 1. Dodanie pluginu do Omarchy 4.0

```bash
omarchy plugin add /home/bartek/.gemini/antigravity/scratch/omarchy-openlogi --enable
```
*(lub ze zdalnego repozytorium po opublikowaniu)*:
```bash
omarchy plugin add https://github.com/twoj-login/omarchy-openlogi.git --enable
```

### 2. Instalacja OpenLogi (opcjonalna, zalecana)

Jeśli nie masz jeszcze zainstalowanego OpenLogi na Arch Linux:
```bash
# Instalacja z AUR lub budowa z repozytorium OpenLogi
cargo install --git https://github.com/AprilNEA/OpenLogi.git openlogi-cli
```

### 3. Przeładowanie powłoki Omarchy

```bash
omarchy restart shell
```

---

## 🎮 Użycie

| Akcja | Opis |
| :--- | :--- |
| **Lewy klik na ikonie paska** | Otwiera podręczne menu popover (DPI, SmartShift, stan baterii, Smart Ring). |
| **Prawy klik na ikonie paska** | Wymusza natychmiastowe odświeżenie stanu urządzeń z pominięciem pamięci podręcznej. |
| **Przycisk "All Settings"** | Otwiera pełne okno konfiguracji ze schematem 8 slotów Smart Ring i mapowaniem przycisków. |
| **Przycisk Smart Ring na myszy** | Otwiera radialne menu na ekranie (`ActionRingOverlay.qml`). |

### Sterowanie z terminala (Omarchy IPC)

```bash
# Otwarcie pełnego okna ustawień Smart Ring
omarchy-shell shell summon io.openlogi.omarchy '{}'

# Pokazanie / ukrycie panelu paska
omarchy-shell ipc io.openlogi.omarchy toggle
```

---

## ⚙️ Struktura Plików Pluginu

- `manifest.json` – Manifest kompatybilny z Omarchy 4.0 / Quattro (punkty wejścia dla paska, usługi, okna ustawień i nakładki).
- `BarWidget.qml` – Wskaźnik na górnym pasku Omarchy z ikoną stanu baterii i połączenia.
- `Panel.qml` – Podręczne menu z suwakami DPI, SmartShift i szybkimi przełącznikami.
- `OpenLogiSettings.qml` – Pełny panel z interaktywnym wizualizatorem 8 slotów Action Ring i edytorem gestów.
- `ActionRingOverlay.qml` – Radialna nakładka HUD na ekranie dla Smart Ring.
- `OpenLogiIcon.qml` – Wektorowa ikona myszy/klawiatury MX.
- `Service.qml` – Singleton usługi działający w procesie `omarchy-shell`.
- `Model.js` – Logika danych, mapowanie akcji, slotów i kolorów.
- `openlogictl.py` – Backend komunikujący się z `openlogi` oraz czytający/zapisujący `~/.config/openlogi/config.toml`.
- `test/` – Testy jednostkowe weryfikujące działanie parsera i kolejki poleceń.

---

## 📜 Licencja

Wtyczka wydana na licencji **MIT**. Kompatybilna z OpenLogi i Omarchy 4.0.
