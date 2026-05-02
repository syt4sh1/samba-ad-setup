#!/bin/bash
set -e

# ========= CONFIG =========
DOMAIN="NOVACODE.LOCAL"
DC_BASE="DC=novacode,DC=local"
PASS="@ITB2025"
BASE="/var/NovaCode"
SOFT="/var/software"

echo "=== CHECK SAMBA AD ==="
if ! testparm -s | grep -q "server role = active directory domain controller"; then
    echo "❌ ERROR: Esto NO es un AD DC"
    echo "👉 Reprovisiona primero:"
    echo "samba-tool domain provision"
    exit 1
fi

echo "=== SERVICIO ==="
systemctl restart samba-ad-dc

# ========= OU =========
echo "=== OUs ==="
for ou in Direccio Oficines Desenvolupament; do
    samba-tool ou create "OU=$ou,$DC_BASE" 2>/dev/null || true
done

# ========= GRUPS =========
echo "=== GRUPS ==="
samba-tool group add gDireccio --groupou="OU=Direccio" 2>/dev/null || true
samba-tool group add gOficines --groupou="OU=Oficines" 2>/dev/null || true
samba-tool group add gDesenvolupament --groupou="OU=Desenvolupament" 2>/dev/null || true

# ========= USERS =========
echo "=== USERS ==="
samba-tool user create uDirectora $PASS --userou="OU=Direccio" 2>/dev/null || true
samba-tool user create uOficinista $PASS --userou="OU=Oficines" 2>/dev/null || true
samba-tool user create uDesenvolupadora $PASS --userou="OU=Desenvolupament" 2>/dev/null || true

samba-tool group addmembers gDireccio uDirectora
samba-tool group addmembers gOficines uOficinista
samba-tool group addmembers gDesenvolupament uDesenvolupadora

# ========= DIRECTORIS =========
echo "=== DIRECTORIS ==="
mkdir -p $BASE/{cHisenda,cComptes,cProjectes,cProduccio,nomines}
mkdir -p $SOFT

chmod -R 770 $BASE
chmod 755 $SOFT

# ========= SMB.CONF =========
echo "=== SMB CONFIG ==="

cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

cat >> /etc/samba/smb.conf <<EOF

# ===== SHARES NOVACODE =====

[software]
path = $SOFT
read only = yes
guest ok = yes

[cHisenda]
path = $BASE/cHisenda
read only = no
valid users = @gDireccio

[cComptes]
path = $BASE/cComptes
read only = yes
valid users = @gOficines @gDireccio
write list = @gOficines

[cProjectes]
path = $BASE/cProjectes
read only = yes
valid users = @gDesenvolupament @gDireccio
write list = @gDesenvolupament

[cProduccio]
path = $BASE/cProduccio
read only = no
valid users = @gDesenvolupament

[nomines]
path = $BASE/nomines
read only = no
valid users = @gOficines
create mask = 0600
directory mask = 0700

[homes]
path = /home/%U
read only = no
browseable = no

EOF

# ========= RESTART =========
echo "=== RESTART ==="
systemctl restart samba-ad-dc

# ========= CHECK =========
echo "=== CHECK FINAL ==="
testparm -s | grep "server role"

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "🔥 LISTO 🔥"
echo "Accede desde Windows:"
echo "\\\\$IP"
echo ""
echo "✔ Escritura: uDirectora → cHisenda"
echo "✔ Lectura: uDirectora → cProjectes"
echo "❌ Denegado: uDesenvolupadora → cHisenda"
