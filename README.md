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
- **Zapis osoby w grobie** (`lib/data/graves.dart`) to jedna transakcja: grób (przy nowym), osoba,
  pochówek i daty, każde z twierdzeniem „notatki”. Błąd w środku nie zostawia „pół osoby”.
- **Odcisk danych** (ekran „Stan danych”, `lib/data/data_state.dart`) jest miarą dla kopii i
  odtworzenia (NFR-002). Liczy się z **treści**, nie z pliku: tabele po nazwie, wiersze po wszystkich
  kolumnach, wartości w stałym kodowaniu, potem pliki zdjęć po ścieżce. `VACUUM INTO` go nie zmienia.
  **Zmiana tej definicji unieważnia wszystkie wcześniej zapisane odciski.**
- **Wymyślone dane** (`lib/dev/`) są dostępne tylko w buildzie debug: przycisk na ekranie „Stan danych”.
  W buildzie release tego kodu nie ma. Wymyślone cmentarze mają wymyślone punkty w Polsce: partie 1 i 2
  stoją w jednym miejscu (znicz z liczbą), co trzecia partia jest bez punktu.

## Mapa

Ekran główny to mapa Polski (ISSUE-014, ADR-007 w vaulcie). **Bez warstwy kafelków i bez sieci:** kontur
kraju, rzeki i 9 miast są w aplikacji, w `assets/map/poland.json` (ok. 37 KB).
- **Źródło:** [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) 1:10m — domena
  publiczna, bez wymogu podpisu. Plik odtwarza `tool/map/extract_poland.dart` z trzech plików GeoJSON
  repozytorium [`nvkelso/natural-earth-vector`](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson)
  (lista i polecenie w nagłówku skryptu). Plików źródłowych nie ma w repo.
- **`flutter_map` 8.3.2 i `latlong2` 0.10.1 są przypięte dokładnie.** Paczka zależy od `http`, ale używa
  go tylko warstwa kafelków, której tu nie ma. Aplikacja nie ma uprawnienia `INTERNET`.
- **Pułapka:** ruch mapy ogranicza `CameraConstraint.containCenter`, a nie `contain`. Na pionowym ekranie
  cała szerokość Polski daje widok wyższy niż Polska, więc „wszystkie krawędzie w granicach” nie da się
  spełnić i mapa jest pusta (zmierzone przy planie ISSUE-014).
- **Znicze, które nachodzą na siebie** (cel dotyku 48 dp), łączą się w jeden znicz z liczbą
  (`lib/app/home/pin_groups.dart`). Ikona znicza jest jedna na całą aplikację: `lib/app/widgets/candle.dart`.

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

## Zdjęcia

Zdjęcie nagrobka: jedno na grób, do dodania, zmiany i usunięcia (ISSUE-016 w vaulcie; zdjęcia osób —
ISSUE-017).

- **Wybór:** paczka `image_picker` — systemowe okno wyboru zdjęć (Android Photo Picker od Androida 13) albo
  systemowy aparat, bez uprawnień do pamięci i aparatu (`lib/app/photo/photo_picker.dart`).
- **Co aplikacja trzyma:** własną kopię dostępową, nie oryginał (decyzja autora D2'): JPEG jakość 85, dłuższy
  bok najwyżej 2048 px (mniejsze zdjęcie bez zmiany rozmiaru), obrócona według EXIF, **bez EXIF** (także bez
  lokalizacji). Robi ją kanał `com.grobing.app/photos` w `PhotoPreparation.kt`: Android 9+ `ImageDecoder`, Android
  7–8 `BitmapFactory` + `ExifInterface`. Oryginał zostaje w galerii albo na papierze.
- **Pliki:** `media/groby/<id grobu>/<czas>-<losowe>.jpg` — nazwa nigdy z tego, co na zdjęciu. Przygotowanie
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

> ⚠️ **Na telefonie z prawdziwymi danymi instaluj wyłącznie build release** (`flutter run --release`
> albo `flutter build apk --release`). Przejście z buildu debug na release też wymaga odinstalowania.

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

## Tożsamość aplikacji

Nazwa pakietu i root widget są zapisane w
`../grobing-agents/.claude/rules/project-config.example.md` (*Product invariants*) — agenci ich nie
wymyślają. **Nazwy pakietu nie zmienia się nigdy**: inna nazwa to dla Androida inna aplikacja, która nie
widzi bazy poprzedniej.
