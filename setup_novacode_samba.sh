#!/bin/bash
# =============================================================================
#  NovaCode Samba AD - Setup complet
#  Crea: OUs, Grups, Usuaris, Directoris i Recursos compartits (smb.conf)
#  Exercici: P3.6 + P4.6 + P4.7 (Comprovar els recursos - Exercici 2.4)
# =============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURACIÓ — ajusta els valors al teu entorn si cal
# ──────────────────────────────────────────────────────────────────────────────
DOMAIN="novacode.local"          # Nom FQDN del domini
DC="DC=novacode,DC=local"        # Base DN
REALM="NOVACODE.LOCAL"           # Realm Kerberos (majúscules)
PASSWORD="@ITB2025"              # Password per defecte de tots els usuaris
NOVACODE_DIR="/var/NovaCode"     # Directori arrel dels recursos
SOFTWARE_DIR="/var/software"     # Directori del recurs anònim "software"
SMB_CONF="/etc/samba/smb.conf"   # Fitxer de configuració de Samba

# Colors per a la sortida
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR] ${NC}  $*"; }
sep()   { echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# Comprova que s'executa com a root
if [[ $EUID -ne 0 ]]; then
    error "Executa el script com a root: sudo $0"
    exit 1
fi

sep
echo -e "${GREEN}  NovaCode Samba AD — Setup complet${NC}"
echo -e "  Domini: ${YELLOW}${DOMAIN}${NC}   |   DC: ${YELLOW}${DC}${NC}"
sep


# =============================================================================
# PART 1 — UNITATS ORGANITZATIVES (OU)
# =============================================================================
sep; info "PART 1: Creant Unitats Organitzatives..."

create_ou() {
    local ou_name="$1"
    local description="$2"
    if samba-tool ou list 2>/dev/null | grep -qi "OU=${ou_name}"; then
        warn "OU '${ou_name}' ja existeix — s'omet."
    else
        samba-tool ou create "OU=${ou_name},${DC}" --description="${description}" \
            && info "OU creada: ${ou_name}" \
            || error "Error creant OU: ${ou_name}"
    fi
}

create_ou "Direccio"      "Unitat organitzativa de Direccio"
create_ou "Oficines"      "Unitat organitzativa d'Oficines i Administracio"
create_ou "Desenvolupament" "Unitat organitzativa de Desenvolupament"
create_ou "Produccio"     "Unitat organitzativa de Produccio"

info "OUs existents al domini:"
samba-tool ou list


# =============================================================================
# PART 2 — GRUPS
# =============================================================================
sep; info "PART 2: Creant Grups..."

create_group() {
    local group="$1"
    local ou="$2"
    local description="$3"
    if samba-tool group list 2>/dev/null | grep -qi "^${group}$"; then
        warn "Grup '${group}' ja existeix — s'omet."
    else
        samba-tool group add "${group}" \
            --groupou="OU=${ou}" \
            --description="${description}" \
            && info "Grup creat: ${group} (OU=${ou})" \
            || error "Error creant grup: ${group}"
    fi
}

create_group "gDireccio"        "Direccio"        "Grup de Direccio"
create_group "gOficines"        "Oficines"        "Grup d'Oficines i Administracio"
create_group "gDesenvolupament" "Desenvolupament" "Grup de Desenvolupament"
create_group "gProduccio"       "Produccio"       "Grup de Produccio"

info "Grups existents al domini:"
samba-tool group list


# =============================================================================
# PART 3 — USUARIS
# =============================================================================
sep; info "PART 3: Creant Usuaris..."

create_user() {
    local username="$1"
    local ou="$2"
    local surname="$3"
    local given_name="$4"
    if samba-tool user list 2>/dev/null | grep -qi "^${username}$"; then
        warn "Usuari '${username}' ja existeix — s'omet."
    else
        samba-tool user create "${username}" "${PASSWORD}" \
            --userou="OU=${ou}" \
            --surname="${surname}" \
            --given-name="${given_name}" \
            && info "Usuari creat: ${username} (OU=${ou})" \
            || error "Error creant usuari: ${username}"
    fi
}

#  Login           OU                Cognom           Nom
create_user "uDirectora"        "Direccio"        "Directora"       "Usuaria"
create_user "uDirectora2"       "Direccio"        "Directora2"      "Usuaria"      # Per a proves d'accés
create_user "uOficinista"       "Oficines"        "Oficinista"      "Usuari"
create_user "uOficinista2"      "Oficines"        "Oficinista2"     "Usuari"       # Per a proves d'ACL
create_user "uDesenvolupadora"  "Desenvolupament" "Desenvolup."     "Usuaria"
create_user "uDesenvolupadora2" "Desenvolupament" "Desenvolup.2"    "Usuaria"      # Per a proves

info "Usuaris existents al domini:"
samba-tool user list


# =============================================================================
# PART 4 — AFEGIR USUARIS ALS GRUPS
# =============================================================================
sep; info "PART 4: Afegint usuaris als grups..."

add_to_group() {
    local group="$1"; shift
    local members=("$@")
    for member in "${members[@]}"; do
        samba-tool group addmembers "${group}" "${member}" \
            && info "  ${member} → ${group}" \
            || warn "  No s'ha pogut afegir ${member} a ${group} (ja membre?)"
    done
}

add_to_group "gDireccio"        "uDirectora" "uDirectora2"
add_to_group "gOficines"        "uOficinista" "uOficinista2"
add_to_group "gDesenvolupament" "uDesenvolupadora" "uDesenvolupadora2"
add_to_group "gProduccio"       "uDesenvolupadora" "uDesenvolupadora2"

info "Membres de gDireccio:";        samba-tool group listmembers "gDireccio"
info "Membres de gOficines:";        samba-tool group listmembers "gOficines"
info "Membres de gDesenvolupament:"; samba-tool group listmembers "gDesenvolupament"
info "Membres de gProduccio:";       samba-tool group listmembers "gProduccio"


# =============================================================================
# PART 5 — DIRECTORIS I PERMISOS (Linux filesystem)
# =============================================================================
sep; info "PART 5: Creant directoris i assignant permisos..."

# Assegura que winbind pot resoldre els usuaris del domini
# Necessari per a chown amb noms de domini
WINBIND_SEP=$(net conf showshare global 2>/dev/null | grep "winbind separator" | awk '{print $3}')
# Normalment el separador és '\' o '+'; a Samba AD el format és DOMINI\usuari
DOM_PREFIX="${REALM}"

# ── /var/software (anònim, lectura) ───────────────────────────────────────────
mkdir -p "${SOFTWARE_DIR}"
chmod 755 "${SOFTWARE_DIR}"
chown root:root "${SOFTWARE_DIR}"
info "Directori creat: ${SOFTWARE_DIR} (anonymous, read-only)"

# Descarrega un fitxer de mostra si no existeix cap
if [ -z "$(ls -A ${SOFTWARE_DIR} 2>/dev/null)" ]; then
    info "Descarregant 7-zip com a software de mostra..."
    wget -q -P "${SOFTWARE_DIR}" https://www.7-zip.org/a/7z2403-linux-x64.tar.xz \
        && info "7-zip descarregat a ${SOFTWARE_DIR}" \
        || warn "No s'ha pogut descarregar el fitxer (comprova la connexió)."
fi

# ── /var/NovaCode (arrel de tots els recursos d'empresa) ──────────────────────
mkdir -p "${NOVACODE_DIR}"
chmod 755 "${NOVACODE_DIR}"
chown root:root "${NOVACODE_DIR}"

# Funció per crear un directori de recurs amb permisos de grup
#   $1 = nom directori (p.ex. cHisenda)
#   $2 = grup propietari (p.ex. gDireccio)
#   $3 = permisos octal   (p.ex. 2770)
make_resource_dir() {
    local dir="${NOVACODE_DIR}/$1"
    local group="$2"
    local perms="$3"
    mkdir -p "${dir}"
    # Intentem chown amb el grup del domini (winbind ha d'estar actiu)
    if getent group "${REALM}\\${group}" &>/dev/null; then
        chown "root:${REALM}\\${group}" "${dir}"
    elif getent group "${group}" &>/dev/null; then
        chown "root:${group}" "${dir}"
    else
        warn "No s'ha pogut resoldre el grup '${group}' — el directori queda amb grup root."
        warn "Torna a executar el script un cop winbind estigui en marxa."
    fi
    chmod "${perms}" "${dir}"
    info "  ${dir}  mode=${perms}  grup=${group}"
}

info "Recursos de l'empresa NovaCode:"
#            Directori       Grup propietari    Permisos
#            ---------       ---------------    --------
# setgid (2) perquè els fitxers nous heretin el grup del directori
make_resource_dir "cProduccio"  "gDesenvolupament"  "2770"
make_resource_dir "cComptes"    "gOficines"         "2770"
make_resource_dir "cHisenda"    "gDireccio"         "2770"
make_resource_dir "cProjectes"  "gProduccio"        "2770"

# Directoris home dels usuaris del domini
HOME_BASE="/home/NovaCode"
mkdir -p "${HOME_BASE}"
for user in uDirectora uOficinista uDesenvolupadora; do
    udir="${HOME_BASE}/${user}"
    mkdir -p "${udir}"
    # chown amb format DOMINI\usuari si winbind ho resol
    if getent passwd "${REALM}\\${user}" &>/dev/null; then
        chown "${REALM}\\${user}:${REALM}\\${user}" "${udir}"
    else
        warn "No s'ha pogut resoldre ${user} via winbind — directori ${udir} amb propietari root."
    fi
    chmod 750 "${udir}"
    info "  Home creada: ${udir}"
done

info "Llistat final de directoris NovaCode:"
ls -la "${NOVACODE_DIR}/"


# =============================================================================
# PART 6 — CONFIGURACIÓ SMB.CONF
# =============================================================================
sep; info "PART 6: Configurant /etc/samba/smb.conf..."

# Fa una còpia de seguretat del smb.conf actual
if [ -f "${SMB_CONF}" ]; then
    cp "${SMB_CONF}" "${SMB_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
    info "Còpia de seguretat del smb.conf original creada."
fi

# Elimina recursos anteriors que pugui haver definit manualment
# (deixa la secció [global], [sysvol] i [netlogon] intactes)
# Estratègia: extreu el bloc global+sysvol+netlogon i afegeix les noves seccions
GLOBAL_BLOCK=$(sed '/^\[sysvol\]/,$d' "${SMB_CONF}")

cat > "${SMB_CONF}" << SMBEOF
${GLOBAL_BLOCK}

[sysvol]
	path = /var/lib/samba/sysvol
	read only = No

[netlogon]
	path = /var/lib/samba/sysvol/${DOMAIN}/scripts
	read only = No

# ─────────────────────────────────────────────────────────────────────────────
# Recurs anònim — software (lectura per a tothom, sense autenticació)
# ─────────────────────────────────────────────────────────────────────────────
[software]
	comment = Repositori de software (accés anònim)
	path = ${SOFTWARE_DIR}
	browseable = Yes
	read only = Yes
	guest ok = Yes

# ─────────────────────────────────────────────────────────────────────────────
# Recursos d'empresa NovaCode
#
# Permisos resum:
#   cProduccio  → gDesenvolupament (rw)
#   cComptes    → gOficines (rw), gDireccio (r)
#   cHisenda    → gDireccio (rw)
#   cProjectes  → gProduccio (rw), gDireccio (r)
# ─────────────────────────────────────────────────────────────────────────────

[produccio]
	comment = Recurs de Produccio - NovaCode
	path = ${NOVACODE_DIR}/cProduccio
	browseable = Yes
	read only = Yes
	valid users = @gDesenvolupament @gDireccio
	write list = @gDesenvolupament

[comptabilitat]
	comment = Recurs de Comptabilitat - NovaCode
	path = ${NOVACODE_DIR}/cComptes
	browseable = Yes
	read only = Yes
	valid users = @gOficines @gDireccio uDesenvolupadora
	write list = @gOficines

[tresoreria]
	comment = Recurs de Hisenda/Tresoreria - NovaCode
	path = ${NOVACODE_DIR}/cHisenda
	browseable = Yes
	read only = No
	valid users = @gDireccio
	write list = @gDireccio

[projectes]
	comment = Recurs de Projectes - NovaCode
	path = ${NOVACODE_DIR}/cProjectes
	browseable = Yes
	read only = Yes
	valid users = @gProduccio @gDireccio
	write list = @gProduccio
	; Exemple de denegació explícita (exercici 2.2):
	; invalid users = uDirectora

# ─────────────────────────────────────────────────────────────────────────────
# Homes dels usuaris del domini
# ─────────────────────────────────────────────────────────────────────────────
[homes]
	comment = Directoris home dels usuaris del domini
	path = /home/NovaCode/%S
	browseable = No
	read only = No
	valid users = %U %D%w%U
	create mask = 0700
	directory mask = 0700
SMBEOF

info "smb.conf escrit correctament."

# Verifica la sintaxi del fitxer
sep; info "Verificant configuració amb testparm..."
testparm -s 2>&1 | head -60


# =============================================================================
# PART 7 — nsswitch.conf (winbind)
# =============================================================================
sep; info "PART 7: Comprovant /etc/nsswitch.conf per a winbind..."

NSSWITCH="/etc/nsswitch.conf"
for line_type in "passwd" "group"; do
    if grep -qP "^${line_type}:.*winbind" "${NSSWITCH}"; then
        info "  ${line_type}: winbind ja present."
    else
        sed -i "s/^${line_type}:\(.*\)/${line_type}:\1 winbind/" "${NSSWITCH}"
        info "  ${line_type}: winbind afegit."
    fi
done

grep -E "^(passwd|group):" "${NSSWITCH}"


# =============================================================================
# PART 8 — Reinici de serveis
# =============================================================================
sep; info "PART 8: Reiniciant serveis Samba..."

systemctl restart samba-ad-dc 2>/dev/null \
    || systemctl restart smbd nmbd winbind 2>/dev/null

sleep 2

for svc in samba-ad-dc smbd winbind; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        info "  ${svc}: ACTIU ✔"
    fi
done


# =============================================================================
# RESUM FINAL
# =============================================================================
sep
echo -e "${GREEN}  RESUM DE LA CONFIGURACIÓ NOVACODE${NC}"
sep
echo ""
echo -e "  ${YELLOW}Domini:${NC} ${DOMAIN}  |  ${YELLOW}Realm:${NC} ${REALM}"
echo ""
echo -e "  ${YELLOW}OUs creades:${NC}"
samba-tool ou list 2>/dev/null | sed 's/^/    /'
echo ""
echo -e "  ${YELLOW}Grups creats:${NC}"
for g in gDireccio gOficines gDesenvolupament gProduccio; do
    echo -n "    ${g}: "
    samba-tool group listmembers "${g}" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
    echo ""
done
echo ""
echo -e "  ${YELLOW}Directoris compartits:${NC}"
ls -la "${NOVACODE_DIR}/" 2>/dev/null | sed 's/^/    /'
echo ""
echo -e "  ${YELLOW}Recursos Samba visibles (smbclient):${NC}"
echo -e "    smbclient -L localhost -U uDirectora%${PASSWORD}"
echo ""
echo -e "  ${YELLOW}Credencials d'usuari (tots usen la mateixa password per defecte):${NC}"
echo -e "    Password: ${RED}${PASSWORD}${NC}"
echo ""
sep
echo -e "${GREEN}  Script finalitzat correctament!${NC}"
echo -e "  Connecta des de Windows amb: ${YELLOW}\\\\\\\\<IP_SERVIDOR>${NC}"
sep

# ─────────────────────────────────────────────────────────────────────────────
# ANNEX — Comandes per a les proves de l'Exercici 4 (des del client Windows)
# ─────────────────────────────────────────────────────────────────────────────
cat << 'ANNEX'

══════════════════════════════════════════════════════════════════════════════
 ANNEX — Comandes útils per a l'Exercici 4 (Comprovar els recursos)
══════════════════════════════════════════════════════════════════════════════

1. LLISTAR recursos compartits des del servidor:
   smbclient -L localhost -U uDirectora%@ITB2025

2. PROVA D'ESCRIPTURA (uDirectora → tresoreria, té permisos rw):
   Des del client Windows 10 navegar a: \\IP_SERVIDOR\tresoreria
   Crear un fitxer → ha de funcionar correctament.

   Des de terminal Linux del client:
   smbclient //IP_SERVIDOR/tresoreria -U "NOVACODE.LOCAL\uDirectora%@ITB2025" \
       -c "put /etc/hostname fitxer_prova.txt; ls"

3. PROVA DE LECTURA (uDesenvolupadora → comptabilitat, només lectura):
   smbclient //IP_SERVIDOR/comptabilitat \
       -U "NOVACODE.LOCAL\uDesenvolupadora%@ITB2025" \
       -c "ls; put /etc/hostname test.txt"
   → ls ha de funcionar, put ha de donar error "NT_STATUS_ACCESS_DENIED"

4. PROVA D'ACCÉS NO PERMÈS (uOficinista → tresoreria, sense accés):
   smbclient //IP_SERVIDOR/tresoreria \
       -U "NOVACODE.LOCAL\uOficinista%@ITB2025" \
       -c "ls"
   → Ha de donar: NT_STATUS_ACCESS_DENIED

5. MUNTAR de forma permanent des de Windows 10 (com a unitat de xarxa Z:):
   → Explorador de fitxers → Afegir una ubicació de xarxa
   → Clic dret "Aquest equip" → "Connecta a unitat de xarxa..."
   → Unitat: Z:  |  Carpeta: \\IP_SERVIDOR\tresoreria
   → Marcar "Reconnectar en iniciar sessió"  (= permanent)
   → Introduir credencials: NOVACODE\uDirectora / @ITB2025

   O des de cmd.exe (permanent):
   net use Z: \\IP_SERVIDOR\tresoreria @ITB2025 /user:NOVACODE\uDirectora /persistent:yes

6. VERIFICAR fitxers creats des del SERVIDOR:
   ls -la /var/NovaCode/cHisenda/
   getfacl /var/NovaCode/cHisenda/

ANNEX
