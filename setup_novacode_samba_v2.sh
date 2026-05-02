#!/bin/bash
# ============================================================
#  setup_novacode_samba.sh
#  Crea OUs, grups, usuaris i recursos compartits Samba AD
#  Domini: NovaCode.local — Exercici 4 (P4.6/P4.7/P6.3)
#  Ús: sudo bash setup_novacode_samba.sh
# ============================================================

set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'; BOLD='\033[1m'
ok()  { echo -e "${GREEN}[OK]${RESET} $*"; }
info(){ echo -e "${CYAN}[--]${RESET} $*"; }
sep() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }

[[ $EUID -ne 0 ]] && { echo "Executa com a root: sudo bash $0"; exit 1; }

# ── Variables globals ──────────────────────────────────────
DOM="NovaCode"
DOMF="NovaCode.local"
DC="DC=NovaCode,DC=local"
PASS="@ITB2025"
BASEDIR="/var/NovaCode"

# ══════════════════════════════════════════════════════════
sep "1. Iniciant Samba AD"
# ══════════════════════════════════════════════════════════
systemctl unmask samba-ad-dc 2>/dev/null || true
systemctl enable samba-ad-dc 2>/dev/null || true
systemctl start  samba-ad-dc 2>/dev/null || true
sleep 2; ok "samba-ad-dc actiu"

# ══════════════════════════════════════════════════════════
sep "2. Unitats Organitzatives"
# ══════════════════════════════════════════════════════════
for OU in Oficines Desenvolupament Direccio; do
    samba-tool ou create "OU=${OU},${DC}" 2>/dev/null \
        && ok "OU $OU creada" || info "OU $OU ja existia"
done

# ══════════════════════════════════════════════════════════
sep "3. Grups"
# ══════════════════════════════════════════════════════════
samba-tool group add gOficines        --groupou="OU=Oficines"        2>/dev/null && ok "gOficines"        || info "ja existia"
samba-tool group add gDesenvolupament --groupou="OU=Desenvolupament" 2>/dev/null && ok "gDesenvolupament" || info "ja existia"
samba-tool group add gDireccio        --groupou="OU=Direccio"        2>/dev/null && ok "gDireccio"        || info "ja existia"

# ══════════════════════════════════════════════════════════
sep "4. Usuaris"
# ══════════════════════════════════════════════════════════
# uOficinista — OU Oficines — gOficines
samba-tool user create uOficinista "$PASS" \
    --userou="OU=Oficines" --given-name="Usuari" --surname="Administratiu" \
    --must-change-at-next-login=false 2>/dev/null && ok "uOficinista creat" || info "ja existia"
samba-tool group addmembers gOficines uOficinista 2>/dev/null || true

# uDesenvolupadora — OU Desenvolupament — gDesenvolupament
samba-tool user create uDesenvolupadora "$PASS" \
    --userou="OU=Desenvolupament" --given-name="Usuaria" --surname="Programadora" \
    --must-change-at-next-login=false 2>/dev/null && ok "uDesenvolupadora creada" || info "ja existia"
samba-tool group addmembers gDesenvolupament uDesenvolupadora 2>/dev/null || true

# uDirectora — OU Direccio — gDireccio
samba-tool user create uDirectora "$PASS" \
    --userou="OU=Direccio" --given-name="Usuaria" --surname="Gestora" \
    --must-change-at-next-login=false 2>/dev/null && ok "uDirectora creada" || info "ja existia"
samba-tool group addmembers gDireccio uDirectora 2>/dev/null || true

info "Usuaris al domini:"; samba-tool user list

# ══════════════════════════════════════════════════════════
sep "5. Directoris i permisos de sistema"
# ══════════════════════════════════════════════════════════
# Estructura:
#   cHisenda   → gDireccio        (R+W)
#   cComptes   → gOficines R+W    | gDireccio R
#   cProjectes → gDesenvolupament R+W | gDireccio R
#   cProduccio → gDesenvolupament (R+W)
#   software   → tots (anònim, R/O)

mkdir -p \
    "$BASEDIR/cHisenda" \
    "$BASEDIR/cComptes" \
    "$BASEDIR/cProjectes" \
    "$BASEDIR/cProduccio" \
    "$BASEDIR/nomines" \
    /var/software \
    /home/NovaCode

# Permisos UNIX base (Samba afina via valid users/write list)
chmod 770 "$BASEDIR/cHisenda"
chmod 770 "$BASEDIR/cComptes"
chmod 770 "$BASEDIR/cProjectes"
chmod 770 "$BASEDIR/cProduccio"
chmod 770 "$BASEDIR/nomines"
chmod 755 /var/software
chown root:root "$BASEDIR" /var/software

ok "Directoris creats i permisos assignats:"
ls -la "$BASEDIR"

# ══════════════════════════════════════════════════════════
sep "6. /etc/samba/smb.conf"
# ══════════════════════════════════════════════════════════
SMB=/etc/samba/smb.conf
cp "$SMB" "${SMB}.bak_$(date +%Y%m%d_%H%M%S)"

# Conserva la secció [global] original del domini
GLOBAL=$(awk '/^\[global\]/,/^\[/' "$SMB" | grep -v '^\[' | sed '/^[[:space:]]*$/d' | head -n -1)

cat > "$SMB" << CONF
# /etc/samba/smb.conf — ${DOMF}

[global]
${GLOBAL}
    winbind use default domain = yes
    winbind enum users         = yes
    winbind enum groups        = yes
    template homedir           = /home/NovaCode/%U
    template shell             = /bin/bash

[sysvol]
    path      = /var/lib/samba/sysvol
    read only = No

[netlogon]
    path      = /var/lib/samba/sysvol/${DOMF}/scripts
    read only = No

# ── Anònim (tothom pot llegir) ──────────────────────────
[software]
    comment    = Software - acces anònim lectura
    path       = /var/software
    read only  = Yes
    guest ok   = Yes
    browseable = Yes

# ── cHisenda: gDireccio R+W ─────────────────────────────
# ESCRIPTURA: uDirectora ✓  |  ACCÉS DENEGAT: uDesenvolupadora ✗
[cHisenda]
    comment     = Hisenda - Direccio
    path        = ${BASEDIR}/cHisenda
    browseable  = Yes
    read only   = No
    valid users = @gDireccio
    write list  = @gDireccio

# ── cComptes: gOficines R+W | gDireccio R ───────────────
[cComptes]
    comment     = Comptes - Oficines escriptura, Direccio lectura
    path        = ${BASEDIR}/cComptes
    browseable  = Yes
    read only   = Yes
    valid users = @gOficines @gDireccio
    write list  = @gOficines

# ── cProjectes: gDesenvolupament R+W | gDireccio R ──────
# LECTURA SOLA: uOficinista no té accés (not in valid users)
# Per prova lectura usa uDirectora → cProjectes (R/O)
[cProjectes]
    comment     = Projectes - Desenvolupament escriptura, Direccio lectura
    path        = ${BASEDIR}/cProjectes
    browseable  = Yes
    read only   = Yes
    valid users = @gDesenvolupament @gDireccio
    write list  = @gDesenvolupament

# ── cProduccio: gDesenvolupament R+W ────────────────────
[cProduccio]
    comment     = Produccio - Desenvolupament
    path        = ${BASEDIR}/cProduccio
    browseable  = Yes
    read only   = No
    valid users = @gDesenvolupament
    write list  = @gDesenvolupament

# ── nomines: màscares restrictives ──────────────────────
[nomines]
    comment        = Nomines - fitxers privats per creador
    path           = ${BASEDIR}/nomines
    browseable     = Yes
    read only      = No
    valid users    = @gOficines
    write list     = @gOficines
    create mask    = 0600
    directory mask = 0700

# ── Homes ────────────────────────────────────────────────
[homes]
    comment     = Directoris personals
    browseable  = No
    read only   = No
    valid users = %U %D%w%U
    path        = /home/NovaCode/%S
CONF

info "Validant smb.conf..."; testparm -s "$SMB" 2>&1 | head -30
ok "smb.conf configurat"

# ══════════════════════════════════════════════════════════
sep "7. nsswitch.conf — winbind"
# ══════════════════════════════════════════════════════════
cp /etc/nsswitch.conf /etc/nsswitch.conf.bak 2>/dev/null || true
grep -qE "^passwd.*winbind" /etc/nsswitch.conf || sed -i '/^passwd:/ s/$/ winbind/' /etc/nsswitch.conf
grep -qE "^group.*winbind"  /etc/nsswitch.conf || sed -i '/^group:/ s/$/ winbind/'  /etc/nsswitch.conf
ok "nsswitch.conf:"; grep -E "^(passwd|group)" /etc/nsswitch.conf

# ══════════════════════════════════════════════════════════
sep "8. Reinici serveis"
# ══════════════════════════════════════════════════════════
systemctl restart samba-ad-dc 2>/dev/null || true
systemctl restart winbind     2>/dev/null || true
sleep 2; ok "Serveis reiniciats"

# ══════════════════════════════════════════════════════════
sep "9. Verificació"
# ══════════════════════════════════════════════════════════
info "Recursos compartits:"; smbclient -L localhost -N 2>/dev/null | head -20 || true
info "Usuaris del domini (wbinfo):"; wbinfo -u 2>/dev/null || true

IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  COMPLETAT — Exercici 4: proves d'accés        ${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${YELLOW}Al client Windows 10 (IP servidor: $IP):${RESET}"
echo ""
echo "  Recursos visibles:"
echo "    Explorador → \\\\$IP"
echo ""
echo "  ✏  Escriptura  → uDirectora    → \\\\$IP\\cHisenda   (R+W)"
echo "  📖 Lectura     → uDirectora    → \\\\$IP\\cProjectes (R/O)"
echo "  🚫 Accés negat → uDesenvolupadora → \\\\$IP\\cHisenda (denegat)"
echo ""
echo "  Muntatge permanent (CMD Admin):"
echo "    net use Z: \\\\$IP\\cHisenda /persistent:yes"
echo ""
