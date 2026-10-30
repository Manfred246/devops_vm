# Конфигурация виртуальной машины devops-vm

Практическая работа 5. Исполнитель: Бельдий Матвей Олегович, ЭФБО-18-24.
Проверено 30 октября 2026 года. Время снимков ниже указано по Москве UTC+3;
журналы гостевой Ubuntu используют UTC.

Репозиторий работы: https://github.com/Manfred246/devops_vm . Использован
существующий репозиторий проекта; в методических указаниях имя учебного
репозитория приведено как `devops-course-2026`. ВМ не переустанавливалась.

## 1. Параметры машины

- VirtualBox, имя `devops-vm`, UUID `7e158435-4d33-4ead-9a41-41f1da5672ba`.
- Фактическая ОС: Ubuntu Server 26.04.1 LTS, x86_64, без рабочего стола.
  В методичке указана Ubuntu 24.04; использована уже установленная система.
  Метка типа ОС в VirtualBox может показывать Ubuntu 25.04 и не определяет
  фактически установленную версию, проверяемую через `/etc/os-release`.
- ОЗУ 2048 МБ, 2 vCPU, динамический VDI 25 ГиБ, контроллер SATA.
- Конфигурация Windows: `C:\Users\TPC\VirtualBox VMs\devops-vm\devops-vm.vbox`.

## 2. Сетевые интерфейсы

| Интерфейс | Тип | IPv4 | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24, DHCP | Интернет, обновления, SSH через проброс |
| enp0s8 | Host-only | 192.168.56.102/24, DHCP | Локальный доступ с Windows |
| lo | Loopback | 127.0.0.1/8 | Локальные службы |

Host-only адаптер Windows: `VirtualBox Host-Only Ethernet Adapter`, IPv4
`192.168.56.1/24`, имя интерфейса Windows `Ethernet 2` (индекс 50 на этом ПК).
DHCP VirtualBox: сервер `.100`, диапазон `.101`–`.254`.
Первоначальный адрес `.101` изменился на `.102` после явного описания
интерфейса в Netplan; во всех итоговых настройках используется `.102`.

Исходный `/etc/netplan/00-installer-config.yaml` описывает NAT. Добавлен
`/etc/netplan/60-hostonly.yaml` с правами 600:

```yaml
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: true
      optional: true
      dhcp4-overrides:
        use-routes: false
```

Проверка: `ip -brief address`. Адрес DHCP следует повторно проверить после
восстановления или изменения сети. В NAT включен DNS host resolver:

```powershell
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' modifyvm devops-vm --natdnshostresolver1 on
```

Команда `modifyvm` выполняется на выключенной ВМ. Это устранило отсутствие
ответов от DNS-серверов, переданных гостю до настройки. Обновление
`apt update && apt upgrade -y` и установка `openssh-server` завершены.

В Windows в защищенный файл `C:\Windows\System32\drivers\etc\hosts`
добавлена запись (потребовался запуск пользователем от имени администратора):

```text
192.168.56.102 devops.local
```

`[System.Net.Dns]::GetHostAddresses('devops.local')` возвращает `.102`.
AmneziaVPN добавляет конкурирующие маршруты `/24` и `/32`; попытки
приоритизировать Host-only не обеспечили прямой доступ: Windows возвращала
`General failure` / `Permission denied` до отправки пакетов. По требованию
пользователя VPN остался включен. Прямой доступ Windows → Host-only
не подтвержден. Рабочее подключение по имени выполняется через SSH-переход,
описанный в разделе 5. Временный маршрут `.102/32` и метрика 1 интерфейса
Host-only устанавливались пользователем только в ActiveStore и исчезают
после перезагрузки Windows; настройки VPN не менялись.

## 3. Правило проброса портов

Постоянное правило адаптера 1:

```text
ssh,tcp,127.0.0.1,2222,,2222
```

То есть TCP `127.0.0.1:2222` на Windows → TCP `2222` гостя. В снимках
01 и 02 гостевой порт равен 22. В снимке 03 и текущем состоянии — 2222.
Временный проброс `ufw-test` с `127.0.0.1:18080` на гостевой `8080`
использовался только для получения UFW BLOCK при включенном VPN и удален.

## 4. Учётные записи

- `mattew`, UID 1000: исходная учетная запись с правами sudo, консольный
  вход сохранен; SSH запрещен итоговым `AllowUsers devops`.
- `devops`, UID 1001: группы `devops`, `sudo`, `users`; SSH по отдельному
  ключу Ed25519. Локальный пароль задан для sudo; пароль в Git не хранится.
- `root`: непосредственный вход по SSH запрещен.

Закрытый ключ находится только на Windows в `C:\Users\TPC\.ssh\devops_vm`,
открытый — рядом в `devops_vm.pub`. Закрытый ключ не включается в репозиторий
и не копируется на сервер. На сервере `/home/devops/.ssh` имеет права 700,
`authorized_keys` — 600, владелец обоих объектов `devops:devops`.

Проверенный через консоль отпечаток ключа сервера Ed25519:

```text
SHA256:Ft7JM9tP+ldiUm9Yi4j3jlD9uS7tENIjmz2R4fYk42o
```

## 5. Служба SSH

Основной `/etc/ssh/sshd_config` не изменялся; эталонная копия:
`/etc/ssh/sshd_config.backup`. Добавлен `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Конфликтующих активных `PasswordAuthentication yes` в drop-in файлах
не обнаружено. Эффективное `KbdInteractiveAuthentication no` уже задано
исходной конфигурацией и проверено через `sshd -T`.
`ssh.socket` отключен, `ssh.service` включен и работает.
Служба слушает `0.0.0.0:2222` и `[::]:2222`.

Настройки Windows в `C:\Users\TPC\.ssh\config`:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
    ProxyCommand ssh -W 192.168.56.102:2222 devops
```

Оба подключения `ssh devops` и `ssh -p 2222 devops@devops.local`
проверены с `BatchMode=yes`, без запроса пароля. Вторая команда проходит
через тот же сервер по NAT и затем обращается к его Host-only адресу.
Это обход недоступного прямого маршрута, а не доказательство прямого
соединения Windows с Host-only. При работе без блокирующего VPN строку
`ProxyCommand` можно убрать после проверки прямого доступа.

До hardening список методов был `publickey,password`, после — `publickey`.
Обе отрицательные проверки вернули `Permission denied (publickey)`.
Для root журнал дополнительно содержит `not allowed because not listed in
AllowUsers`; во втором случае клиент отключил единственный доступный метод.

## 6. Правила межсетевого экрана

UFW активен, включен при загрузке. Политики: `deny incoming`, `allow outgoing`,
`disabled routed`; журналирование `medium`.

| Порт TCP | Действие | Комментарий |
|---|---|---|
| 80 | ALLOW IN | HTTP |
| 443 | ALLOW IN | HTTPS |
| 2222 | LIMIT IN | SSH rate-limited |

Те же правила действуют для IPv6. Разрешающее правило SSH создано до
активации UFW, затем заменено на LIMIT. Новое SSH-подключение после
активации проверено при сохраненной действующей сессии.
Не следует выполнять шесть и более новых подключений с одного адреса
за 30 секунд во время автоматических проверок.

Реальная запись блокировки от хостовой системы получена через временный NAT
проброс: `IN=enp0s3 SRC=10.0.2.2 DST=10.0.2.15 PROTO=TCP DPT=8080`.
Запись находится в `/var/log/ufw.log`. Номер внешнего порта Windows 18080
в журнале UFW не виден: NAT уже преобразовал назначение в гостевой 8080.

## 7. Снимки состояния

Все три снимка сделаны после штатного выключения, без сохранения памяти.

| Название | Время 30 октября 2026 UTC+3 | Состояние |
|---|---|---|
| 01-clean-install | 03:43:15 | Обновленная ОС, SSH 22, NAT и Host-only |
| 02-keys-configured | 03:47:00 | Учетная запись devops, sudo, ключевой вход |
| 03-ssh-hardened | 03:48:10 | SSH 2222, root и парольный SSH запрещены |

UFW, FQDN и скрипт аудита настроены после снимка 03 и находятся в текущем
измененном состоянии. Восстановление снимка 03 их не восстановит.
Попытка живого снимка 02 зависла при сохранении памяти и была штатно
отменена через `IProgress.Cancel`; неудачный снимок не оставлен в дереве.

## Восстановление после снимка 01

Оставляйте действующую SSH-сессию открытой до успешного подключения в новой.
Команды хоста выполняются в PowerShell, команды сервера — в Ubuntu.

1. После отката 01 запустите ВМ. Правило NAT уже направляет 2222 на 22.
   Подключитесь `ssh -p 2222 mattew@127.0.0.1`. На сервере:

   ```bash
   sudo adduser devops
   sudo usermod -aG sudo devops
   ```

   Пароль задается интерактивно и нужен для sudo. Отпечаток ключа хоста
   сверяется с консолью; при откате на 01 он должен остаться прежним.

2. Отдельный ключ Windows уже существует и при откате ВМ не меняется.
   Если он утерян, создайте новый ключ `ssh-keygen -t ed25519 -C devops-vm-key
   -f "$env:USERPROFILE\.ssh\devops_vm"`. Не перезаписывайте существующий
   ключ. Скопируйте открытый ключ с Windows:

   ```powershell
   Get-Content "$env:USERPROFILE\.ssh\devops_vm.pub" | ssh -p 2222 devops@127.0.0.1 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
   ssh -o BatchMode=yes devops 'id; stat -c "%a %n" ~/.ssh ~/.ssh/authorized_keys'
   ```

3. В открытой сессии `devops` сохраните основной файл и создайте drop-in
   с точным содержимым из раздела 5:

   ```bash
   sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
   sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
   sudo grep -r PasswordAuthentication /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
   sudo sshd -t
   sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
   sudo systemctl disable --now ssh.socket
   sudo systemctl enable --now ssh.service
   sudo systemctl restart ssh
   sudo ss -tlnp | grep sshd
   ```

4. На Windows, не закрывая предыдущую сессию:

   ```powershell
   $vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
   & $vbox controlvm devops-vm natpf1 delete ssh
   & $vbox controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
   ssh -o BatchMode=yes devops hostname
   ssh -o BatchMode=yes -p 2222 root@127.0.0.1
   ssh -o BatchMode=yes -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1
   ```

   Последние две команды должны завершиться отказом. При ошибке
   исправляйте конфигурацию через оставленную сессию или консоль ВМ.

5. В Ubuntu настройте UFW и имя:

   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow 2222/tcp comment 'SSH'
   sudo ufw allow 80/tcp comment 'HTTP'
   sudo ufw allow 443/tcp comment 'HTTPS'
   sudo ufw --force enable
   sudo ufw --force delete allow 2222/tcp
   sudo ufw limit 2222/tcp comment 'SSH rate-limited'
   sudo ufw logging medium
   sudo hostnamectl set-hostname devops-vm
   sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
   sudo ufw status verbose
   hostname -f
   ```

6. Проверьте `.102` через `ip -brief address`, актуальность Windows hosts
   и ProxyCommand; при смене DHCP-адреса обновите их. На Windows:
   `ssh -o BatchMode=yes devops.local hostname -f`.

7. Скопируйте скрипт из этого репозитория в ВМ и запустите:

   ```powershell
   ssh devops 'mkdir -p ~/devops-course-2026/scripts'
   scp .\scripts\audit.sh devops:devops-course-2026/scripts/audit.sh
   ssh -t devops 'cd ~/devops-course-2026 && bash scripts/audit.sh; echo EXIT_CODE=$?'
   ```

   Ожидаются `Passed: 6, failed: 0` и код 0. `MaxAuthTries 10` временно
   дает `Passed: 5, failed: 1`, код 1; после теста обязательно вернуть 3.
   Для проверки файловой конфигурации через `sshd -T` перезапуск службы
   во время намеренного нарушения не требуется.

## Дополнительная проверка туннеля

На ВМ создан `/home/devops/restricted/index.html`. Временный сервер
`python3 -m http.server 8080 --bind 127.0.0.1` отдавал страницу через
`ssh -L 127.0.0.1:9090:127.0.0.1:8080 -N devops` с ответом HTTP 200.
После проверки туннель и тестовый HTTP-процесс остановлены; файл страницы
сохранен для повторения опыта. Разрешающее правило UFW для 8080 не добавлялось.

## 8. Веб-сервер

Практическая работа 6, 30 октября 2026 года. Перед началом выполнен откат
на `01-clean-install`, затем конфигурация разделов 1–7 восстановлена по этому
документу. Прежнее полное состояние отдельно сохранено в
`03-practice5-complete`. Снимок `04-nginx-https` содержит настроенный HTTPS
с временной страницей до доставки содержимого репозитория.

### Пакеты и ресурс

```bash
sudo apt update
sudo apt install -y nginx rsync
sudo install -d -m 755 -o devops -g devops /var/www/devops-site
```

Использован пакет `nginx` из репозитория Ubuntu, версия 1.28.3.
Ресурс: `/var/www/devops-site`, владелец `devops:devops`, каталоги 755,
файлы 644. Пользователь `www-data` читает содержимое, но не изменяет его.
Главный процесс Nginx работает от root, рабочие процессы — от www-data.

### Сертификат и конфигурация

Самоподписанный сертификат формируется один раз на сервере:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' \
  -addext 'subjectAltName=DNS:devops.local'
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Закрытый ключ `/etc/ssl/private/devops.key` остается на сервере, root:root 600.
Открытый сертификат `/etc/ssl/certs/devops.crt` имеет root:root 644.
CN и issuer равны `devops.local`, SAN содержит `DNS:devops.local`.
Срок фактического сертификата: 30.10.2026 01:24:01 UTC —
30.10.2027 01:24:01 UTC. При воспроизведении даты изменятся.
Root читает ключ при запуске/перезагрузке конфигурации; рабочим процессам
не требуется право самостоятельно открывать файл ключа.

Файл `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Активировать конфигурацию ссылкой, отключить только ссылку default,
оставляя `/etc/nginx/sites-available/default`:

```bash
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo unlink /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Повторно создавать существующую ссылку или удалять отсутствующую не нужно.
Каждое последующее изменение проверять `nginx -t` до reload. HSTS для
учебного самоподписанного сертификата не добавляется. Правила UFW для
80 и 443 уже существуют; профиль Nginx Full дополнительно не разрешается.

### Доставка с Windows через WSL 1

На хосте используется Ubuntu в WSL 1, без запуска гипервизора WSL 2.
Установить `rsync`, `openssh-client`, `git`, `curl`. Ключ Windows
`C:\Users\TPC\.ssh\devops_vm` скопировать в собственный `~/.ssh` WSL,
задать каталогу 700, ключу и config 600. Проверенный открытый ключ сервера
сохранить в known_hosts. Не использовать закрытый ключ непосредственно
из `/mnt/c` и не включать его в репозиторий. Псевдоним `devops` соответствует
HostName 127.0.0.1, Port 2222, User devops, IdentityFile ~/.ssh/devops_vm,
IdentitiesOnly yes. Репозиторий доступен как `/mnt/e/Git/devops_vm`;
`git config core.fileMode false` устраняет ложные изменения режимов на DrvFS.

Открытый сертификат получить по доверенному SSH-каналу:

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
rsync -avz --delete --dry-run --chmod=D755,F644 site/ devops:/var/www/devops-site/
rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/
```

В этой конфигурации VPN блокирует прямой Host-only, поэтому для проверок
с Windows/WSL добавлены NAT-пробросы TCP 127.0.0.1:80 → гостевой 80 и
127.0.0.1:443 → гостевой 443. Они доступны только локальному хосту.
Имя devops.local в Windows hosts остается сопоставлено с 192.168.56.102.
Проверка HTTPS через NAT сохраняет Host/SNI и проверяет сертификат:

```bash
curl --noproxy '*' --resolve devops.local:80:127.0.0.1 -I http://devops.local/
curl --noproxy '*' --resolve devops.local:443:127.0.0.1 \
  --cacert ~/devops.crt -I https://devops.local/
DEPLOY_RESOLVE=devops.local:443:127.0.0.1 scripts/deploy.sh --dry-run
DEPLOY_RESOLVE=devops.local:443:127.0.0.1 scripts/deploy.sh
```

Первый запуск новой команды rsync с `--delete` всегда предварять dry run.
Штатный deploy требует чистого Git, включая индекс и неигнорируемые новые
файлы, проверяет наличие index.html, нормализует права и возвращает 1 при
неудаче синхронизации или HTTPS-проверки. Используется одно SSH-соединение
на запуск; не выполнять шесть новых SSH-подключений за 30 секунд.

### Аудит

Скопировать `scripts/audit.sh` на сервер и выполнить с sudo для проверки
sshd, UFW, Nginx и прав ключа. Нормальный результат — 10 успешных проверок,
код 0. `AUDIT_CERT_MIN_DAYS=400` намеренно дает код 1; файл ресурса с
правами 666 также дает код 1. После опыта вернуть 644 и повторить аудит.

## 9. Контейнеризация

Практическая работа 7, 30 октября 2026 года. Docker Engine 29.9.2 и
Docker Compose v5.6.1 установлены из официального APT-репозитория Docker,
без пакета docker.io. Инструкция: https://docs.docker.com/engine/install/ubuntu/ .
Для установленной Ubuntu 26.04 LTS используется suite resolute, amd64:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod 644 /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
```

Открыть новую SSH-сессию. Из учебных учетных записей в группе docker состоит
только devops, уже имеющий sudo. Эта группа дает фактические полномочия root.
Проверки: docker version, docker compose version, docker run --rm hello-world.

### Проект и секреты

Исходники хранятся в app/ репозитория, проект на сервере — /home/devops/app,
владелец devops:devops. Доставка с хоста из WSL 1 сначала в пробном режиме:

```bash
rsync -avz --delete --exclude=.env --chmod=D755,F644 --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/
```

Нормализация 755/644 нужна для исходников с DrvFS. Dockerfile использует
python:3.12-slim, пользователя app, порт 5000 и exec-форму CMD Gunicorn.
Внутри образа исходники принадлежат root:root и имеют 644: app их читает,
но не перезаписывает. requirements.txt копируется отдельно до установки
зависимостей, поэтому изменение app.py не сбрасывает кэш pip install.

Файл /home/devops/app/.env создается только на сервере, devops:devops 600:

```bash
cd /home/devops/app
umask 077
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
```

Это первоначальная настройка: существующий секрет при обновлении не заменять.
POSTGRES_DB и POSTGRES_USER равны app, DB_HOST=db, пароль случайный.
.gitignore и app/.dockerignore исключают .env, rsync --exclude=.env сохраняет
его при --delete. В Git хранится только .env.example с заглушкой change_me.
Не публиковать полный docker compose config или inspect с окружением;
для проверки использовать docker compose config --quiet.

### Сеть том и запуск

```bash
cd /home/devops/app
docker compose up -d --build --wait --wait-timeout 90
docker compose ps
docker compose exec -T app id </dev/null
docker compose exec -T app getent hosts db </dev/null
```

Конфигурация — app/docker-compose.yml, имя проекта app задается каталогом.
Сервисы app и db работают в пользовательской bridge-сети app_backend,
встроенный DNS разрешает db в текущий IP контейнера БД. Контейнеры называются
app-app-1 и app-db-1. PostgreSQL использует postgres:16-alpine,
pg_isready: интервал 5 секунд, тайм-аут 3 секунды, 5 попыток.
depends_on: service_healthy задерживает запуск app до готовности db.
У обоих сервисов restart: unless-stopped.

Публикуется только 127.0.0.1:5000:5000; порт БД 5432 не публикуется.
EXPOSE не публикует порт. Правила UFW для 5000/5001/5432 не добавляются.
Том app_db_data смонтирован в /var/lib/postgresql/data. Обычный down
сохраняет том; down -v использован только для синтетических посещений
этого нового проекта в упражнении. При штатном обновлении -v не применять.
Действующий проект, том и снимки после работы сохраняются.

### Обратный прокси

В HTTPS-блок /etc/nginx/sites-available/devops-site добавлено:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Статические root, location / и error_page из раздела 8 сохранены.
Применение: sudo nginx -t && sudo systemctl reload nginx.
Завершающий слеш proxy_pass заменяет префикс /app/ на /.
При включенном VPN проверки с WSL используют NAT с сохранением Host/SNI:

```bash
curl --noproxy '*' --resolve devops.local:443:127.0.0.1 --cacert ~/devops.crt https://devops.local/app/
curl --noproxy '*' --resolve devops.local:443:127.0.0.1 --cacert ~/devops.crt https://devops.local/app/health
curl --noproxy '*' --resolve devops.local:443:127.0.0.1 --cacert ~/devops.crt -I https://devops.local/
```

При 502 проверить 127.0.0.1:5000, docker compose ps/logs app и журнал
/var/log/nginx/devops-site.error.log. Connection refused у upstream
означает отказ между Nginx и приложением, после установления клиентского TLS.

### Аудит и снимок

Копия аудита: /home/devops/devops-course-2026/scripts/audit.sh.
Раздел [5] проверяет Docker, healthy у app-db-1, отсутствие внешних
слушающих сокетов 5000/5432 и права .env 600. Для 5000 дополнительно
требуется наличие 127.0.0.1:5000. Штатно — 14 проверок, код 0.
Временная публикация 5000:5000 дает код 1; после проверки вернуть
127.0.0.1:5000:5000 и пересоздать app. Снимок 05-docker-compose создается
после проверки Compose и тома, до настройки обратного прокси;
снимок 04-nginx-https сохраняется.
