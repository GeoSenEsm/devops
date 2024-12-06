# Konfiguracja Środowiska Produkcyjnego i Testowego

Dokument opisuje, jak skonfigurować i uruchomić środowisko produkcyjne i testowe dla projektu przy użyciu Docker Compose.

## Wymagania wstępne

Przed rozpoczęciem upewnij się, że masz zainstalowane:

- Docker na swoim komputerze.
- Docker Compose.

## UWAGA!!

Serwisy produkcyjne opisane tutaj są przeznaczone do środowisk produkcyjnych. Serwisy testowe (`test-api`, `test-admin-panel`, itp.) służą do tworzenia kont testowych dla usług takich jak Google i Apple, które wymagają tworzenia kont testowych. Te środowiska **nie** powinny być używane na produkcji, z wyjątkiem celów testowych i stagingowych.

### Kluczowe Zmienne Środowiskowe

1. **PRODUCTION_API_URL**:  
   Ta zmienna służy do zdefiniowania URL, który powinien kierować do usługi `production-api` za pośrednictwem Nginx Proxy Manager. Należy ją skonfigurować tak, żeby proxy Nginx prawidłowo wskazywał na `production-api`. Przykład:

    ```bash
    export PRODUCTION_API_URL="http://production-api.local"
    ```

2. **DATABASE_PASSWORD**:  
   Ta zmienna jest używana do ustawienia hasła dla baz danych SQL Server. Ważne jest, aby ustawić ją poprawnie zarówno dla środowiska produkcyjnego, jak i testowego. Przykład:

    ```bash
    export DATABASE_PASSWORD="twoje_bezpieczne_hasło"
    ```

3. **ADMIN_USER_PASSWORD**:  
   To hasło dla użytkownika administracyjnego w środowisku produkcyjnym. Upewnij się, że jest ono ustawione w sposób bezpieczny. Przykład:

    ```bash
    export ADMIN_USER_PASSWORD="twoje_hasło_administracyjne"
    ```

4. **TEST_API_URL**:  
   Ta zmienna służy do zdefiniowania URL dla usługi `test-api`. Ten URL będzie używany przez testowy panel administracyjny do łączenia się z testowym API. Jeśli nie zostanie podany, domyślny URL to `http://localhost:8080`. Przykład:

    ```bash
    export TEST_API_URL="http://test-api.local"
    ```

## Kroki do Uruchomienia Środowiska

1. Pobierz plik `docker-composes/production/docker-compose.yml` z repozytorium.
2. Otwórz terminal (bash w systemie Linux, PowerShell w systemie Windows).
3. Przejdź do katalogu, w którym znajduje się plik `docker-compose.yml`.
4. Uruchom następujące polecenie, aby uruchomić wszystkie usługi:

    ```bash
    docker-compose up
    ```

5. Następujące usługi będą dostępne:

   - **Nginx Proxy Manager**: Dostępny na porcie 81 (do konfigurowania routingu między usługami).
   - **Production API**: Dostępny za pośrednictwem skonfigurowanego Nginx Proxy Manager.
   - **Production Admin Panel**: Dostępny poprzez skonfigurowany routing w Nginx Proxy Manager.

   **Uwaga**: Po pierwszym uruchomieniu tego środowiska Docker pobierze wszystkie niezbędne obrazy, co może potrwać chwilę.

## Konfiguracja Nginx Proxy Manager

Środowisko zawiera [Nginx Proxy Manager](https://nginxproxymanager.com/), który służy do zarządzania routingiem między usługami. Po uruchomieniu kontenerów należy skonfigurować routing dla `production-api` i innych usług za pomocą interfejsu Nginx Proxy Manager.

## Serwisy Testowe

Serwisy testowe (`test-api`, `test-admin-panel`, i `test-database`) są używane wyłącznie do tworzenia kont testowych dla usług takich jak Google i Apple, które wymagają, aby konta testowe zostały stworzone w środowisku testowym. Konta te są potrzebne do zadań specyficznych dla testerów (np. testowanie w Google Play lub Apple App Store).

## Polityka prywatności

Umieść politykę (lub polityki w różnych językach) prywatności w folderze `./privacy_policy`, będzie ona dostępna pod taką samą ścieżką w serwicie privacy-policy. Potem możesz odpowiednio skonfugurować przekierowanie w ngnx proxy manager.

### Konfiguracja Środowiska Testowego

Można uzyskać dostęp do testowego panelu administracyjnego i API w następujący sposób:

- **Test API**: Dostępne poprzez usługę `test-api`.
- **Test Admin Panel**: Dostępne poprzez usługę `test-admin-panel`.

Te usługi są izolowane od środowiska produkcyjnego, ale odzwierciedlają produkcyjne API i bazę danych, umożliwiając testowanie określonych działań, takich jak tworzenie kont, bez wpływania na dane produkcyjne.

## Dodatkowe Uwagi Konfiguracyjne

- **Wolumeny**: Usługi używają wolumenów Dockera do przechowywania danych w sposób trwały. Wolumeny te są definiowane dla Nginx Proxy Manager, baz danych SQL Server oraz przesyłania obrazów API.
  
- **Porty Nginx Proxy Manager**: Nginx Proxy Manager jest skonfigurowany do nasłuchiwania na następujących portach:
  - **80**: HTTP
  - **443**: HTTPS
  - **81**: Interfejs administracyjny do konfigurowania routingu.

  Po uruchomieniu kontenerów będziesz musiał zalogować się do interfejsu Nginx Proxy Manager pod adresem `http://localhost:81`, aby skonfigurować odpowiednie trasy proxy dla swojego produkcyjnego i testowego API.

## Podsumowanie

Ta konfiguracja umożliwia uruchomienie zarówno środowiska produkcyjnego, jak i testowego dla projektu przy użyciu Dockera. Możesz skonfigurować routing dla swoich usług za pomocą Nginx Proxy Manager i łatwo przełączać się między produkcyjnymi i testowymi API w zależności od potrzeb.

Aby uzyskać więcej informacji na temat korzystania z Nginx Proxy Manager, zapoznaj się z oficjalną [dokumentacją](https://nginxproxymanager.com/).
