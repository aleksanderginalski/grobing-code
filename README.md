# grobing-code

Kod aplikacji **Grobing** (Flutter, Android, local-first). Projekt powstał świeżym `flutter create`
na przypiętej wersji SDK (ISSUE-002), **nie** jako kopia innego projektu.

- Agenci i reguły: `../grobing-agents/` (tam otwierasz sesje, `/pm`).
- Dokumentacja i decyzje: `../grobing-vault/`.
- ⚠️ **Żadnych danych rodziny w tym repo** — ani bazy, ani kopii, ani eksportów, ani zdjęć prawdziwych
  osób. Dane żyją w aplikacji na telefonie. `.gitignore` obok to pierwsza linia obrony, nie jedyna.

## Wersja Fluttera — przypięta

Flutter na tej maszynie jest **współdzielony z inną, wydaną aplikacją autora**, więc globalnego SDK
się nie aktualizuje bez decyzji (ADR-002).

- **Jeden sposób:** `pubspec.yaml` → `environment.flutter: 3.41.1`. Każde `flutter pub get`
  (a więc `run`, `test`, `build`) na innej wersji **odmawia** z komunikatem
  *„Because grobing requires Flutter SDK version 3.41.1, version solving failed."*
- Zadeklarowana wartość żyje w `../grobing-agents/.claude/rules/project-config.example.md`
  (`flutter_version_pinned`). **Zmiana wersji = obie linie w jednej paczce** + datowana linia w ADR-002.
- Czego to nie daje: dwóch wersji obok siebie. Gdy druga aplikacja będzie potrzebowała nowszego
  Fluttera, ten projekt przestanie się budować — wtedy decyzja: podbić wersję albo dołożyć menedżer
  wersji (FVM).

## Uruchomienie

```sh
flutter pub get
flutter analyze
flutter test
flutter run            # debug — emulator albo telefon testowy
```

## Testy

`flutter test` uruchamia wszystko. Testy ekranów, które czytają bazę `drift`, mają trzy pułapki. Żadna nie daje
błędu — przebieg **wisi bez końca** (ISSUE-014, ISSUE-012):

- **Strumień drift i fałszywy zegar.** Test widżetu biegnie w fałszywym czasie, a drift zamyka zapytanie
  strumieniowe na timerze w tym czasie. `db.close()` w `tester.runAsync` przy wciąż podpiętym ekranie czeka na
  timer, który nie ruszy. Przed zamknięciem bazy zdejmij ekran:
  `await tester.pumpWidget(const SizedBox()); await tester.pump(const Duration(seconds: 1));`.
- **Zapis albo odczyt bazy w `tester.runAsync` przy podpiętym ekranie.** Strumień ekranu ponawia zapytanie w
  strefie fałszywego zegara i trzyma blokadę bazy, więc `runAsync` wisi. Wzorzec `leaveScreen`
  (`test/app/grave/grave_screens_test.dart`): ekran zdjęty jak wyżej → `runAsync` z zapisem → ekran podpięty od
  nowa.
- **Czekanie na pliki i bazę.** Biegną w prawdziwym czasie, a `pumpAndSettle` na nie nie czeka. Wzorzec
  `_pumpUntil` w testach ekranów: na zmianę `runAsync(() => Future.delayed(10 ms))` i `pump(50 ms)`, aż warunek
  się spełni (z limitem, po którym test pada).

Po przerwanym albo zawieszonym przebiegu:

- następny `flutter test` może paść na **zablokowanym `sqlite3.dll`**. Plik trzyma najpewniej proces testów z
  poprzedniego przebiegu (`flutter_tester.exe` w Menedżerze zadań) — zamknij go i uruchom testy ponownie;
- Flutter zapisuje wtedy **`flutter_01.log` w korzeniu repo**. `.gitignore` go pomija (`*.log`); można usunąć.

## Baza danych

SQLite przez `drift` (ADR-005 w vaulcie). Paczka `sqlite3` **dołącza własny SQLite** (build hooks), więc
`VACUUM INTO`, na którym stoi kopia (ADR-004), nie zależy od wersji Androida. Przy pierwszym budowaniu
hook pobiera gotową bibliotekę z wydań `sqlite3.dart` na GitHubie i sprawdza jej SHA-256 zapisane w
paczce. Później korzysta z `.dart_tool/`, więc build offline działa dopiero po pierwszym udanym buildzie.

- **Gdzie leży:** `grobing.db` i katalog `media/` w katalogu wsparcia aplikacji (prywatny magazyn,
  `path_provider`). Schemat: `lib/data/database.dart`.
- **`drift` i `drift_dev` są przypięte parą** (`pubspec.yaml`, komentarz): przypięty Flutter trzyma
  `analyzer` na 10.x. Zmiana jednej bez drugiej psuje generowanie kodu i weryfikator migracji.
- **Po każdej zmianie tabel:**

  ```sh
  dart run build_runner build --delete-conflicting-outputs   # database.g.dart
  ```

  Pliki `*.g.dart` commitujesz razem ze zmianą.
- **Zmiana schematu = migracja, nigdy „usuń i stwórz od nowa”** (NFR-003):
  1. podbij `schemaVersion` w `GrobingDatabase`;
  2. `dart run drift_dev make-migrations`: zapisuje schemat nowej wersji w `drift_schemas/grobing/`
     i generuje testy migracji w `test/drift/grobing/`;
  3. dopisz krok w `onUpgrade` i uruchom testy.

  Wersja bez kroku migracji kończy się błędem przy otwarciu bazy, zamiast skasować dane. Wszystkie
  kroki i `user_version` idą w jednej transakcji: przerwana aktualizacja zostawia starą wersję całą.
  **Krok dodaje i przebudowuje, ale nie usuwa tabel ani wierszy:** odtworzenie starszej kopii sprawdza
  po migracji każdą tabelę z jej manifestu i liczbę wierszy (`lib/backup/restore_service.dart`).
- **Twierdzenia (schemat v2, ADR-006 w vaulcie).** Wartość żyje w wierszu `events` (data z dopiskiem)
  albo `burials` (grób), a tabela `assertions` mówi, kto ją podał i jak mocna jest: rodzaj źródła,
  opcjonalny szczegół, status, kiedy zapisane. Tak jak w GEDCOM 7:
  - sprzeczna wartość z innego źródła to **osobny wiersz** z własnym twierdzeniem, nigdy nadpisanie;
  - pokazuje się **pierwszy** wiersz (najniższe `id`);
  - **każdy wiersz `events` i `burials` ma co najmniej jedno twierdzenie.** Dlatego zapisuje się je
    przez `lib/data/claims.dart`, w jednej transakcji z twierdzeniem. Wiersze z v1 dostały przy migracji
    twierdzenie „notatki, przeniesione z v1”.
- **Nazwa grobu (schemat v3, ISSUE-012).** Opcjonalna kolumna `graves.name`: tytuł, który nadaje autor
  („Grób rodzinny Nowaków”). Aplikacja nigdy nie wylicza jej z nazwisk. Migracja v2→v3 tylko dodaje
  kolumnę (`addColumn`). Start aplikacji pyta o kopię w tle dopiero **po otwarciu bazy**, czyli po
  migracji (`lib/main.dart`, retro 1 R6): migracja zmienia plik, a nie zgłasza zmian do `tableUpdates()`.
- **Zdjęcia osób jako łącza (schemat v4, ISSUE-017).** Nowa tabela `person_media` (osoba, zdjęcie, pozycja), a
  `media` traci `person_id` i warunek „osoba albo grób”. Migracja v3→v4 przenosi zdjęcia osób z v3 do łączy w
  kolejności `id` i przebudowuje `media` (`TableMigration`): wiersze i `id` zostają, więc odtworzenie kopii v3
  przechodzi sprawdzenie liczby wierszy. Na końcu `PRAGMA foreign_key_check` — klucze obce są w migracji
  wyłączone (`beforeOpen` włącza je po niej). Szczegóły: *Zdjęcia* niżej.
- **Kadr profilowego (schemat v5, ISSUE-018).** Łącze `person_media` ma cztery opcjonalne kolumny kadru
  (`crop_left`, `crop_top`, `crop_width`, `crop_height`) — `CROP` z GEDCOM 7, w pikselach pliku zdjęcia. Plik to
  kopia dostępowa: obrócona przed zapisem, bez EXIF i nigdy nie zmieniana w miejscu, więc piksele kadru się nie
  przesuwają. Kadr należy do łącza, więc każda osoba na zdjęciu grupowym ma własny. Wszystkie cztery puste =
  bez kadru: okrąg pokazuje środek, jak przed v5. Migracja v4→v5 tylko dodaje kolumny (`addColumn`).
  **Kadr przeżywa każdą edycję zdjęć osoby:** `applyPersonPhotoEdits` przepisuje łącza od nowa, więc najpierw
  czyta ich kadry i zapisuje je z powrotem, chyba że edycja ustawiła nowy. Granicę obrazu pilnuje ekran kadru
  (`lib/app/photo/crop_geometry.dart`), bo wymiarów zdjęcia nie ma w bazie; okrąg i tak przycina kadr do
  obrazu.
- **Rodzina (schemat v6, ISSUE-019, ADR-011 w vaulcie).** Rodzina to związek (małżeństwo albo nie) z dziećmi:
  1–2 osoby w parze, ślub i koniec jako zdarzenia rodziny. Osoba w kilku związkach jest w kilku rodzinach.
  - **Twierdzenie o relacji stoi przy rodzinie (związek pary) i przy łączu każdego dziecka**, nie przy partnerze.
    GEDCOM 7 cytuje źródło przy `FAM`, a Gramps przy łączu dziecka (`ChildRef`). `family_children` ma więc `id`, a
    `assertions` cytuje dokładnie jedno: zdarzenie, pochówek, rodzinę albo łącze dziecka (`CHECK`).
  - **Zapis i usuwanie rodziny** (`lib/data/families.dart` → `saveFamily`, `deleteFamily`) to jedna transakcja.
    Te same reguły co na ekranie: 1–2 osoby w parze, co najmniej dwie osoby, nikt dwa razy, dziecko w jednej
    rodzinie rodziców.
  - **Migracja v5→v6 nie dopisuje wierszy:** przebudowuje `family_children` (stary `rowid` to `id`) i `assertions`
    (`TableMigration`). Dopisanie twierdzeń do rodzin sprzed v6 zmieniłoby liczbę wierszy `assertions` i
    odtworzenie każdej kopii v5 z rodzinami by odmówiło. Rodziny przed v6 pisały tylko wymyślone dane debug, a
    twierdzenie dostają przy pierwszym zapisie w arkuszu rodziny.
  - **Dzieci według daty urodzenia** (GEDCOM 7: *„chronological by birth”*), bez daty na końcu; związki osoby
    według pierwszej daty związku (od v7: „Razem od”, a bez niej ślub).
- **Płeć i oś czasu związku (schemat v7, ISSUE-025).** Kolumna `persons.sex` (`female` / `male`, pusta = nieznana —
  `U` w GEDCOM 7); formularz podpowiada ją z imienia, baza nigdy. Związek to oś czasu z trzech zdarzeń rodziny:
  `together` („Razem od”, nowy typ — GEDCOM nie ma na to znacznika, eksport jako `EVEN` z `TYPE`), `marriage` i `end`.
  **Ślub albo koniec bez daty to zdarzenie bez daty** (`MARR Y` w GEDCOM 7: „wiadomo, że było”) — z twierdzeniem jak
  każde inne. `saveFamily` dostaje `married` / `ended` obok dat: bez nich decyduje sama data, jak przed v7. Migracja
  v6→v7 tylko dodaje kolumnę (`addColumn`); nowy typ zdarzenia nie potrzebuje kroku, bo typ jest zapisany nazwą, bez
  `CHECK` na wartościach. Osoby sprzed v7 nie mają płci, a rodziny bez ślubu są „Razem”.
- **Tło osoby (schemat v8, ISSUE-024).** Kolumna `person_media.is_background` — zdjęcie za portretem w widoku osoby,
  znacznik przy łączu jak kadr. Częściowy indeks unikalny `person_media_background` (`WHERE is_background`) pozwala na
  jedno tło na osobę. GEDCOM 7 zna przy łączu tylko `CROP` i `TITL`, więc to rozszerzenie aplikacji. Łącza osoby
  przepisuje od zera `applyPersonPhotoEdits`: tło, jak kadr, czyta przed skasowaniem i oddaje, a łącze usunięte (także
  przez „Kto jest na zdjęciu?”) zabiera tło ze sobą. Migracja v7→v8 dodaje kolumnę z domyślnym `false` i indeks — bez
  nowych wierszy, więc kopia v7 odtwarza się bez tła.
- **Zdjęcie cmentarza (schemat v9, ISSUE-023).** Kolumna `media.cemetery_id` — wiersz zdjęcia wskazuje cmentarz tak jak
  zdjęcie nagrobka wskazuje grób (`grave_id`); pliki w `media/cmentarze/<id>/`. Jedno zdjęcie na cmentarz pilnuje jedna
  droga zapisu (`lib/data/photos.dart` → `setCemeteryPhoto`), wspólna z nagrobkiem: plik przed wierszem, usunięcie zdejmuje
  tylko wiersz. **Pułapka:** `applyPersonPhotoEdits` sprząta wiersze `media` bez właściciela — warunek obejmuje grób,
  cmentarz i łącze osoby; bez cmentarza każde „Zapisz” przy zdjęciach osoby kasowałoby zdjęcia cmentarzy. Migracja v8→v9
  tylko dodaje kolumnę (`addColumn`), więc kopia v8 odtwarza się z cmentarzami bez zdjęć.
- **Plan cmentarza (schemat v10, ISSUE-027, ADR-015 w vaulcie).** Tabela `cemetery_plans`: jeden wiersz na cmentarz,
  status (`ok` albo `notInOsm` — OpenStreetMap nie ma obrysu przy punkcie), obrys i alejki jako JSON samych współrzędnych
  (bez nazw i znaczników OSM, `lib/data/cemetery_plans.dart`), czas pobrania i serwer. Brak wiersza = plan jeszcze nie
  pobrany. **Nowy punkt cmentarza kasuje jego plan** w tej samej transakcji (`updateCemetery`), bo obrys wybiera punkt.
  Plan jest w bazie, więc wchodzi do kopii i odcisku bez zmian w kodzie kopii (tabele z `sqlite_master`). Migracja v9→v10
  to sam `createTable`: kopia v9 odtwarza się bez planów, a plany pobierają się, gdy telefon ma internet.
- **Kwatery (schemat v11, ISSUE-028, ADR-016 w vaulcie).** Tabela `sectors`: kwatera cmentarza z nazwą (bez słowa
  „Kwatera”), kluczem nazwy (bez wielkości liter i polskich znaków, unikalnym na cmentarzu — „b” i „B” to jedna kwatera)
  i strefą zaznaczoną przez autora (JSON pierścienia, pusta = kwatera tylko w adresach). Grób wskazuje kwaterę
  (`graves.sector_id`) zamiast trzymać tekst, więc zmiana nazwy kwatery zmienia adresy wszystkich jej grobów. Normalizacja
  nazwy jest w jednym miejscu (`lib/data/address_text.dart`) dla okien, zapisu i migracji. Kwatera bez strefy i bez grobów
  znika w tej samej transakcji (`dropSectorIfUnused`). Kwatery są osobno od planu, bo plan kasuje się przy zmianie punktu.
  Migracja v10→v11 zamienia tekst kwatery na wiersze `sectors` i przebudowuje `graves` bez kolumny tekstu — liczba grobów
  się nie zmienia, więc kopia v10 odtwarza się w v11.
- **Pinezka grobu (schemat v12, ISSUE-029).** `graves.lat`/`lon` (od v1), skąd pozycja (`position_source`: `gps` — telefon
  przy grobie, `plan` albo `satellite` — ręka autora na planie albo na zdjęciu z góry), dokładność telefonu w metrach (tylko
  `gps`) i data zapisu (`position_recorded_at`, od v12). Zapis: `setGravePin` w `lib/data/graves.dart`. Migracja v11→v12 to
  jedna kolumna — pinezki sprzed v12 (tylko wymyślone) zostają bez daty. Wartość `plan` nie potrzebowała kroku, bo źródło
  jest zapisane nazwą.
- **Miejsca zamieszkania (schemat v13, ISSUE-042, ADR-020 w vaulcie).** Tabela `residences`: osoba, okres „od – do” (każdy
  koniec z dopiskiem `exact`/`about` albo pusty — `RESI` z `FROM … TO …` w GEDCOM 7), poziom miejsca (`country` · `locality` ·
  `address`) i samo miejsce **słowami w wierszu**: nazwa dziś, jednostka, kraj (kod i nazwa), punkt, id z GeoNames, opcjonalnie
  nazwa z tamtego czasu i adres (tekst, punkt zostaje w środku miejscowości). Kopia czyta się więc bez listy miejsc z
  aplikacji. Zapis razem z „Zapisz” wpisu, w jego transakcji (`lib/data/residences.dart` → `writeResidences` przez
  `AlsoWrite`). Migracja v12→v13 to `createTable` z indeksem — kopia v12 odtwarza się z osobami bez zamieszkań.
- **Opłata za grób (schemat v14, ISSUE-043).** `graves.paid_until_year` / `_month` / `_day`: data „opłacone do”, taka jak na
  naklejce albo pokwitowaniu (rok, miesiąc albo dzień), bez dopisku — jak daty zamieszkań. Pusta znaczy „nie wiadomo”. Liczby, nie
  tekst, żeby przypomnienie mogło później wyliczyć najbliższy termin. Pole w oknie „Popraw grób” przyjmuje lata do bieżącego + 50,
  a daty osoby dalej nie przyjmują przyszłości (`lib/app/dates.dart` → `readPaidUntil`). Zapis: `setGraveDetails` razem z nazwą i
  adresem, w jednej transakcji. Migracja v13→v14 to trzy kolumny — kopia v13 odtwarza się z grobami bez daty opłaty.
- **Rody i wieńce (schemat v15, ISSUE-044, ADR-021).** Tabela `clans` (nazwa, klucz wzoru, klucz koloru) i przy osobie tylko
  **wybór**: `persons.clan_id` (ród wybrany u szczytu linii albo wyjątek) i `persons.no_wreath` („bez wieńca”). Wieniec każdej osoby
  liczy się przy odczycie z drzewa (`lib/data/wreaths.dart`): po ojcu, a kobieta po ślubie ma pół wieńca rodu męża z ostatniego
  małżeństwa. Nazwa rodu jest unikalna bez wielkości liter i polskich znaków (`lib/data/clans.dart`, przez `fold`). Wybór i ród
  zapisują się od razu, jak „Rodzina”. Migracja v14→v15 to nowa tabela i dwie kolumny — kopia v14 odtwarza się bez rodów.
- **Zapis osoby w grobie** (`lib/data/graves.dart`) to jedna transakcja: grób (przy nowym), osoba,
  pochówek i daty, każde z twierdzeniem „notatki”, a od v4 także zmiany jej zdjęć. Błąd w środku nie zostawia
  „pół osoby”.
- **Odcisk danych** (ekran „Stan danych”, `lib/data/data_state.dart`) jest miarą dla kopii i
  odtworzenia (NFR-002). Liczy się z **treści**, nie z pliku: tabele po nazwie, wiersze po wszystkich
  kolumnach, wartości w stałym kodowaniu, potem pliki zdjęć po ścieżce. `VACUUM INTO` go nie zmienia.
  **Zmiana tej definicji unieważnia wszystkie wcześniej zapisane odciski.**
- **Wymyślone dane** (`lib/dev/`) są dostępne tylko w buildzie debug: przycisk na ekranie „Stan danych”.
  W buildzie release tego kodu nie ma. Wymyślone cmentarze mają wymyślone punkty w Polsce: partie 1 i 2
  stoją w jednym miejscu (znicz z liczbą), co trzecia partia jest bez punktu. Drugi przycisk, **„Wymyślone pinezki na
  planach”**, stawia wymyślone pinezki grobom na cmentarzach z pobranym planem (co trzeci grób zostaje bez), po kolei z
  każdym źródłem pinezki (GPS, plan, zdjęcie z góry).

## Mapa

Ekran główny to mapa Polski (ISSUE-014, ADR-007 w vaulcie), od ISSUE-023 jak R1: sąsiedzi, Bałtyk, jeziora, rzeki,
„Polska” i 11 miast. **Bez warstwy kafelków i bez sieci:** wszystko jest w aplikacji, w `assets/map/poland.json`
(ok. 300 KB).
- **Źródło:** [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) 1:10m — domena
  publiczna, bez wymogu podpisu. Plik odtwarza `tool/map/extract_poland.dart` z siedmiu plików GeoJSON
  repozytorium [`nvkelso/natural-earth-vector`](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson)
  (lista i polecenie w nagłówku skryptu). Plików źródłowych nie ma w repo.
- **Co skrypt bierze:** kontur Polski bez uproszczenia; morze (ocean przycięty do prostokąta wokół Polski, wyspy jako
  dziury), jeziora (w Polsce od 8 km², za granicą od 40 km²) i granice sąsiadów — uproszczone (ok. 50 m przy Polsce,
  ok. 600 m dalej). **Prostokąt danych jest większy niż wszystko, co kamera pokaże** na telefonie trzymanym pionowo —
  inaczej morze kończyłoby się prostą linią. W pliku nie ma żadnych nazw poza 11 miastami (strażnik treści sprawdza
  plik przy `git add` jak każdy inny).
- **Tło mapy ma kolor sąsiadów**, więc szczeliny między uproszczonymi granicami a pełnym konturem Polski nie wychodzą.
- **Pułapka wydajności:** morze to jeden wielokąt z wyspami jako dziurami. Domyślne wypełnienie `flutter_map`
  (`Path.combine`) przy każdej klatce robi operację na ścieżce całego morza — 2–3 s na klatkę i ANR przy starcie
  (zmierzone w ISSUE-023). Warstwy wody mają więc `painterFillMethod: PolygonPainterFillMethod.evenOdd` (wyspy się nie
  przecinają, rysunek ten sam); test ekranu tego pilnuje.
- **Jazda mapy przy arkuszu** (`home_screen.dart`, D30): przy całej Polsce otwarcie arkusza przesuwa mapę w ok. 300 ms
  tak, że Polska stoi nad arkuszem, a zamknięcie wraca na środek; przy przybliżeniu — znicz nad arkuszem. Na emulatorze
  z oknem w tle zrzuty potrafią złapać stan pośredni (klatki przychodzą z opóźnieniem) — pozycję końcową sprawdza
  przełącznik „Usuń animacje” (`settings put global transition_animation_scale 0`), płynność — oko.
- **`flutter_map` 8.3.2 i `latlong2` 0.10.1 są przypięte dokładnie.** Paczka zależy od `http`, którego używa tylko warstwa
  kafelków — od ISSUE-027 zdjęcie z góry na mapie cmentarza (*Sieć* niżej). Mapa Polski dalej nie ma kafelków ani sieci.
- **Pułapka:** ruch mapy ogranicza `CameraConstraint.containCenter`, a nie `contain`. Na pionowym ekranie
  cała szerokość Polski daje widok wyższy niż Polska, więc „wszystkie krawędzie w granicach” nie da się
  spełnić i mapa jest pusta (zmierzone przy planie ISSUE-014).
- **Znicze, które nachodzą na siebie** (cel dotyku 48 dp), łączą się w jeden znicz z liczbą
  (`lib/app/home/pin_groups.dart`). Ikona znicza jest jedna na całą aplikację: `lib/app/widgets/candle.dart`.

### Mapa świata (mapa migracji)

Część „Mapa” zakładki Drzewo (ISSUE-045, `05_DESIGN/mapa-migracji.md` w vaulcie): kto gdzie mieszkał w roku z suwaka
drzewa. **Też bez kafelków i bez sieci:** kraje świata są w `assets/map/world.json` (ok. 510 KB, 182 kraje, ok. 35 tys.
punktów).
- **Źródło:** ten sam plik Natural Earth 1:10m co mapa Polski i lista miejsc — `ne_10m_admin_0_countries.geojson`. Plik
  odtwarza `dart run tool/map/extract_world.dart <katalog z plikiem>`: Douglas–Peucker 0,06° (ok. 6,7 km), wyspy od 0,15
  stopnia kwadratowego, bez Antarktydy, współrzędne do 3 miejsc. Przy każdym kraju kod (`ISO_A2_EH` — w `ISO_A2` Francja i
  Norwegia mają `-99`), polska nazwa i punkt nazwy — ten sam, który lista miejsc daje zamieszkaniu „cały kraj”.
- **Przybliżenie najwyżej do poziomu regionu** (zoom 7): bliżej uproszczona linia robi się kanciasta.
- **Kadr wybiera użytkownik** (R4): zmieniają go tylko palce i + / −; trzymany w pamięci, dopóki aplikacja działa
  (`migrationArea` w `lib/app/tree/migration_map.dart`), a nie w bazie.
- **Kto gdzie w roku** liczy czysta funkcja `lib/app/tree/migration_year.dart` — okna dat z drzewa (`TreeTime`) i koniec
  pobytu z następnego miejsca (`impliedEnds`, jak w widoku osoby).
- **Miejsca bliżej niż 44 dp na ekranie łączą się w jedno skupienie** (jak `Leaflet.markercluster`): do 3 twarzy, „+N” i podpis
  „5 miejsc”; dotknięcie przybliża do jego miejsc, a przy największym przybliżeniu rozsuwa. Podpisy nie nachodzą na siebie ani na
  okręgi — nazwy krajów ustępują pierwsze.
- **Pułapka wydajności:** przy ▶ ludzie ruszają się w każdej klatce, a nowy renderer nie trzyma pamięci podręcznej rastra, więc
  35 tys. punktów lądu było rysowanych od nowa w każdej klatce (22–26% wolnych klatek na emulatorze). Ląd jest dlatego **rysowany
  raz do obrazu**, gdy kamera stoi (`_LandLayer` w `migration_map.dart`), a z wektorów tylko w ruchu kamery. Z `FRAME_LOG` w logu
  widać `GROBING_MEASURE map land image`, gdy obraz powstał. `MapOptions` mapy powstają raz — nowe w każdym budowaniu ekranu drzewa
  kazały mapie budować warstwy od nowa.
- **Dane do sprawdzenia:** w „Stanie danych” (debug i profile) przycisk „Wymyślone miejsca zamieszkania” dokłada zamieszkania
  wymyślonej rodzinie z „Wymyślona rodzina do drzewa” (`lib/dev/fictional_residences.dart`).

## Mapa cmentarza i sieć

Od ISSUE-027 (ADR-003 w vaulcie) aplikacja ma uprawnienie `INTERNET` — **wyłącznie** do dwóch rzeczy:
- **plan cmentarza z OpenStreetMap**: obrys i alejki, pobierane raz i trzymane w bazie (`lib/net/overpass_plan_source.dart`,
  czyste funkcje w `lib/net/osm_plan.dart`). Zapytanie łączy `is_in` (obrys zawierający punkt — środek dużego cmentarza bywa
  dalej niż 300 m od krawędzi) z `around:300` (obrys obok punktu postawionego przy bramie). Wybór: największy obrys z punktem,
  inaczej najbliższy do 100 m, inaczej „brak w OSM”. Alejki: odcinek zostaje, gdy jego środek leży w obrysie;
- **zdjęcie z góry GUGiK** (WMTS `StandardResolution`, EPSG:3857, do z19), tylko na ekranie, **bez zapisu w telefonie**.

**Wszystkie adresy są w `lib/net/hosts.dart`**, tylko `https`. Nowy adres to decyzja autora, nie linia kodu (NFR-005: od
`INTERNET` własność „dane nie opuszczają telefonu” pilnuje kod, a nie system). Sprawdzenie na APK:
`aapt dump permissions build/app/outputs/flutter-apk/app-x86_64-release.apk` — z nowych tylko `INTERNET`.

- **Pułapka: `flutter_map` 8.3.2 domyślnie zapisuje kafelki na dysk** (`BuiltInMapCachingProvider` w katalogu cache
  aplikacji). Warstwa zdjęcia ma `cachingProvider: const DisabledMapCachingProvider()` (`orthophotoTileProvider` w
  `lib/app/map/plan_downloads.dart`); po oglądaniu zdjęcia w `cache` nie ma plików kafelków (sprawdzone w buildzie debug,
  `run-as`). Nagłówki dostawcy kafelków muszą być zwykłą mapą, nie `const` — `TileLayer` dopisuje do nich `putIfAbsent`.
- **Overpass jest zawodny** (pomiary przy ISSUE-027: 504, „server is probably too busy”, instancje bez odpowiedzi) i ma
  limit kilku zapytań naraz **na adres IP** — emulator wychodzi przez ten sam adres co PC, więc zapytania z PC w tym samym
  czasie psują pobieranie na emulatorze. Dlatego: po kolei, najwyżej jedno zapytanie na sekundę, ponowienia na dwóch
  hostach, cała próba do ok. 60 s, a ekran mówi wprost „serwer map nie odpowiada”.
- **Kiedy plan się pobiera** (`PlanDownloads`, ISSUE-027 D3): zapis cmentarza z punktem, zmiana punktu, start aplikacji,
  powrót do niej, otwarcie cmentarza bez planu, „Pobierz teraz”. Bez zadania w tle przy zamkniętej aplikacji. Brak sieci
  albo błąd serwera nie zapisuje niczego, więc następny start próbuje znowu; „brak w OSM” się zapisuje i wraca tylko po
  zmianie punktu.
- **Build release na emulator jako aktualizacja:** dotychczasowe buildy szły z `--split-per-abi` (kod wersji 4001 dla
  x86_64). Zwykły `flutter build apk --release` ma kod 1 i Android odrzuca go jako „downgrade” — na emulator
  `flutter build apk --release --split-per-abi --target-platform android-x64`.

## Lokalizacja — „gdzie jestem” i pinezka

Od ISSUE-029 (ADR-017 w vaulcie) aplikacja zna pozycję telefonu, **tylko z satelitów i tylko na ekranie cmentarza**:
- **własny kanał** `android/.../HereLocation.kt` na `LocationManager.GPS_PROVIDER` — bez Wi-Fi i masztów, bez usług Google,
  bez nowej zależności; nakładka w Dart: `lib/app/grave/here_location.dart`. Pozycje płyną tylko, gdy ekran słucha
  (`EventChannel`), i **nigdy nie trafiają do logu** — przy prawdziwym użyciu to miejsce, gdzie leży rodzina (NFR-005);
- uprawnienia `ACCESS_FINE_LOCATION` i `ACCESS_COARSE_LOCATION` w jednym żądaniu (Android 12+ pozwala dać tylko
  „Przybliżoną” — wtedy pinezki stawia się ręcznie). Po dwóch odmowach system już nie pyta: komunikat prowadzi do ustawień
  aplikacji;
- **próg „słaby sygnał”** to jedna stała, `weakSignalM` (15 m) w `here_location.dart` — **tymczasowa**: ustawi ją pomiar
  przy grobach (vault → `CURRENT_STATE.md` → *Parked*). Dokładność z Androida to promień przy 68% pewności.

**Emulator:** pozycję podaje `adb emu geo fix <długość> <szerokość> <wysokość> <satelity>`, np. `… 100 8` — najpierw długość; bez wysokości i satelitów emulator zostawiał swoją domyślną pozycję (ISSUE-029). Ta komenda **nie ustawia
dokładności**, więc słaby sygnał sprawdzają testy, a nie emulator. Punkt bierz z bazy aplikacji (cmentarz testowy), nie z
pamięci.

**Telefon** (wyjątek DoD: GPS na miejscu): Grobing trafia na telefon **wyłącznie z Google Play** (testy wewnętrzne —
*Wydanie* niżej, ISSUE-041). APK zbudowany tutaj ma inny podpis (klucz przesyłania, nie klucz Google) i inny numer wersji
(`--split-per-abi` daje 2001 na arm64), więc nie zaktualizuje wersji ze sklepu, a wersja ze sklepu nie zaktualizuje jego — przejście
między nimi to odinstalowanie, czyli skasowana baza. **Przed prawdziwymi danymi** wyczyść dane po próbach na wymyślonych: Ustawienia
telefonu → Aplikacje → Grobing → Pamięć → Wyczyść dane.

## Baza cmentarzy

Cmentarz dodaje się z wbudowanej bazy cmentarzy Polski (ISSUE-015): `assets/cemeteries/poland_cemeteries.json`
(ok. 1,9 MB, ok. 16 tys. cmentarzy). Działa bez sieci; aplikacja dalej nie ma uprawnienia `INTERNET`.
- **Licencja: ODbL 1.0, © autorzy OpenStreetMap** ([prawa autorskie OSM](https://www.openstreetmap.org/copyright/pl)).
  Plik jest bazą pochodną, więc obowiązuje go ta sama licencja (także w tym repozytorium). W aplikacji pod
  wynikami jest podpis „Dane: © autorzy OpenStreetMap (ODbL)”. Nagłówek pliku (`source`, `license`,
  `osmBase`) mówi, skąd i z którego dnia są dane. Województwa: Natural Earth 1:10m, domena publiczna.
- **Odtworzenie:** `dart run tool/cemeteries/extract_cemeteries.dart <katalog>`, gdzie katalog ma trzy pliki
  (nie ma ich w repo). Pobierz je z [Overpass API](https://overpass-api.de/api/interpreter) i z
  [Natural Earth](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson):
  - `osm_cemeteries.json`:
    ```
    [out:json][timeout:300];
    area["ISO3166-1"="PL"][admin_level=2]->.pl;
    (nwr["landuse"="cemetery"](area.pl); nwr["amenity"="grave_yard"](area.pl););
    out tags center;
    ```
  - `osm_places.json`:
    ```
    [out:json][timeout:300];
    area["ISO3166-1"="PL"][admin_level=2]->.pl;
    node["place"~"^(city|town|village|hamlet|suburb)$"](area.pl);
    out;
    ```
  - `ne_10m_admin_1_states_provinces.geojson`.

  Obecny plik powstał z wyciągu OSM z 2026-10-06 (`osmBase` w nagłówku). Nowy wyciąg oznacza nową wersję
  aplikacji; aktualizacji z sieci nie ma.
- **Miejscowość** w wyniku to najbliższa miejscowość z uwzględnieniem rangi (zasięg: miasto 12 km, miasteczko
  5 km, wieś 2,5 km, przysiółek 1,5 km). W mieście i miasteczku w nawiasie jest dzielnica bliżej niż 2,5 km.
  Pozostałe miejscowości w zasięgu są słowami do szukania. Ten sam cmentarz zmapowany dwa razy (ta sama
  nazwa i miejscowość, mniej niż 300 m) jest scalany.
- **Zdjęcie satelitarne** otwiera się w innej aplikacji (Mapy Google, bez nich przeglądarka) adresem z
  `basemap=satellite`, tylko po dotknięciu (`lib/app/external_link.dart`, kanał `grobing/external` w
  `ExternalLinks.kt`). `geo:` nie umie wybrać warstwy satelitarnej.

## Lista miejsc

Miejsce zamieszkania wybiera się z listy w aplikacji (ISSUE-042): `assets/places/places.db` (SQLite, ok. 11,7 MB) — 239 krajów
i ok. 188 tys. miejscowości. Działa bez sieci.

- **⚠️ Pliku nie ma w repo** — `*.db` jest w `.gitignore` (blok danych rodziny). To celowe: lista ma nazwy wszystkich
  miejscowości, także tych z listy rdzeni strażnika treści, więc w repo zatrzymałaby każdy commit, a wyjątek w strażniku byłby
  dziurą w jedynej ochronie publikacji (plan ISSUE-042, G1). **Na czystym klonie zbuduj listę przed pierwszym
  `flutter test`, `run` albo `build`** — `pubspec.yaml` ją wymienia, więc bez niej Flutter nie zbuduje assetów.
- **Zakres:** wszystkie miejscowości (GeoNames, klasa `P`, bez dzielnic `PPLX`) **Polski, Ukrainy, Białorusi i Litwy** (granice
  sprzed 1945), a ze świata `cities5000` (powyżej 5000 mieszkańców i stolice jednostek 1. rzędu). Z `cities1000` plik miał 18 MB,
  ponad próg 15 MB z planu. Kraje i ich punkty etykiet: Natural Earth 1:10m admin-0. Polskie nazwy z nazw alternatywnych GeoNames
  (`pl`); nazwy historyczne i inne polskie zapisy wsi z czterech krajów są tylko słowami do szukania.
- **Kolejność wyników:** dopasowanie od początku nazwy przed dopasowaniem w środku, potem liczba mieszkańców (mieszkańcy Polski ×10,
  Ukrainy, Białorusi i Litwy ×3), stolica i siedziby jednostek, potem alfabet. Dla 1–2 liter wyniki są policzone przy budowie
  (tabela `short_keys`), bo zakres jednej litery to dziesiątki tysięcy słów.
- **Licencje:** GeoNames — [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (pod wynikami podpis „Lista miejsc: GeoNames
  (CC BY 4.0) · Natural Earth”); Natural Earth — domena publiczna.
- **W aplikacji** pierwszy wybór miejsca kopiuje plik do `places/` w katalogu wsparcia aplikacji (SQLite nie otwiera assetu) i
  otwiera go tylko do odczytu (`lib/app/person/place_list_asset.dart`). Kopia zapasowa bierze tylko `grobing.db` i `media/`, więc
  lista do niej nie wchodzi. Nowa wersja aplikacji z inną listą (inny rozmiar pliku) kopiuje ją od nowa.
- **Budowa:** pobierz do jednego katalogu (poza repo) i rozpakuj:
  - z [GeoNames](https://download.geonames.org/export/dump/): `PL.zip`, `UA.zip`, `BY.zip`, `LT.zip`, `cities5000.zip`,
    `alternateNamesV2.zip` (ok. 200 MB, po rozpakowaniu ok. 800 MB), `admin1CodesASCII.txt`;
  - z [Natural Earth](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson): `ne_10m_admin_0_countries.geojson`;

  potem `dart run tool/places/build_places.dart <katalog>` (ok. 25 s). Obecny plik: zrzut GeoNames z 2026-10-16, Natural Earth
  pobrany tego samego dnia (tabela `meta` w pliku). Nowy zrzut oznacza nową wersję aplikacji.

## Wieńce

Wieniec rodu przy portrecie i na drzewie (ISSUE-044; vault: `05_DESIGN/wieniec.md`) to jeden z 19 wzorów w
`assets/wreaths/wieniec-<klucz>.png`, w kolorze rodu z palety 12 kolorów (`GrobingColors.clan`).

- **Pliki są w repo** (decyzja autora R na stopie #1): jedyny katalog obrazów poza `android/app/src/main/res/`. `.gitignore`
  wpuszcza tylko `wieniec-*.png`, a strażnik danych rodziny w `grobing-agents` dodatkowo tylko **szary PNG z przezroczystością,
  640 × 640** — zdjęcie nie jest ani jednym, ani drugim.
- **Co jest w pliku:** przezroczystość to kształt liści; szarość to cieniowanie C3 jako mnożnik koloru rodu (128 = sam kolor):
  jaśniej u końców gałązek, ciemniej przy węźle, liście tłoczone światłem z lewej u góry, nigdy ciemniej niż 80% koloru (każdy kolor
  palety zostaje ≥ 3:1 na tle). Aplikacja raz na wzór, kolor i rozmiar nakłada kolor, dodaje obwódkę w kolorze tła i trzyma gotowy
  obraz (`lib/app/widgets/wreath.dart`): w klatce drzewa nic się nie rozmywa.
- **Wspólny kadr:** portret ma średnicę połowy płótna i środek w (0,5; 0,434) płótna. Liście, które wchodzą pod portret, chowają
  się za nim.
- **Skąd obrazy:** autor wygenerował je w ChatGPT (DALL-E) z promptów w `05_DESIGN/wieniec.md` → *Prompts*: biały wieniec na
  czarnym tle, 2026-10-17. Nie ma maku (11). Oryginały są u autora, poza repo.
- **Przebudowa** (np. nowy wzór): zapisz oryginały jako `<klucz>.png` w jednym katalogu poza repo i uruchom
  `python tool/wreaths/build_wreaths.py <katalog>` (Python 3, Pillow, numpy). Nowy wzór to też nowa wartość `WreathMotif` w
  `lib/data/clans.dart` — bez zmiany schematu.

## Ikony

Ikony w aplikacji i ikona aplikacji (ISSUE-046; vault: `05_DESIGN/brand/style-b.md` reguły 3 i 8).

- **Ikony w aplikacji:** Material Symbols Rounded, grubość 300, w dwóch tonach — ten sam glif wypełniony przy kryciu 25% pod glifem
  z kreską (`lib/app/widgets/grobing_icon.dart` → `GrobingIcon`). Stałe ikon są w `lib/app/widgets/glyphs.dart` (`Glyphs.inkPen`
  …), font w `assets/fonts/grobing-symbols.ttf` (ok. 210 KB, licencja Apache-2.0 obok, w licencjach aplikacji). Ikona obok tekstu
  rośnie z systemowym rozmiarem tekstu; przycisk z samą ikoną, zakładka albo ikona w pudełku o stałym rozmiarze podaje
  `applyTextScaling: false`.
- **Dlaczego nie `Icon` i nie pakiet `material_symbols_icons`:** Flutter przy buildzie release wycina z fontów ikon nieużywane glify
  (`--tree-shake-icons`), a jego narzędzie gubi glify, które Material Symbols podmienia wzdłuż osi FILL — `group` i `settings`
  wychodziły puste (sonda 2026-10-18). Nasz font jest już wycięty poprawnie i aplikacja rysuje go jak tekst, nie przez `IconData`,
  więc Flutter go nie rusza. Nie używaj `Icon(...)` ani `Icons.*` w `lib/` — test to sprawdza.
- **Dziewięć ikon z arkusza autora** (decyzja 1' ISSUE-046): zakładki Mapa, Osoby i Drzewo, lupa, ustawienia, dodaj zdjęcie, pinezka ze
  zniczem, pióro, telewizor — obraz z DALL-E (bursztyn, dwa tony) przerysowany do wektora (potrace) i dołożony do tego samego fontu jako para
  glifów: linie i wypełnienie (`Glyph(…, fill: …)`, wolne kody z prywatnego obszaru Unicode). Ostre w każdym rozmiarze, kolor ze stanu jak
  reszta. Wypełnienie to wszystko wewnątrz zewnętrznego obrysu poza dużymi ciemnymi dziurami (środek koła zębatego) — tekstura DALL-E nie
  przechodzi. Obraz arkusza jest u autora, **poza repo**.
- **Znicz** (znak aplikacji — logo, przyciski „Otwórz cmentarz”/„Pokaż grób”, środek pinezek, znacznik zmarłych w drzewie): rysunek autora z
  DALL-E (`Z-znicz.png` w dwóch tonach, `Z-znicz-pelny.png` pełny z wyciętymi detalami), przerysowany tak samo do tego fontu (`Glyphs.candle`,
  `Glyphs.candleSolid`; `lib/app/widgets/candle.dart`). Pinezka zostaje kroplą z kodu (czubek co do piksela), w środku pełny znicz.
- **Nowa ikona albo przebudowa:** dopisz nazwę z pliku `.codepoints` do `tool/icons/glyphs.txt` i uruchom
  `python tool/icons/build_symbols.py <MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf> <…codepoints> <arkusz.png> <Z-znicz.png> <Z-znicz-pelny.png>` (Python 3:
  `python -m pip install fonttools potracer numpy pillow`). Źródło fontu: `github.com/google/material-design-icons`, katalog `variablefont/`,
  commit `49d4db35df873165d6bd6ba09b063c7dafbac2f4` (wersja fontu 2.975). Lista ikon z arkusza i ich kolejność — `SHEET` w skrypcie. Skrypt
  przebudowuje font i `glyphs.dart`.
- **Ikona aplikacji:** ikona adaptacyjna (`res/mipmap-anydpi-v26/ic_launcher.xml`): tło `@color/grobing_background`, na pierwszym
  planie znicz L1 w akcencie, warstwa jednobarwna z samych linii (motywy Androida 13+), do tego `mipmap-*/ic_launcher.png` dla Androida 7.
  Wszystko z jednego obrazu autora (DALL-E, poza repo):
  `python tool/icons/build_launcher.py <L1-znicz.png> [<ikona sklepu 512 px poza repo>]` (Python 3, Pillow). Ikonę 512 × 512 do
  karty w Play Console skrypt zapisuje tylko poza repo.

## Zdjęcia

Zdjęcie nagrobka: jedno na grób, do dodania, zmiany i usunięcia (ISSUE-016 w vaulcie). Zdjęcia osób: każda
osoba ma swoją bazę zdjęć z „profilowym”, a jedno zdjęcie może należeć do kilku osób (ISSUE-017).

- **Model (schemat v4, ISSUE-017):** wiersz `media` to zdjęcie (rekord), a `person_media` to łącze osoba–zdjęcie
  z pozycją — jak `OBJE` w GEDCOM 7. **Profilowe to pierwsze łącze osoby** (najniższa pozycja), osobno dla każdej
  osoby. Nagrobek zostaje przy `media.grave_id`. Wiersz `media` bez grobu i bez łącza znika w tej samej
  transakcji, która go takim zostawiła, a jego plik usuwa sprzątanie.
- **Zapis zdjęć osoby z „Zapisz” formularza** (`lib/app/photo/person_photos_draft.dart`): dodanie, profilowe,
  osoby na zdjęciu i usunięcie z osoby czekają w formularzu. „Zapisz” przenosi nowe pliki do `media/zdjecia/` i
  zapisuje wiersze w transakcji wpisu osoby (`graves.dart` → `AlsoWrite`), a „Odrzuć” cofa wszystko. **Przy
  przeniesieniu plik dostaje czas „teraz”**, bo zdjęcie może czekać w otwartym formularzu dłużej niż godzinę, a
  sprzątanie bierze pliki bez wiersza starsze niż 1 h. Nieudany zapis odkłada pliki z powrotem, więc „Zapisz”
  można ponowić.

- **Wybór:** paczka `image_picker` — systemowe okno wyboru zdjęć (Android Photo Picker od Androida 13) albo
  systemowy aparat, bez uprawnień do pamięci i aparatu (`lib/app/photo/photo_picker.dart`).
- **Co aplikacja trzyma:** własną kopię dostępową, nie oryginał (decyzja autora D2'): JPEG jakość 85, dłuższy
  bok najwyżej 2048 px (mniejsze zdjęcie bez zmiany rozmiaru), obrócona według EXIF, **bez EXIF** (także bez
  lokalizacji). Robi ją kanał `com.grobing.app/photos` w `PhotoPreparation.kt`: Android 9+ `ImageDecoder`, Android
  7–8 `BitmapFactory` + `ExifInterface`. Oryginał zostaje w galerii albo na papierze.
- **Pliki:** `media/groby/<id grobu>/<czas>-<losowe>.jpg` i `media/zdjecia/<czas>-<losowe>.jpg` (zdjęcia osób —
  bez id osoby, bo zdjęcie bywa wspólne) — nazwa nigdy z tego, co na zdjęciu. Przygotowanie
  idzie do `photo-work/` obok `media/` (poza kopią), a dopiero gotowy plik przechodzi do `media/`.
- **Kolejność kroków chroni kopię** (D3, `lib/data/photos.dart`): plik powstaje przed wierszem `media`, usunięcie
  kasuje tylko wiersz, a plik bez wiersza usuwa `sweepOrphanMedia` — pod zamkiem danych, przed znacznikiem i
  migawką każdej kopii oraz przy starcie, i tylko starszy niż 1 h. Odcisk danych i archiwum kopii liczą **tę
  samą** listę plików (`backup_archive.dart`): zdjęcie dodane w trakcie kopii nie może jej zepsuć.
- **Testy i dane debug:** obrazy tylko generowane w kodzie (`lib/dev/fictional_photo.dart`) — strażnik danych
  rodziny nie wpuszcza plików graficznych do repo. Kod natywny zmniejszania nie ma testu automatycznego;
  sprawdza się go na emulatorze.

## Kopia

Jeden zaszyfrowany plik w Dysku autora, nadpisywany przy każdej kopii (ADR-004 i ISSUE-008 w vaulcie).
Konfiguracja i „Zrób kopię teraz” są na ekranie „Stan danych”.

- **Format v1** — kontrakt, który zamraża pierwsza prawdziwa kopia; opis w vaulcie
  (`04_ARCHITECTURE/`). Plik `age` v1 do jednego klucza X25519, w środku `tar` (ustar):
  `grobing.db` (migawka `VACUUM INTO`), `media/…`, na końcu `manifest.json` (wersja formatu i
  schematu, liczby rekordów, odcisk danych, rozmiar i SHA-256 każdego pliku). Zmiana czegokolwiek to
  nowy `format_version`, bo odtworzenie musi czytać każdą wersję, która kiedykolwiek powstała.
- **Klucz:** w telefonie zostaje tylko klucz publiczny (`backup.json` obok bazy), więc kopia nie
  potrzebuje hasła. Klucz prywatny jest w pliku `grobing-klucz.age`, zaszyfrowanym hasłem (scrypt).
  **Odtworzenie = plik kopii + plik klucza + hasło.** Hasła aplikacja nigdzie nie zapisuje.
- **Stan kopii poza bazą** (`backup.json`: klucz publiczny, plik w Dysku, czas ostatniej kopii): czas
  kopii w bazie zmieniałby odcisk danych przy każdej kopii i wymagałby migracji.
- **Otwarcie bez Grobing**, na PC, oficjalnym [`age`](https://github.com/FiloSottile/age) — poza każdym
  repozytorium, bo to dane rodziny:

  ```sh
  age -d -i grobing-klucz.age grobing-kopia.age > kopia.tar   # age pyta o hasło do pliku klucza
  mkdir kopia && tar -xf kopia.tar -C kopia
  dart run tool/fingerprint.dart kopia                       # odcisk i manifest, ta sama funkcja co ekran
  ```

- **Moduł `age`** (`lib/backup/age/`) jest nasz — `dage` i `dartage` odpadły w SPIKE-003. Sprawdzają go
  oficjalne wektory testowe [C2SP/CCTV](https://github.com/C2SP/CCTV/tree/main/age) w `flutter test`
  i oficjalne CLI (bramka zgodności). `cryptography` i `pointycastle` są przypięte dokładnie: nowa
  wersja to zmiana do sprawdzenia tą samą bramką.
- **Do Dysku przez systemowe okno zapisu pliku** (`BackupDocuments.kt`): aplikacja ma uprawnienie do
  jednego pliku, bez kluczy API, bez OAuth i bez uprawnienia `INTERNET` — wysyła aplikacja Dysk.
  „Ostatnia udana kopia” znaczy: Dysk w telefonie przyjął plik, nie: plik jest już w chmurze.
- **Kopia Androida i transfer na nowy telefon (D2D) są wyłączone** (`allowBackup="false"` +
  `res/xml/data_extraction_rules.xml`). Jedyna droga na nowy telefon to ta kopia.

### Odtworzenie

„Stan danych” → „Odtwórz z kopii” (ISSUE-009 w vaulcie): plik kopii i plik klucza z systemowego okna
otwarcia pliku, hasło. **Dane w telefonie zmieniają się dopiero po sprawdzeniu całej kopii** — zła
kopia kończy się komunikatem i niczego nie rusza.

- **Kolejność** (`lib/backup/restore_service.dart`), wszystko w `restore-staging/` w katalogu danych
  aplikacji:
  1. miejsce: wolne ≥ 2 × rozmiar pliku kopii + 200 MB; gdy Dysk nie zna rozmiaru, czytanie przerywa
     budżet bajtów (kopia zaszyfrowana i rozpakowane pliki są na dysku naraz);
  2. plik klucza otwierany hasłem (scrypt, work factor do 20 — więcej nie zmieści się w pamięci
     telefonu); tożsamość nigdy nie trafia na dysk;
  3. plik kopii skopiowany lokalnie, odszyfrowany i rozpakowany ścisłym czytnikiem tar
     (`tar_reader.dart`: tylko zwykłe pliki, bezpieczne ścieżki tą samą regułą co zapis, tylko
     `grobing.db`, `media/…` i `manifest.json` na końcu, sumy nagłówków, budżet bajtów);
  4. manifest: wersja formatu, wersja schematu (nowsza → „zaktualizuj aplikację”), lista plików,
     rozmiary i SHA-256;
  5. baza: `integrity_check`, `user_version`, liczby rekordów i **odcisk danych = manifest**;
  6. starszy schemat → zwykłe migracje aplikacji, potem znów `integrity_check` i liczby rekordów.
- **Podmiana odporna na przerwanie** (`restore_swap.dart`): znacznik `restore.json` jest punktem
  zatwierdzenia. Bez znacznika nic się nie zmieniło, a resztki są usuwane; ze znacznikiem każdy start
  aplikacji (`main.dart`, **przed** otwarciem bazy) kończy podmianę. Stara baza odchodzi razem ze swoim
  dziennikiem (`-journal`/`-wal`/`-shm`), zanim przyjdzie nowa. Po odtworzeniu aplikacja otwiera dane
  od nowa tą samą drogą co przy starcie.
- **Kopia po odtworzeniu:** telefon z konfiguracją kopii zostaje przy niej. Świeży telefon pisze dalej
  **tym samym kluczem** do pliku, z którego odtworzono (o ile Dysk pozwala w nim zapisywać), więc plik
  klucza z notki przekazania otwiera także nowe kopie.
- Telefon, który ma już dane, dostaje ostrzeżenie z liczbami i „Zastąp dane”. Nie ma tam „najpierw
  zrób kopię”: to nadpisałoby plik, z którego właśnie odtwarzasz.

### Kopia w tle

Kopia robi się sama, **jedna po sesji pracy:** ok. 10 min po ostatniej zmianie danych, a przy dłuższej,
nieprzerwanej pracy najpóźniej godzinę po pierwszej niezapisanej zmianie (ISSUE-010 w vaulcie). Gdy
aplikacji nikt nie używa, nic się nie dzieje — bez cyklicznych sprawdzeń.

- **Wyzwalacze:** **każdy zapis do bazy** (`watchChanges` — `tableUpdates` z `drift`, jeden obserwator w
  `GrobingApp`), a do tego wyjście z aplikacji (`paused`) i start (`main.dart`: dane po odtworzeniu,
  zmiany poza `drift`). Zamówienie idzie w chwili zapisu, bo samo wyjście z aplikacji przegrywa wyścig z
  wyrzuceniem jej z ostatnich: proces ginie ~2 s po geście, zanim zadanie zostanie zapisane (stop #2).
  Każdy wyzwalacz zamawia kopię tylko wtedy, gdy **stempel danych** (`data_stamp.dart`: licznik zmian z
  nagłówka SQLite, rozmiar i czas pliku bazy, rozmiar i czas każdego zdjęcia — nigdy treść) różni się
  od stempla ostatniej udanej kopii w `backup.json`. Stempel jest porównywany na równość, więc cofnięty
  zegar niczego nie ukryje.
- **Zadanie** (`BackgroundBackup.kt`): jednorazowe zadanie WorkManagera (`androidx.work`, bez wtyczki
  Fluttera) z opóźnieniem 10 min, warunkiem `StorageNotLow` i czasem pierwszej zmiany. Jedno czekające
  zadanie obejmuje wszystkie zmiany; biegnące **nigdy nie jest anulowane** (anulowany zapis `"wt"`
  zostawiłby w Dysku ucięty plik), następne idzie za nim. **Cisza:** jeśli dane zmieniły się mniej niż
  10 min temu, przebieg kończy się bez kopii i zamawia następny na chwilę, gdy minie 10 min ciszy — chyba
  że od pierwszej zmiany minęła godzina (`backupQuiet`, `backupCap` w `background.dart`). Nieudana kopia →
  do 4 prób z rosnącym odstępem, potem czeka na następne wyzwolenie; błąd widać na „Stanie danych”.
- **Dart w tle:** zadanie startuje bezgłowy silnik Fluttera, rejestruje w nim `BackupDocuments` (bez
  okien) i kanał `com.grobing.app/background`, a potem uruchamia `backgroundBackupMain` z `main.dart`
  (`@pragma('vm:entry-point')` — inaczej build release by ją wyciął). Przebieg
  (`background_backup.dart`) robi tę samą kopię co przycisk, z dopiskiem „(w tle)” na ekranie. Zadanie ma
  ~10 min (limit Androida); przy ~8 MB/s szyfrowania to kopie rzędu kilku GB.
- **Jedna operacja na danych naraz:** kopia w tle, „Zrób kopię teraz”, konfiguracja i odtworzenie biorą
  ten sam zamek, trzymany natywnie (`DataLock`), bo silniki nie dzielą pamięci Darta, a blokada pliku w
  Darcie działa na poziomie procesu. Kopia w tle przy znaczniku `restore.json` albo przy innej wersji
  schematu nie robi nic — dokończenie odtworzenia i migracja należą do startu aplikacji.
- **Dwa połączenia z bazą** (otwarta aplikacja + kopia w tle) używają tej samej dołączonej biblioteki
  SQLite i `PRAGMA busy_timeout`. **Kotlin nigdy nie otwiera `grobing.db`**: druga kopia SQLite w
  procesie nie widzi cudzych blokad ([How To Corrupt](https://www.sqlite.org/howtocorrupt.html), 2.3).
- **Do testów** — wymuszenie zadania bez czekania (przy danych zmienionych < 10 min temu przebieg tylko
  zamówi następny):

  ```sh
  adb shell dumpsys jobscheduler | grep "u0a.*BackupWorker"   # numer zadania po "/"
  adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler com.grobing.app <numer>
  ```

## Podpis wydania

Aktualizacja wchodzi na telefon tylko wtedy, gdy jest podpisana **tym samym kluczem** co zainstalowana
wersja ([Sign your app](https://developer.android.com/studio/publish/app-signing)). Inny klucz = trzeba
odinstalować aplikację, a **odinstalowanie kasuje bazę**.

> ⚠️ **Na telefon tylko z Google Play** (ISSUE-041). Aplikację ze sklepu podpisuje **klucz wygenerowany przez Google**
> (Play App Signing); klucz niżej podpisuje paczkę wysyłaną do sklepu, czyli jest **kluczem przesyłania**. Zgubiony klucz
> przesyłania da się zresetować w Play Console (*Integralność aplikacji*), bez zmiany podpisu aplikacji na telefonie. Buildy
> debug, profile i APK release z tego klucza idą tylko na emulatory.

1. **Klucz tworzy autor sam** — `keytool` pyta o hasła, więc nie przechodzą przez żadną sesję ani
   historię. Katalog: `release_keystore_dir` z `../grobing-agents/.claude/rules/project-config.md`
   (lokalny, poza każdym drzewem projektu):

   ```powershell
   keytool -genkey -v -keystore <release_keystore_dir>\grobing-release.jks -storetype JKS `
     -keyalg RSA -keysize 2048 -validity 10000 -alias grobing
   ```

2. **`android/key.properties`** (gitignorowany — nigdy do repo). W `storeFile` ukośniki `/`, bo `\` jest
   w tym formacie znakiem ucieczki:

   ```properties
   storePassword=<hasło magazynu>
   keyPassword=<hasło klucza>
   keyAlias=grobing
   storeFile=<release_keystore_dir z ukośnikami />/grobing-release.jks
   ```

3. **Kopia klucza** (`.jks` + hasła) w zaszyfrowanym miejscu autora, tym samym co kopia notatek
   (NT-001) — nie na tym samym dysku.

Bez `android/key.properties` build release **kończy się błędem** — nigdy nie podpisuje się po cichu
kluczem debug (`android/app/build.gradle.kts`).

## Wydanie

Aktualizacja na telefonie zachowuje dane, gdy zgadzają się trzy rzeczy: nazwa pakietu (*Tożsamość aplikacji*), podpis (*Podpis
wydania*) i **wyższy numer wersji**. Kanał jest jeden: Google Play, ścieżka testów wewnętrznych, autor jedynym testerem (ADR-019,
ISSUE-041). Czynności w Play Console wykonuje autor; agent przygotowuje paczkę i podaje kroki.

1. **Numer wersji** — `pubspec.yaml` → `version: <nazwa>+<numer>`: **numer rośnie przy każdej wysyłce** (sklep odrzuca numer, który
   już był). Nazwa: `0.9.x` do instalacji z prawdziwymi danymi, `1.0.0` na instalację. Nazwa ma drugi dom —
   `appVersion` w `lib/app/settings/settings_screen.dart` (test pilnuje, że są równe).
2. **Paczka:**

   ```sh
   flutter build appbundle --release      # build/app/outputs/bundle/release/app-release.aab
   ```

3. **Przed wysyłką na telefonie:** „Stan danych” → ostatnia udana kopia jest świeża.
4. **Wysyłka (autor):** Play Console → *Testy wewnętrzne* → *Utwórz wersję* → paczka → *Zapisz* → *Sprawdź wersję* → *Rozpocznij
   wdrażanie*. Pierwsza wersja: klucz podpisu **wygenerowany przez Google**.
5. **Aktualizacja (autor):** Sklep Play → Grobing → *Aktualizuj*. Pierwsze uruchomienie przenosi bazę do nowej wersji (jedna
   transakcja), a zaraz potem robi kopię.
6. **W trakcie wyjazdu na cmentarze — bez aktualizacji.**

**Migawka sprzed aktualizacji** (ISSUE-041, K3, `lib/data/pre_update_snapshot.dart`): zanim nowa wersja przeniesie bazę na nowszy
schemat, start zapisuje jej spójną kopię w starej wersji — `pre-update/grobing-v<stara>.db` obok bazy (prywatny katalog aplikacji,
poza kopią i poza Pobranymi); zostają 3 najnowsze. Kopia na Dysku tego nie zastąpi: start zamawia ją zaraz po migracji, a ona
nadpisuje jedyny plik kopii.

**Droga powrotu przy złej migracji:** nowa wersja z poprawką — zanim otworzy bazę — zastępuje ją migawką z wersji sprzed złej
migracji (przy zamkniętej bazie, z jej `-journal`, jak przy odtworzeniu w `restore_swap.dart`) i przenosi ją poprawionym krokiem.
Zmiany wpisane po złej aktualizacji, a przed poprawką, giną — dlatego po aktualizacji ze zmianą schematu najpierw sprawdzić dane,
potem wpisywać nowe. Zdjęć to nie dotyczy: migracje ich nie zmieniają.

## Tożsamość aplikacji

Nazwa pakietu i root widget są zapisane w
`../grobing-agents/.claude/rules/project-config.example.md` (*Product invariants*) — agenci ich nie
wymyślają. **Nazwy pakietu nie zmienia się nigdy**: inna nazwa to dla Androida inna aplikacja, która nie
widzi bazy poprzedniej.
