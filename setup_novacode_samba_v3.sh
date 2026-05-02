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
echo " FASE 0 - DESINSTAL·LAR SAMBA COMPLETAMENT"
echo "=================================================="
systemctl stop samba-ad-dc smbd nmbd winbind 2>/dev/null || true
systemctl disable samba-ad-dc smbd nmbd winbind 2>/dev/null || true

apt-get purge -y samba samba-common samba-dsdb-modules samba-vfs-modules \
  winbind libpam-winbind libnss-winbind libpam-krb5 krb5-config krb5-user \
  acl attr 2>/dev/null || true

apt-get autoremove -y 2>/dev/null || true

# Eliminar fitxers residuals
rm -rf /etc/samba /var/lib/samba /var/cache/samba /run/samba
rm -f /etc/krb5.conf

echo "=================================================="
echo " FASE 1 - PREPARACIÓ DEL SISTEMA"
echo "=================================================="

# Desactivar serveis conflictius
systemctl stop slapd 2>/dev/null || true
systemctl disable slapd 2>/dev/null || true
systemctl mask systemd-resolved.service 2>/dev/null || true
systemctl stop systemd-resolved.service 2>/dev/null || true
rm -f /etc/resolv.conf

# Configurar hostname
hostnamectl set-hostname SRVLIN40
echo "SRVLIN40" > /etc/hostname

# Configurar /etc/hosts
cat > /etc/hosts <<EOF
127.0.0.1       localhost
${IP}           SRVLIN40.${DOMAIN} SRVLIN40
EOF

# Configurar DNS
cat > /etc/resolv.conf <<EOF
nameserver ${IP}
nameserver 8.8.8.8
search ${DOMAIN}
EOF
chattr +i /etc/resolv.conf 2>/dev/null || true

echo "=================================================="
echo " FASE 2 - INSTAL·LAR SAMBA I PAQUETS"
echo "=================================================="
export DEBIAN_FRONTEND=noninteractive

# Pre-configurar Kerberos per evitar preguntes interactives
cat > /etc/krb5.conf.debconf <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
EOF

echo "krb5-config krb5-config/default_realm string ${REALM}" | debconf-set-selections
echo "krb5-config krb5-config/kerberos_servers string SRVLIN40" | debconf-set-selections
echo "krb5-config krb5-config/admin_server string SRVLIN40" | debconf-set-selections

apt-get update -qq
apt-get install -y acl attr samba samba-dsdb-modules samba-vfs-modules \
  winbind libpam-winbind libnss-winbind libpam-krb5 krb5-config krb5-user

echo "=================================================="
echo " FASE 3 - PROVISIÓ DEL DOMINI SAMBA AD"
echo "=================================================="

# Eliminar configuració per defecte
mv /etc/samba/smb.conf /etc/samba/smb.conf_orig 2>/dev/null || true
mv /etc/krb5.conf /etc/krb5.conf_orig 2>/dev/null || true

# Provisió no interactiva
samba-tool domain provision \
  --use-rfc2307 \
  --realm="${REALM}" \
  --domain="${NETBIOS}" \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --dns-forwarder=8.8.8.8 \
  --adminpass="${ADMINPASS}"

# Copiar Kerberos
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

echo "=================================================="
echo " FASE 4 - ARRANCAR SAMBA AD"
echo "=================================================="
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
sleep 3
systemctl status samba-ad-dc --no-pager || true

echo "=================================================="
echo " FASE 5 - CREAR OUs, GRUPS I USUARIS"
echo "=================================================="

# OUs
samba-tool ou create "OU=Oficines,DC=NovaCode,DC=local" \
  --description="Unitat organitzativa del personal d'oficines"
samba-tool ou create "OU=Desenvolupament,DC=NovaCode,DC=local" \
  --description="Unitat organitzativa dels desenvolupadors"
samba-tool ou create "OU=Direccio,DC=NovaCode,DC=local" \
  --description="Unitat organitzativa de la direccio"

# Grups
samba-tool group add "gOficines" \
  --groupou="OU=Oficines" \
  --description="Grup del personal d'oficines"
samba-tool group add "gDesenvolupament" \
  --groupou="OU=Desenvolupament" \
  --description="Grup dels desenvolupadors"
samba-tool group add "gDireccio" \
  --groupou="OU=Direccio" \
  --description="Grup de la direccio"

# Usuaris
samba-tool user create "uOficinista" "${USERPASS}" \
  --userou="OU=Oficines" \
  --surname="Administratiu" \
  --given-name="Usuari" \
  --must-change-at-next-login=false

samba-tool user create "uDesenvolupadora" "${USERPASS}" \
  --userou="OU=Desenvolupament" \
  --surname="Programadora" \
  --given-name="Usuaria" \
  --must-change-at-next-login=false

samba-tool user create "uDirectora" "${USERPASS}" \
  --userou="OU=Direccio" \
  --surname="Gestora" \
  --given-name="Usuaria" \
  --must-change-at-next-login=false

# Usuari extra per P4.7 (uDirectora2)
samba-tool user create "uDirectora2" "${USERPASS}" \
  --userou="OU=Direccio" \
  --surname="Gestora2" \
  --given-name="Usuaria2" \
  --must-change-at-next-login=false

# Afegir usuaris als grups
samba-tool group addmembers "gOficines" uOficinista
samba-tool group addmembers "gDesenvolupament" uDesenvolupadora
samba-tool group addmembers "gDireccio" uDirectora
samba-tool group addmembers "gDireccio" uDirectora2

echo "✓ OUs, grups i usuaris creats"
samba-tool user list
samba-tool group list
samba-tool ou list

echo "=================================================="
echo " FASE 6 - CREAR DIRECTORIS COMPARTITS"
echo "=================================================="

# Directoris principals
mkdir -p /var/NovaCode/{cHisenda,cComptes,cProjectes,cProduccio,nomines}
mkdir -p /var/software
mkdir -p /home/NovaCode/{uDirectora,uDesenvolupadora,uOficinista}

# Instal·lar wget si no hi és i baixar fitxer software
apt-get install -y wget 2>/dev/null || true
wget -q -O /var/software/7z2403-linux-x64.tar.xz \
  https://www.7-zip.org/a/7z2403-linux-x64.tar.xz 2>/dev/null || \
  echo "Info: no s'ha pogut descarregar 7zip (sense internet), creant fitxer de prova" && \
  echo "7-zip installer placeholder" > /var/software/7zip_installer.txt

echo "=================================================="
echo " FASE 7 - PERMISOS DE DIRECTORIS"
echo "=================================================="

# cHisenda: gDireccio rw, others ---
chown root:"NOVACODE\gDireccio" /var/NovaCode/cHisenda 2>/dev/null || \
  chown root:root /var/NovaCode/cHisenda
chmod 770 /var/NovaCode/cHisenda

# cComptes: gOficines rw, gDireccio r, others ---
chown root:"NOVACODE\gOficines" /var/NovaCode/cComptes 2>/dev/null || \
  chown root:root /var/NovaCode/cComptes
chmod 770 /var/NovaCode/cComptes

# cProjectes: gDesenvolupament rw, gDireccio r, others ---
chown root:"NOVACODE\gDesenvolupament" /var/NovaCode/cProjectes 2>/dev/null || \
  chown root:root /var/NovaCode/cProjectes
chmod 770 /var/NovaCode/cProjectes

# cProduccio: gDesenvolupament rw, others ---
chown root:"NOVACODE\gDesenvolupament" /var/NovaCode/cProduccio 2>/dev/null || \
  chown root:root /var/NovaCode/cProduccio
chmod 770 /var/NovaCode/cProduccio

# nomines: gOficines rw, mask 600 (solo propietari)
chown root:"NOVACODE\gOficines" /var/NovaCode/nomines 2>/dev/null || \
  chown root:root /var/NovaCode/nomines
chmod 770 /var/NovaCode/nomines

# software: lectura per a tothom (anonymous)
chown root:root /var/software
chmod 755 /var/software

# homes
chmod 750 /home/NovaCode/uDirectora
chmod 750 /home/NovaCode/uDesenvolupadora
chmod 750 /home/NovaCode/uOficinista

echo "✓ Permisos aplicats"
ls -la /var/NovaCode/

echo "=================================================="
echo " FASE 8 - CONFIGURAR SMB.CONF"
echo "=================================================="

cat > /etc/samba/smb.conf <<'SMBCONF'
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

# ---- Recurs anònim (P4.6 Ex3) ----
[software]
    comment = Software disponible per a tots
    path = /var/software
    read only = Yes
    guest ok = Yes
    browseable = Yes

# ---- Recursos del domini (P4.6 Ex4) ----
[cHisenda]
    comment = Comptabilitat i Hisenda - Direccio
    path = /var/NovaCode/cHisenda
    read only = No
    valid users = @gDireccio
    write list = @gDireccio
    browseable = Yes
    create mask = 0770
    directory mask = 0770

[cComptes]
    comment = Comptes - Oficines (lectura Direccio)
    path = /var/NovaCode/cComptes
    read only = Yes
    valid users = @gOficines @gDireccio
    write list = @gOficines
    browseable = Yes
    create mask = 0770
    directory mask = 0770

[cProjectes]
    comment = Projectes - Desenvolupament (lectura Direccio)
    path = /var/NovaCode/cProjectes
    read only = Yes
    valid users = @gDesenvolupament @gDireccio
    write list = @gDesenvolupament
    browseable = Yes
    create mask = 0770
    directory mask = 0770

[cProduccio]
    comment = Produccio - Desenvolupament
    path = /var/NovaCode/cProduccio
    read only = No
    valid users = @gDesenvolupament
    write list = @gDesenvolupament
    browseable = Yes
    create mask = 0770
    directory mask = 0770

# ---- Nomines amb mascara (P4.7 Ex4) ----
[nomines]
    comment = Nomines - Oficines (privat per propietari)
    path = /var/NovaCode/nomines
    read only = No
    valid users = @gOficines
    write list = @gOficines
    browseable = Yes
    create mask = 0600
    directory mask = 0700
    force create mode = 0600
    force directory mode = 0700

# ---- Homes (P4.7 Ex6) ----
[homes]
    comment = Directoris dels usuaris
    browseable = No
    read only = No
    valid users = %U %D%w%U
    path = /home/NovaCode/%S
    create mask = 0600
    directory mask = 0700
SMBCONF

echo "✓ smb.conf configurat"

# Verificar configuració
testparm -s 2>&1 | tail -5 || true

echo "=================================================="
echo " FASE 9 - CONFIGURAR NSSWITCH (winbind)"
echo "=================================================="

# Afegir winbind a passwd i group
sed -i 's/^passwd:.*/passwd:         files winbind/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          files winbind/' /etc/nsswitch.conf

echo "✓ nsswitch.conf configurat:"
grep -E "^passwd|^group" /etc/nsswitch.conf

echo "=================================================="
echo " FASE 10 - REINICIAR SERVEIS"
echo "=================================================="

systemctl restart samba-ad-dc
systemctl enable winbind
systemctl restart winbind
sleep 3

echo "=================================================="
echo " VERIFICACIÓ FINAL"
echo "=================================================="

echo "--- Estat samba-ad-dc ---"
systemctl status samba-ad-dc --no-pager | head -5

echo "--- Usuaris del domini ---"
samba-tool user list

echo "--- Grups del domini ---"
samba-tool group list

echo "--- OUs del domini ---"
samba-tool ou list

echo "--- Recursos compartits ---"
smbclient -L localhost -U Administrator --password="${ADMINPASS}" -N 2>/dev/null || \
  smbclient -L ${IP} -N 2>/dev/null || echo "Comprova manualment: smbclient -L ${IP} -N"

echo ""
echo "=========================================================="
echo " SCRIPT FINALITZAT CORRECTAMENT"
echo "=========================================================="
echo ""
echo " Domini:    ${DOMAIN}"
echo " Servidor:  SRVLIN40 (${IP})"
echo " Admin:     Administrator / ${ADMINPASS}"
echo " Usuaris:   uOficinista / uDesenvolupadora / uDirectora"
echo " Password:  ${USERPASS}"
echo ""
echo " Des de Windows 10:"
echo "   DNS → ${IP}"
echo "   Unir a domini → NovaCode.local (admin: isard / ${ADMINPASS})"
echo "   Explorador → \\\\${IP}"
echo ""
echo " Proves accés (P6.5 Ex4):"
echo "   Escriptura:    uDirectora → \\\\${IP}\\cHisenda"
echo "   Lectura:       uDirectora → \\\\${IP}\\cProjectes (read only)"
echo "   Accés negat:   uDesenvolupadora → \\\\${IP}\\cHisenda"
echo "   Muntatge perm: net use Z: \\\\${IP}\\cHisenda /persistent:yes"
echo ""
echo " Verificar equip Windows unit:"
echo "   samba-tool computer list"
echo "=========================================================="
