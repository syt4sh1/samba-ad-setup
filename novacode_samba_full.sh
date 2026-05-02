#!/bin/bash
# ============================================================
# SCRIPT COMPLET SAMBA AD - NovaCode
# HOSTNAME: SRVLIN40 | IP: 192.168.40.15 | DOMINI: NovaCode.local
# Execució: sudo bash novacode_samba_full.sh
# ============================================================

set -e

DOMAIN="NovaCode.local"
REALM="NOVACODE.LOCAL"
NETBIOS="NOVACODE"
IP="192.168.40.15"
ADMINPASS="@ITB2025"
USERPASS="@ITB2025"

echo "=================================================="
echo " FASE 0 - PURGE COMPLET DE SAMBA"
echo "=================================================="
systemctl stop samba-ad-dc smbd nmbd winbind 2>/dev/null || true
systemctl disable samba-ad-dc smbd nmbd winbind 2>/dev/null || true
systemctl mask smbd nmbd 2>/dev/null || true

apt-get purge -y --auto-remove \
  samba samba-common samba-common-bin samba-dsdb-modules samba-vfs-modules \
  winbind libpam-winbind libnss-winbind libpam-krb5 krb5-config krb5-user \
  acl attr 2>/dev/null || true

rm -rf /etc/samba /var/lib/samba /var/cache/samba /run/samba
rm -f /etc/krb5.conf

echo "=================================================="
echo " FASE 1 - PREPARACIO SISTEMA"
echo "=================================================="

systemctl stop slapd 2>/dev/null || true
systemctl disable slapd 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
systemctl mask systemd-resolved.service 2>/dev/null || true
systemctl stop systemd-resolved.service 2>/dev/null || true
rm -f /etc/resolv.conf

hostnamectl set-hostname SRVLIN40
echo "SRVLIN40" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
${IP}           SRVLIN40.${DOMAIN} SRVLIN40
EOF

# DNS temporal per descarregar paquets
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

echo "=================================================="
echo " FASE 2 - INSTALLACIO PAQUETS"
echo "=================================================="
export DEBIAN_FRONTEND=noninteractive

echo "krb5-config krb5-config/default_realm string ${REALM}" | debconf-set-selections
echo "krb5-config krb5-config/kerberos_servers string SRVLIN40.${DOMAIN}" | debconf-set-selections
echo "krb5-config krb5-config/admin_server string SRVLIN40.${DOMAIN}" | debconf-set-selections

apt-get update -qq
apt-get install -y \
  acl attr \
  samba samba-dsdb-modules samba-vfs-modules \
  winbind libpam-winbind libnss-winbind libpam-krb5 \
  krb5-config krb5-user \
  wget

echo "=================================================="
echo " FASE 3 - PROVISIO DOMINI SAMBA AD DC"
echo "=================================================="

mv /etc/samba/smb.conf /etc/samba/smb.conf_orig 2>/dev/null || true
mv /etc/krb5.conf /etc/krb5.conf_orig 2>/dev/null || true

samba-tool domain provision \
  --use-rfc2307 \
  --realm="${REALM}" \
  --domain="${NETBIOS}" \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --dns-forwarder=8.8.8.8 \
  --adminpass="${ADMINPASS}" \
  --host-name=SRVLIN40 \
  --host-ip="${IP}"

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Ara DNS apunta al servidor
chattr -i /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf <<EOF
nameserver ${IP}
nameserver 8.8.8.8
search ${DOMAIN}
EOF
chattr +i /etc/resolv.conf 2>/dev/null || true

echo "=================================================="
echo " FASE 4 - ARRANCAR SAMBA AD DC"
echo "=================================================="
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
sleep 5

systemctl is-active samba-ad-dc && echo "OK samba-ad-dc actiu" || echo "ERROR samba-ad-dc"

echo "=================================================="
echo " FASE 5 - OUs GRUPS I USUARIS"
echo "=================================================="

samba-tool ou create "OU=Oficines,DC=NovaCode,DC=local" \
  --description="Personal d oficines NovaCode"
samba-tool ou create "OU=Desenvolupament,DC=NovaCode,DC=local" \
  --description="Equip de desenvolupadors NovaCode"
samba-tool ou create "OU=Direccio,DC=NovaCode,DC=local" \
  --description="Direccio de NovaCode"

samba-tool group add "gOficines" \
  --groupou="OU=Oficines" \
  --description="Grup personal oficines"
samba-tool group add "gDesenvolupament" \
  --groupou="OU=Desenvolupament" \
  --description="Grup desenvolupadors"
samba-tool group add "gDireccio" \
  --groupou="OU=Direccio" \
  --description="Grup direccio"

samba-tool user create "uOficinista" "${USERPASS}" \
  --userou="OU=Oficines" \
  --given-name="Usuari" --surname="Administratiu" \
  --must-change-at-next-login=false

samba-tool user create "uDesenvolupadora" "${USERPASS}" \
  --userou="OU=Desenvolupament" \
  --given-name="Usuaria" --surname="Programadora" \
  --must-change-at-next-login=false

samba-tool user create "uDirectora" "${USERPASS}" \
  --userou="OU=Direccio" \
  --given-name="Usuaria" --surname="Gestora" \
  --must-change-at-next-login=false

# uDirectora2 necessari per P4.7 Ex2 (denegar acces individual)
samba-tool user create "uDirectora2" "${USERPASS}" \
  --userou="OU=Direccio" \
  --given-name="Usuaria2" --surname="Gestora2" \
  --must-change-at-next-login=false

samba-tool group addmembers "gOficines" uOficinista
samba-tool group addmembers "gDesenvolupament" uDesenvolupadora
samba-tool group addmembers "gDireccio" uDirectora
samba-tool group addmembers "gDireccio" uDirectora2

echo "Usuaris:"
samba-tool user list
echo "Grups:"
samba-tool group list
echo "OUs:"
samba-tool ou list

echo "=================================================="
echo " FASE 6 - CREAR DIRECTORIS"
echo "=================================================="

mkdir -p /var/NovaCode/{cHisenda,cComptes,cProjectes,cProduccio,nomines}
mkdir -p /var/software
mkdir -p /home/NovaCode/{uDirectora,uDesenvolupadora,uOficinista}

wget -q -O /var/software/7z2403-linux-x64.tar.xz \
  "https://www.7-zip.org/a/7z2403-linux-x64.tar.xz" 2>/dev/null \
  || echo "fitxer de prova" > /var/software/readme.txt

echo "=================================================="
echo " FASE 7 - PERMISOS"
echo "=================================================="

# cHisenda: gDireccio rw, reste sense acces
chmod 770 /var/NovaCode/cHisenda
chown root:root /var/NovaCode/cHisenda

# cComptes: gOficines rw, gDireccio r
chmod 770 /var/NovaCode/cComptes
chown root:root /var/NovaCode/cComptes

# cProjectes: gDesenvolupament rw, gDireccio r
chmod 770 /var/NovaCode/cProjectes
chown root:root /var/NovaCode/cProjectes

# cProduccio: gDesenvolupament rw
chmod 770 /var/NovaCode/cProduccio
chown root:root /var/NovaCode/cProduccio

# nomines: gOficines, fitxers privats del creador
chmod 770 /var/NovaCode/nomines
chown root:root /var/NovaCode/nomines

# software: lectura per a tothom
chmod 755 /var/software
chown root:root /var/software

# homes
chmod 750 /home/NovaCode/uDirectora
chmod 750 /home/NovaCode/uDesenvolupadora
chmod 750 /home/NovaCode/uOficinista

ls -la /var/NovaCode/

echo "=================================================="
echo " FASE 8 - SMB.CONF"
echo "=================================================="

cat > /etc/samba/smb.conf <<'SMBEOF'
[global]
    workgroup = NOVACODE
    realm = NOVACODE.LOCAL
    netbios name = SRVLIN40
    server role = active directory domain controller
    dns forwarder = 8.8.8.8
    idmap_ldb:use rfc2307 = yes
    log file = /var/log/samba/%m.log
    log level = 1

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No

[netlogon]
    path = /var/lib/samba/sysvol/novacode.local/scripts
    read only = No

# Recurs anonim (P4.6 Ex3)
[software]
    comment = Software disponible anonimament
    path = /var/software
    read only = Yes
    guest ok = Yes
    browseable = Yes

# cHisenda: gDireccio escriptura (P4.6 Ex4)
# Prova escriptura: uDirectora pot escriure
# Prova acces denegat: uDesenvolupadora NO pot accedir
[cHisenda]
    comment = Hisenda i comptabilitat - Direccio
    path = /var/NovaCode/cHisenda
    valid users = @gDireccio
    write list = @gDireccio
    read only = No
    browseable = Yes
    create mask = 0770
    directory mask = 0770

# cComptes: gOficines escriptura, gDireccio lectura (P4.6 Ex4)
[cComptes]
    comment = Comptes - Oficines escriptura Direccio lectura
    path = /var/NovaCode/cComptes
    valid users = @gOficines @gDireccio
    write list = @gOficines
    read only = Yes
    browseable = Yes
    create mask = 0770
    directory mask = 0770

# cProjectes: gDesenvolupament escriptura, gDireccio lectura (P4.6 Ex4)
# Prova lectura: uDirectora veu pero no pot escriure
[cProjectes]
    comment = Projectes - Desenvolupament escriptura Direccio lectura
    path = /var/NovaCode/cProjectes
    valid users = @gDesenvolupament @gDireccio
    write list = @gDesenvolupament
    read only = Yes
    browseable = Yes
    create mask = 0770
    directory mask = 0770

# cProduccio: gDesenvolupament escriptura (P4.6 Ex4)
[cProduccio]
    comment = Produccio - Desenvolupament
    path = /var/NovaCode/cProduccio
    valid users = @gDesenvolupament
    write list = @gDesenvolupament
    read only = No
    browseable = Yes
    create mask = 0770
    directory mask = 0770

# nomines: gOficines, fitxers privats del propietari (P4.7 Ex4)
[nomines]
    comment = Nomines - privat per propietari
    path = /var/NovaCode/nomines
    valid users = @gOficines
    write list = @gOficines
    read only = No
    browseable = Yes
    create mask = 0600
    directory mask = 0700
    force create mode = 0600
    force directory mode = 0700

# homes: directori personal per usuari (P4.7 Ex6)
[homes]
    comment = Directoris personals usuaris
    browseable = No
    read only = No
    valid users = %U %D%w%U
    path = /home/NovaCode/%S
    create mask = 0600
    directory mask = 0700
SMBEOF

echo "OK smb.conf escrit"
testparm -s 2>&1 | tail -5

echo "=================================================="
echo " FASE 9 - NSSWITCH WINBIND"
echo "=================================================="

# Afegir winbind a passwd i group (evitant duplicats)
if ! grep -q "winbind" /etc/nsswitch.conf; then
  sed -i 's/^passwd:\(.*\)/passwd:\1 winbind/' /etc/nsswitch.conf
  sed -i 's/^group:\(.*\)/group:\1 winbind/' /etc/nsswitch.conf
fi

grep -E "^passwd|^group" /etc/nsswitch.conf

echo "=================================================="
echo " FASE 10 - REINICI SERVEIS"
echo "=================================================="

systemctl restart samba-ad-dc
systemctl enable winbind
systemctl start winbind
sleep 4

echo ""
echo "samba-ad-dc: $(systemctl is-active samba-ad-dc)"
echo "winbind:     $(systemctl is-active winbind)"

echo "=================================================="
echo " VERIFICACIO FINAL"
echo "=================================================="

echo "Usuaris finals:"
samba-tool user list

echo ""
echo "Test recursos:"
smbclient -L localhost -U "Administrator%${ADMINPASS}" 2>/dev/null \
  | grep -E "Disk|software|cHisenda|cComptes|cProjectes|cProduccio|nomines" \
  || echo "Comprova: smbclient -L ${IP} -U Administrator%${ADMINPASS}"

echo ""
echo "=========================================================="
echo "  SAMBA AD DC CONFIGURAT"
echo "=========================================================="
echo "  Domini:   NovaCode.local"
echo "  IP:       ${IP}"
echo "  Admin:    Administrator / ${ADMINPASS}"
echo ""
echo "  USUARIS (password: ${USERPASS}):"
echo "    uOficinista      -> gOficines      -> cComptes(rw)"
echo "    uDesenvolupadora -> gDesenvolupament -> cProjectes(rw) cProduccio(rw)"
echo "    uDirectora       -> gDireccio      -> cHisenda(rw) cComptes(r) cProjectes(r)"
echo "    uDirectora2      -> gDireccio      -> igual que uDirectora"
echo ""
echo "  PROVES EX4 (P6.5) des de Windows 10:"
echo "    Explorador:  \\\\${IP}"
echo "    Escriptura:  uDirectora    -> \\\\${IP}\\cHisenda (pot escriure)"
echo "    Lectura:     uDirectora    -> \\\\${IP}\\cProjectes (NO pot escriure)"
echo "    Denegat:     uDesenvolupadora -> \\\\${IP}\\cHisenda (acces denegat)"
echo "    Permanent:   net use Z: \\\\${IP}\\cHisenda /persistent:yes"
echo ""
echo "  Windows 10 unio al domini:"
echo "    1. DNS primari -> ${IP}"
echo "    2. Propietats sistema -> Canviar -> Domini: NovaCode.local"
echo "    3. Usuari: Administrator / ${ADMINPASS}"
echo "    4. Verificar: samba-tool computer list"
echo "=========================================================="
