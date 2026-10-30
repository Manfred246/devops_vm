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
