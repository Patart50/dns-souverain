#!/usr/bin/env bash
# =====================================================================
#  install-dns-souverain.sh
#  Pi-hole (blocage pubs/trackers) + Unbound (résolveur récursif local)
#  Prévu pour : Debian 12/13, Ubuntu Server 22.04/24.04
#
#  Usage :  sudo bash install-dns-souverain.sh            (résolution directe)
#           sudo bash install-dns-souverain.sh --chiffre  (DNS chiffré via
#                                    Quad9 ou Mullvad, au choix)
#           Option directe : --chiffre=quad9  ou  --chiffre=mullvad
#  Relançable sans risque : il détecte ce qui est déjà en place.
#
#  Licence MIT — https://github.com/Patart50/dns-souverain
#  Configuration Unbound adaptée de la documentation officielle Pi-hole
#  (https://docs.pi-hole.net/guides/dns/unbound/, CC BY-SA 4.0).
#  Pi-hole est installé via son installeur officiel, non modifié.
# =====================================================================
set -euo pipefail

# ---------- Affichage ----------
VERT='\033[0;32m'; ROUGE='\033[0;31m'; JAUNE='\033[1;33m'; BLEU='\033[1;34m'; RAZ='\033[0m'
etape() { echo -e "\n${BLEU}==> $*${RAZ}"; }
ok()    { echo -e "${VERT}  [OK]${RAZ} $*"; }
warn()  { echo -e "${JAUNE}  [!]${RAZ} $*"; }
stop()  { echo -e "${ROUGE}  [ERREUR]${RAZ} $*"; exit 1; }
demander() { # demander "question" -> 0 si oui
  local r; read -r -p "  $1 [o/N] " r < /dev/tty || true
  [[ "$r" =~ ^[oOyY]$ ]]
}

export DEBIAN_FRONTEND=noninteractive
UNBOUND_CONF=/etc/unbound/unbound.conf.d/pi-hole.conf
PIHOLE_TOML=/etc/pihole/pihole.toml
UPSTREAM='127.0.0.1#5335'

# ---------- Options ----------
MODE=direct; FOURNISSEUR=""
for arg in "$@"; do
  case "$arg" in
    --chiffre)          MODE=chiffre ;;
    --chiffre=quad9)    MODE=chiffre; FOURNISSEUR=quad9 ;;
    --chiffre=mullvad)  MODE=chiffre; FOURNISSEUR=mullvad ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $arg (voir --help)"; exit 1 ;;
  esac
done

# =====================================================================
etape "1/8  Vérifications de base"
# =====================================================================
[[ $EUID -eq 0 ]] || stop "Lancez le script avec sudo :  sudo bash $0"

. /etc/os-release
if [[ "${ID:-}" != "debian" && "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *debian* ]]; then
  stop "Système non supporté (${PRETTY_NAME:-inconnu}). Utilisez Debian ou Ubuntu Server."
fi
ok "Système : ${PRETTY_NAME}"

if [[ "$MODE" == "chiffre" && -z "$FOURNISSEUR" ]]; then
  echo
  echo "  Mode chiffré : vos requêtes DNS partiront chiffrées (DNS over TLS)"
  echo "  vers UN résolveur public. Votre FAI ne les verra plus, mais ce"
  echo "  résolveur, lui, les verra toutes."
  echo "    1) Quad9   (fondation suisse à but non lucratif)"
  echo "    2) Mullvad (fournisseur VPN suédois, sans filtrage)"
  read -r -p "  Votre choix [1/2] : " CHOIX < /dev/tty || true
  case "$CHOIX" in
    2) FOURNISSEUR=mullvad ;;
    *) FOURNISSEUR=quad9 ;;
  esac
fi
if [[ "$MODE" == "chiffre" ]]; then
  ok "Mode : DNS chiffré via ${FOURNISSEUR}"
else
  ok "Mode : résolution directe (sans intermédiaire, non chiffrée)"
fi

ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || stop "Pas d'accès Internet. Vérifiez le câble réseau."
ok "Accès Internet"

# Interface et réseau local détectés automatiquement
IFACE=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
IP_CIDR=$(ip -o -4 addr show dev "$IFACE" | awk '{print $4; exit}')
IP_LOCALE=${IP_CIDR%/*}
RESEAU=$(ip -4 route show dev "$IFACE" scope link proto kernel | awk '{print $1; exit}')
[[ -n "$IP_LOCALE" && -n "$RESEAU" ]] || stop "Impossible de détecter l'adresse IP locale."

echo
echo "  Interface réseau : $IFACE"
echo "  IP de ce serveur : $IP_LOCALE"
echo "  Réseau local     : $RESEAU"
echo
demander "Ces informations sont-elles correctes ?" || stop "Corrigez la configuration réseau puis relancez."

# IP fixe ?
if ip -4 addr show dev "$IFACE" | grep -q "dynamic"; then
  warn "L'IP $IP_LOCALE est attribuée par la box (DHCP) : elle pourrait changer."
  warn "Le plus simple : dans l'interface de votre box, faites une RÉSERVATION DHCP"
  warn "(« bail statique », « IP fixe ») de $IP_LOCALE pour ce serveur."
  demander "C'est fait (ou je le ferai juste après). Continuer ?" || stop "Arrêt à votre demande."
fi

# =====================================================================
etape "2/8  Installation des outils de base"
# =====================================================================
apt-get update -qq
apt-get install -y -qq curl dnsutils ufw ca-certificates >/dev/null
ok "curl, dig, ufw installés"

# =====================================================================
etape "3/8  Test : votre box/FAI laisse-t-elle passer le DNS direct ?"
# =====================================================================
# Recommandé par la doc officielle Pi-hole : certains FAI ou box
# interceptent le DNS, ce qui casse Unbound de façon incompréhensible.
if [[ "$MODE" == "direct" ]]; then
REP_UDP=$(dig @198.41.0.4 . NS +norec +time=3 +tries=1 2>/dev/null || true)
if grep -q "flags:.* aa" <<<"$REP_UDP"; then
  ok "Les serveurs racines répondent en direct (UDP)"
else
  warn "Réponse anormale des serveurs racines : votre FAI ou votre box intercepte peut-être le DNS."
  demander "Continuer quand même (déconseillé) ?" || stop "Arrêt. Vérifiez le filtrage/contrôle parental de la box."
fi
if grep -q "flags:.* aa" <<<"$(dig @198.41.0.4 . NS +norec +tcp +time=3 +tries=1 2>/dev/null || true)"; then
  ok "Les serveurs racines répondent en direct (TCP)"
else
  warn "DNS en TCP bloqué : certaines résolutions (DNSSEC) pourront échouer."
  demander "Continuer quand même ?" || stop "Arrêt à votre demande."
fi
else
  ok "Mode chiffré : test des serveurs racines inutile"
fi

# =====================================================================
etape "4/8  Installation et configuration d'Unbound (port 5335)"
# =====================================================================
# IPv6 activé seulement si le serveur a une vraie route IPv6
if [[ -n "$(ip -6 route show default 2>/dev/null)" ]]; then IPV6=yes; else IPV6=no; fi

# La config est écrite AVANT l'installation pour qu'Unbound ne démarre
# jamais sur le port 53 (sinon conflit avec Pi-hole).
mkdir -p /etc/unbound/unbound.conf.d
cat > "$UNBOUND_CONF" <<EOF
# Généré par install-dns-souverain.sh — basé sur la doc officielle Pi-hole
server:
    verbosity: 0
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: ${IPV6}
    prefer-ip6: no

    # Racines Internet : fournies et mises à jour par le paquet dns-root-data
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    edns-buffer-size: 1232
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m

    # Ne jamais renvoyer d'adresses privées pour un domaine public
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
    private-address: 192.0.2.0/24
    private-address: 198.51.100.0/24
    private-address: 203.0.113.0/24
    private-address: 255.255.255.255/32
    private-address: 2001:db8::/32
EOF

if [[ "$MODE" == "chiffre" ]]; then
  if [[ "$FOURNISSEUR" == "mullvad" ]]; then
    ADDRS="    forward-addr: 194.242.2.2@853#dns.mullvad.net"
  else
    ADDRS="    forward-addr: 9.9.9.9@853#dns.quad9.net
    forward-addr: 149.112.112.112@853#dns.quad9.net"
  fi
  cat >> "$UNBOUND_CONF" <<EOF

    # Certificats pour vérifier l'identité du résolveur chiffré
    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

# Mode chiffré : tout part en DNS over TLS (port 853) vers ${FOURNISSEUR}
forward-zone:
    name: "."
    forward-tls-upstream: yes
${ADDRS}
EOF
fi

# Tampon réseau suffisant pour so-rcvbuf (évite un avertissement)
echo "net.core.rmem_max=1048576" > /etc/sysctl.d/99-unbound.conf
sysctl -q -w net.core.rmem_max=1048576 || true

apt-get install -y -qq unbound >/dev/null || true

# Debian : désactive unbound-resolvconf qui casserait la résolution du système
if systemctl list-unit-files 2>/dev/null | grep -q '^unbound-resolvconf'; then
  systemctl disable --now unbound-resolvconf.service >/dev/null 2>&1 || true
  [[ -f /etc/resolvconf.conf ]] && sed -Ei 's/^unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf
  rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf
  command -v resolvconf >/dev/null && resolvconf -u 2>/dev/null || true
  ok "Correctif Debian (unbound-resolvconf) appliqué"
fi

unbound-checkconf >/dev/null || stop "Configuration Unbound invalide."
systemctl enable unbound >/dev/null 2>&1
systemctl restart unbound
sleep 2

grep -q "status: NOERROR" <<<"$(dig pi-hole.net @127.0.0.1 -p 5335 +time=5 || true)" \
  || stop "Unbound ne répond pas. Diagnostic :  journalctl -u unbound -n 30 (en mode chiffré, vérifiez que le port 853 sortant n'est pas bloqué)"
if [[ "$MODE" == "chiffre" ]]; then
  ok "Unbound résout les noms via ${FOURNISSEUR}, en chiffré (port 853)"
else
  ok "Unbound résout les noms en interrogeant directement les racines"
fi

grep -q "status: SERVFAIL" <<<"$(dig fail01.dnssec.works @127.0.0.1 -p 5335 +time=5 || true)" \
  && ok "DNSSEC : les réponses falsifiées sont bien rejetées" \
  || warn "Le test DNSSEC n'a pas donné le résultat attendu"

# =====================================================================
etape "5/8  Libération du port 53 (Ubuntu)"
# =====================================================================
if systemctl is-active --quiet systemd-resolved; then
  mkdir -p /etc/systemd/resolved.conf.d
  printf "[Resolve]\nDNSStubListener=no\n" > /etc/systemd/resolved.conf.d/pihole.conf
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved
  sleep 1
  ok "Le résolveur intégré d'Ubuntu libère le port 53"
else
  ok "Rien à faire"
fi

# =====================================================================
etape "6/8  Installation de Pi-hole branché sur Unbound"
# =====================================================================
if command -v pihole >/dev/null 2>&1; then
  ok "Pi-hole déjà installé : on le rebranche simplement sur Unbound"
else
  # Pi-hole v6 exige un pihole.toml préparé pour s'installer sans questions
  mkdir -p /etc/pihole
  cat > "$PIHOLE_TOML" <<EOF
[dns]
upstreams = ["${UPSTREAM}"]
EOF
  # On télécharge l'installeur officiel dans un fichier (pas de curl | bash)
  curl -fsSL https://install.pi-hole.net -o /tmp/pihole-install.sh \
    || stop "Téléchargement de l'installeur Pi-hole impossible."
  bash /tmp/pihole-install.sh --unattended || stop "L'installation de Pi-hole a échoué."
  rm -f /tmp/pihole-install.sh
fi

# Force Unbound comme SEUL serveur amont (aucun Google/Cloudflare/Quad9)
pihole-FTL --config dns.upstreams "[\"${UPSTREAM}\"]" >/dev/null
ok "Serveur DNS amont : ${UPSTREAM} (Unbound) uniquement"

# Liste de blocage de référence (StevenBlack) si aucune liste n'existe
NB_LISTES=$(pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist;" 2>/dev/null || echo 0)
if [[ "${NB_LISTES:-0}" -eq 0 ]]; then
  pihole-FTL sqlite3 /etc/pihole/gravity.db \
    "INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts', 1, 'StevenBlack');"
fi
pihole -g >/dev/null 2>&1 || warn "Mise à jour des listes de blocage incomplète (relancez : pihole -g)"
ok "Listes de blocage chargées"

# =====================================================================
etape "7/8  Pare-feu (UFW)"
# =====================================================================
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null   # ne JAMAIS se couper l'accès SSH
ufw allow from "$RESEAU" to any port 53 proto udp >/dev/null      # DNS
ufw allow from "$RESEAU" to any port 53 proto tcp >/dev/null
ufw allow from "$RESEAU" to any port 80 proto tcp >/dev/null      # interface web
ufw allow from "$RESEAU" to any port 443 proto tcp >/dev/null
ufw --force enable >/dev/null
ok "Pare-feu actif : DNS et interface web réservés à $RESEAU, SSH conservé"

# =====================================================================
etape "8/8  Tests finaux"
# =====================================================================
ECHEC=0
if grep -q "status: NOERROR" <<<"$(dig wikipedia.org @127.0.0.1 +time=5 || true)"; then
  ok "Pi-hole répond et passe par Unbound"
else
  warn "Pi-hole ne répond pas correctement"; ECHEC=1
fi
BLOQUE=$(dig +short doubleclick.net @127.0.0.1 +time=5 2>/dev/null || true); BLOQUE=${BLOQUE%%$'\n'*}
if [[ "$BLOQUE" == "0.0.0.0" || -z "$BLOQUE" ]]; then
  ok "Blocage actif (doubleclick.net bloqué)"
else
  warn "doubleclick.net n'est pas bloqué (listes peut-être pas encore chargées)"
fi

# ---------- Mot de passe ----------
echo
echo -e "${BLEU}Choisissez le mot de passe de l'interface web Pi-hole :${RAZ}"
pihole setpassword < /dev/tty || warn "Vous pourrez le définir plus tard avec : sudo pihole setpassword"

# ---------- Résumé ----------
echo
echo -e "${VERT}=====================================================================${RAZ}"
[[ $ECHEC -eq 0 ]] && echo -e "${VERT}  INSTALLATION TERMINÉE${RAZ}" || echo -e "${JAUNE}  INSTALLATION TERMINÉE AVEC AVERTISSEMENTS${RAZ}"
echo -e "${VERT}=====================================================================${RAZ}"
echo
echo "  Interface web :  http://${IP_LOCALE}/admin"
echo
echo "  DERNIÈRE ÉTAPE (indispensable) : dans votre box, réglage DHCP/DNS,"
echo "  mettez  ${IP_LOCALE}  comme serveur DNS. Sans ça, aucun appareil"
echo "  du réseau n'utilisera Pi-hole."
echo
echo "  Vérifier depuis un autre PC :  nslookup doubleclick.net ${IP_LOCALE}"
echo "  (réponse 0.0.0.0 = ça marche)"
echo
