#!/bin/bash
# ============================================================
# SCRIPT: OUs, Grups, Usuaris i Permisos - NovaCode
# Prerequisit: Samba AD DC ja instal·lat i funcionant
# Execució: sudo bash novacode_users_ous.sh
# ============================================================

USERPASS="@ITB2025"

echo "=================================================="
echo " 1 - CREAR OUs"
echo "=================================================="

samba-tool ou create "OU=Oficines,DC=NovaCode,DC=local" \
  --description="Personal d oficines NovaCode"

samba-tool ou create "OU=Desenvolupament,DC=NovaCode,DC=local" \
  --description="Equip de desenvolupadors NovaCode"

samba-tool ou create "OU=Direccio,DC=NovaCode,DC=local" \
  --description="Direccio de NovaCode"

echo "OUs creades:"
samba-tool ou list

echo "=================================================="
echo " 2 - CREAR GRUPS"
echo "=================================================="

samba-tool group add "gOficines" \
  --groupou="OU=Oficines" \
  --description="Grup personal oficines"

samba-tool group add "gDesenvolupament" \
  --groupou="OU=Desenvolupament" \
  --description="Grup desenvolupadors"

samba-tool group add "gDireccio" \
  --groupou="OU=Direccio" \
  --description="Grup direccio"

echo "Grups creats:"
samba-tool group list

echo "=================================================="
echo " 3 - CREAR USUARIS"
echo "=================================================="

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

samba-tool user create "uDirectora2" "${USERPASS}" \
  --userou="OU=Direccio" \
  --given-name="Usuaria2" --surname="Gestora2" \
  --must-change-at-next-login=false

echo "Usuaris creats:"
samba-tool user list

echo "=================================================="
echo " 4 - AFEGIR USUARIS ALS GRUPS"
echo "=================================================="

samba-tool group addmembers "gOficines" uOficinista
samba-tool group addmembers "gDesenvolupament" uDesenvolupadora
samba-tool group addmembers "gDireccio" uDirectora
samba-tool group addmembers "gDireccio" uDirectora2

echo "Membres gOficines:"
samba-tool group listmembers gOficines
echo "Membres gDesenvolupament:"
samba-tool group listmembers gDesenvolupament
echo "Membres gDireccio:"
samba-tool group listmembers gDireccio

echo "=================================================="
echo " 5 - CREAR DIRECTORIS I PERMISOS"
echo "=================================================="

mkdir -p /var/NovaCode/{cHisenda,cComptes,cProjectes,cProduccio,nomines}
mkdir -p /var/software
mkdir -p /home/NovaCode/{uDirectora,uDesenvolupadora,uOficinista}

# cHisenda → gDireccio rw
chown root:root /var/NovaCode/cHisenda
chmod 770 /var/NovaCode/cHisenda

# cComptes → gOficines rw, gDireccio r
chown root:root /var/NovaCode/cComptes
chmod 770 /var/NovaCode/cComptes

# cProjectes → gDesenvolupament rw, gDireccio r
chown root:root /var/NovaCode/cProjectes
chmod 770 /var/NovaCode/cProjectes

# cProduccio → gDesenvolupament rw
chown root:root /var/NovaCode/cProduccio
chmod 770 /var/NovaCode/cProduccio

# nomines → gOficines, privat per propietari
chown root:root /var/NovaCode/nomines
chmod 770 /var/NovaCode/nomines

# software → lectura per a tothom
chown root:root /var/software
chmod 755 /var/software

# homes → privat per cada usuari
chmod 750 /home/NovaCode/uDirectora
chmod 750 /home/NovaCode/uDesenvolupadora
chmod 750 /home/NovaCode/uOficinista

echo "Directoris i permisos:"
ls -la /var/NovaCode/
ls -la /home/NovaCode/

echo "=================================================="
echo " 6 - NSSWITCH (winbind)"
echo "=================================================="

if ! grep -q "winbind" /etc/nsswitch.conf; then
  sed -i 's/^passwd:\(.*\)/passwd:\1 winbind/' /etc/nsswitch.conf
  sed -i 's/^group:\(.*\)/group:\1 winbind/' /etc/nsswitch.conf
  echo "winbind afegit a nsswitch.conf"
else
  echo "winbind ja estava a nsswitch.conf"
fi

grep -E "^passwd|^group" /etc/nsswitch.conf

systemctl restart winbind 2>/dev/null || true

echo "=================================================="
echo " DONE"
echo "=================================================="
echo ""
echo "  uOficinista      -> gOficines      -> cComptes (rw)"
echo "  uDesenvolupadora -> gDesenvolupament -> cProjectes(rw) cProduccio(rw)"
echo "  uDirectora       -> gDireccio      -> cHisenda(rw) cComptes(r) cProjectes(r)"
echo "  uDirectora2      -> gDireccio      -> igual que uDirectora"
echo ""
echo "  Password de tots: ${USERPASS}"
echo "=================================================="
