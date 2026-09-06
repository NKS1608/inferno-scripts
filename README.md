# Inferno no macOS Apple Silicon

*Português · [English](README.en.md)*

Scripts e manual para rodar o [Inferno](https://chefkiss.dev/guides/inferno/) da
ChefKiss — um iPhone 11 (t8030) emulado — num Mac Apple Silicon.

O guia oficial é a fonte da verdade. Isto aqui é o que sobrou depois de executá-lo
de ponta a ponta: os desvios que o macOS exigiu, a ordem que funciona, e um
launcher que não deixa você errar a sequência.

Testado em macOS 15.7, M4, 16 GB. Restaurado com iOS 14.0 beta 5 (`18A5351d`) em
`iPhone12,1`.

## O que você precisa fornecer

Os scripts **não** baixam nada disso, e nem devem:

- o `.ipsw` de uma versão suportada para o seu device;
- a SEP ROM correspondente (para o t8030, `Cebu B1`);
- o IV e a chave do SEP firmware daquele build específico, do
  [The Apple Wiki](https://theapplewiki.com/).

O guia é explícito: não compartilhe ipsw, imagens, firmware decriptado, tickets,
IVs ou chaves, e não automatize o download nem o patch desses arquivos. Isso viola
a EULA da Apple e pode ser crime na sua jurisdição. O `.gitignore` deste repo é
uma whitelist justamente para nada disso entrar por acidente.

## Requisitos

- macOS em Apple Silicon, Homebrew, `cmake`, `python3`.
- ~40 GB livres: ipsw 5 GB, `Restore/` extraído 0,5 GB, disco `root` ~8 GB depois
  do restore, VM companion ~6 GB.
- Paciência. O restore leva mais de uma hora, e a UI depois roda em software
  rendering.

## Setup do zero

Trabalhe sempre num diretório só, aqui chamado de `InfernoData`. Os scripts assumem
que estão na raiz dele.

### 1. Host

```sh
brew install libtool meson ninja pkgconf dtc glib gnutls jpeg-turbo libpng \
  libslirp libssh libusb lzo ncurses pixman snappy vde zstd libtasn1 lzfse

git clone https://github.com/ChefKissInc/Inferno && cd Inferno
git submodule update --init
mkdir build && cd build
LIBTOOL="glibtool" ../configure --target-list=aarch64-softmmu,x86_64-softmmu \
  --disable-guest-agent --enable-lzfse --enable-slirp --enable-curses \
  --enable-libssh --enable-virtfs --enable-zstd --extra-cflags=-DNCURSES_WIDECHAR=1 \
  --disable-sdl --disable-gtk --enable-cocoa --enable-nettle --enable-gnutls \
  --extra-cflags="-I/opt/homebrew/include" --extra-ldflags="-L/opt/homebrew/lib" \
  --disable-werror --disable-qom-cast-debug --disable-debug-info --disable-fuse
ninja
```

`--disable-fuse` não está no guia e é obrigatório no macOS: `block/export/fuse.c`
não compila contra os headers do macFUSE.

O build só produz `qemu-system-*-unsigned`. Assine para o HVF da companion
funcionar:

```sh
cd Inferno/build
for b in qemu-system-aarch64 qemu-system-x86_64; do
  codesign --entitlements ../accel/hvf/entitlements.plist --force -s - ./$b-unsigned
  cp ./$b-unsigned ./$b
done
```

### 2. Arquivos

```sh
python3 -m venv venv && ./venv/bin/pip install pyasn1 pyasn1-modules

for d in "root 32G" "firmware 8M" "syscfg 128K" "ctrl_bits 8K" "nvram 8K" \
         "effaceable 4K" "panic_log 1M" "sep_nvram 64K" "sep_ssc 128K"; do
  set -- $d; Inferno/build/qemu-img create -f raw "$1" "$2"
done
```

Em `zsh`, `set -- $d` não faz word splitting — rode os nove `qemu-img create` na
mão, ou use `bash`.

Coloque o ipsw na pasta, extraia sem o `.dmg` grande (é o OS; o `idevicerestore`
lê direto do ipsw), pegue os scripts de ticket e o `img4lib`:

```sh
mkdir Restore
unzip -q "SEU.ipsw" -x "038-44337-083.dmg" -d Restore     # ajuste o nome do dmg

for f in create_apticket.py create_septicket.py ticket.shsh2 idevicerestore.patch; do
  curl -LO "https://chefkiss.dev/Extras/Inferno/$f"
done

git clone https://github.com/xerub/img4lib && cd img4lib
git submodule update --init
make LDFLAGS="-L/opt/homebrew/opt/openssl/lib -L/opt/homebrew/opt/lzfse/lib" \
     CFLAGS='-I/opt/homebrew/opt/openssl/include -I/opt/homebrew/opt/lzfse/include -O2 -I. -g -DiOS10 -DDER_MULTIBYTE_TAGS=1 -DDER_TAG_SIZE=8 -D__unused="__attribute__((unused))"'
```

Tickets e SEP firmware (`n104ap` é o iPhone 11 — ajuste para o seu device):

```sh
./venv/bin/python3 create_apticket.py  n104ap Restore/BuildManifest.plist ticket.shsh2 root_ticket.der
./venv/bin/python3 create_septicket.py n104ap Restore/BuildManifest.plist ticket.shsh2 sep_root_ticket.der

KEY=<IV><KEY>    # concatenados, sem espaço, do The Apple Wiki, para o SEU build
V=$(img4lib/img4 -v -i Restore/Firmware/all_flash/sep-firmware.n104.RELEASE.im4p \
      -o sep-firmware.n104.RELEASE -k $KEY)
img4lib/img4 -A -F -o sep-firmware.n104.RELEASE.new.img4 -i sep-firmware.n104.RELEASE \
      -M sep_root_ticket.der -T rsep -V "$V"
```

O último comando deve imprimir só `none`. IV e chave são diferentes para cada
build **e** cada device — confira três vezes. Errar aqui dá panic de `dart-sep`
lá na frente, não um erro aqui.

### 3. Companion

O guia sugere uma VM x86_64 emulada. Aqui usamos **Debian arm64 com HVF** — o
`usb-tcp-remote` existe no alvo `aarch64` também, então ela roda acelerada em vez
de emulada.

```sh
mkdir companion && cd companion
bzcat ../Inferno/pc-bios/edk2-aarch64-code.fd.bz2 > edk2-aarch64-code.fd
dd if=/dev/zero of=edk2-arm-vars.fd bs=1m count=64
curl -LO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2
../Inferno/build/qemu-img resize debian-13-generic-arm64.qcow2 12G
hdiutil makehybrid -iso -joliet -iso-volume-name CIDATA -joliet-volume-name CIDATA -o seed.iso seed
```

O `companion/seed/user-data` deste repo já instala as dependências, monta o
`InfernoData` em `/mnt/inferno` via 9p e compila a stack do libimobiledevice
(`libplist`, `libimobiledevice-glue`, `libusbmuxd`, `libtatsu`, `libimobiledevice`,
`libirecovery`, `usbmuxd`, `idevicerestore`) já com o patch da ChefKiss aplicado.

Duas coisas que o cloud-init não resolve sozinho:

- `libplist` precisa de `--without-cython` — as bindings Python não compilam sem
  `python-is-python3`, e nada aqui as usa.
- o `usbmuxd` compilado do source não instala unit nem regra de udev a menos que
  você passe os diretórios:

  ```sh
  ./configure --with-udevrulesdir=/lib/udev/rules.d \
              --with-systemdsystemunitdir=/lib/systemd/system
  ```

  Sem isso o `idevicerestore` nunca enxerga o device. O serviço fica `inactive`
  quando não há device conectado — isso é normal, ele é ativado por udev.

## Uso diário

```sh
./inferno.sh boot     # sobe a companion se preciso, depois o iPhone
./inferno.sh status
./inferno.sh stop
```

A companion **tem** que subir antes da VM do iPhone: o USB do iPhone é o cliente
que conecta no socket `/tmp/InfernoUSBRemote` que a companion abre. O `inferno.sh`
cuida disso.

## Restaurar

Apaga o disco `root`. Só faz sentido na primeira vez ou se a instalação quebrou.

```sh
./inferno.sh restore   # a VM fecha sozinha quando o estágio 1 termina
./inferno.sh patch     # filesystem patches (pede sudo)
./inferno.sh boot      # migração de dados + tela de setup
```

`restore` arma na companion um watcher que só dispara o `idevicerestore` depois
que o USB do iPhone aparece no sysfs. Disparar antes dá
`Unable to discover device mode`. Acompanhe com `./inferno.sh log`.

O `patch` monta o `root`, roda o
[InfernoFSPatcher](https://git.chefkiss.dev/AppleHax/InfernoFSPatcher) no
`dyld_shared_cache_arm64e` (é isso que habilita o software rendering — não há
emulação de GPU), desabilita cinco launch daemons que quebram o boot
(`voicemail.vmd`, os três `CommCenter*`, `locationd`) e ejeta. Ele aborta se não
achar os cinco, em vez de gravar um plist pela metade. O `launchd.plist` original
fica salvo ao lado.

Clone e compile o patcher antes do primeiro `patch`:

```sh
git clone https://git.chefkiss.dev/AppleHax/InfernoFSPatcher && cd InfernoFSPatcher
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
```

## Botões do device

| Tecla | Ação             | Tecla  | Ação              |
|-------|------------------|--------|-------------------|
| F1    | Desligar à força | F5     | Power/lateral     |
| F2    | Toggle ringer    | F6     | Home              |
| F3    | Volume −         | F7/F8  | Help / Help duplo |
| F4    | Volume +         | F9/F10 | Hall effect       |

Home screen: F6 uma vez. App switcher: F6 duas vezes.
SOS/desligar: segure F4 e, ~meio segundo depois, F5 — não simultâneo.

## Nunca faça

- **Não** configure passcode — não funciona.
- **Não** ative serviços de localização.
- **Não** use "Apagar Conteúdo e Ajustes" — brica a instalação.
- **Não** modifique os tickets depois do restore. Eles são exigidos em todos os
  estágios de boot, não só na instalação.

## Sobre performance

A VM do iPhone é TCG puro, e vai continuar sendo. O A13 é emulado com sysregs
proprietários da Apple (GXF/APRR) registrados à mão em
`hw/arm/apple-silicon/a13_gxf.c`; o Hypervisor.framework expõe o host com um
conjunto fixo de features e não deixa registrar nem interceptar isso. Não há
uma linha de `hvf` em `hw/arm/apple-silicon/`.

O que dá para fazer: `-accel tcg,tb-size=1024` (já está no `run-iphone.sh`), MTTCG
já ligado por padrão, e a companion acelerada. Num M4 (4 P-cores + 6 E-cores) as
7 vCPUs se espalham e a maioria cai nos E-cores; não há afinidade de thread no
macOS.

Para jogos o gargalo não é a CPU emulada, é não ter GPU nenhuma.

## Arquivos

| Arquivo | O quê |
|---|---|
| `inferno.sh` | launcher: `boot`, `restore`, `patch`, `shell`, `log`, `status`, `stop` |
| `run-iphone.sh` | comando QEMU do device (`SERIAL=file:x.log` redireciona o serial) |
| `run-companion.sh` | comando QEMU da companion |
| `patch-fs.sh` | filesystem patches, roda como root |
| `wait-and-restore.sh` | roda **dentro** da companion; espera o USB e chama `idevicerestore` |
| `companion/seed/user-data` | cloud-init da companion |

Companion: `./inferno.sh shell` (ou `ssh -p 32222 inferno@127.0.0.1`, senha
`inferno`). O `InfernoData` aparece lá em `/mnt/inferno`, read-only.

Os nomes de arquivo em `run-iphone.sh` e `wait-and-restore.sh` são do iOS 14.0
beta 5 no iPhone 11. Trocando de versão ou device, ajuste ramdisk, trustcache,
kernelcache, device tree e SEP firmware.

## Quando der problema

| Sintoma | Causa |
|---|---|
| Trava em "skipping unencrypted volume" ou "SEP accepted IMG4" | Instabilidade conhecida. Reinicie até passar. |
| `Unable to discover device mode` | Companion subiu depois do iPhone, ou `usbmuxd` não está ativo. Use `./inferno.sh restore`. |
| `at24c-eeprom: Backing file size ...` | `truncate -c -s 64K ./sep_nvram` |
| panic `dart-sep ... TTBR invalid` | SEP ROM ou SEP firmware errados. |
| panic `cannot find IOAESAccelerator` | Bootou sem o ramdisk, ou disco corrompido. |
| Não consegue montar o `root` como read-write | macOS antigo demais. |

O log serial do iPhone só é gravado quando você inicia com `SERIAL=file:...`.
Lista completa: <https://chefkiss.dev/guides/inferno/troubleshooting/>
