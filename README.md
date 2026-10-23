# dns-souverain 🛡️

Transformez un vieux PC en **DNS pour toute la maison** : pubs et pisteurs bloqués sur tous les appareils (PC, téléphones, TV), sans passer par Google, Cloudflare ni votre FAI.

Le script installe et relie automatiquement :

- **[Pi-hole](https://pi-hole.net)** : bloque les domaines de pub et de pistage
- **[Unbound](https://nlnetlabs.nl/projects/unbound/)** : résout les noms en interrogeant directement les serveurs racines d'Internet, sans intermédiaire, avec vérification DNSSEC

Systèmes prévus : **Debian 12/13** et **Ubuntu Server 22.04/24.04**.

---

## Installation en 4 étapes

### 1. Un vieux PC sous Linux

1. Téléchargez [Debian](https://www.debian.org/download) ou [Ubuntu Server](https://ubuntu.com/download/server).
2. Flashez l'image sur une clé USB avec [Rufus](https://rufus.ie) (Windows) ou [balenaEtcher](https://etcher.balena.io) (Mac/Linux).
3. Démarrez le PC sur la clé (touche **F12**, **F8** ou **Suppr** au démarrage) et suivez l'installation.

> ⚠️ Le disque du PC sera **entièrement effacé**.
>
> ⚠️ Pendant l'installation, **cochez « OpenSSH server »** (« serveur SSH » dans la liste des logiciels sous Debian). C'est ce qui permet de piloter le serveur depuis votre PC habituel.

À la fin, connectez-vous et tapez `ip a` pour noter l'adresse du serveur (par exemple `192.168.1.50`).

### 2. Une adresse fixe pour ce PC

Dans l'interface de votre box, rubrique **DHCP**, réservez l'adresse IP actuelle du serveur (« bail statique » ou « IP fixe »). Pas besoin de toucher à Linux pour ça.

### 3. Lancer le script depuis votre PC habituel

Ouvrez un terminal **sur votre PC habituel** (pas sur le serveur) :

| Système | Comment ouvrir un terminal |
|---|---|
| Windows | Touche Windows, tapez `terminal` (ou `powershell`), Entrée |
| Mac | Cmd + Espace, tapez `terminal`, Entrée |
| Linux | Ctrl + Alt + T |

Connectez-vous au serveur avec le nom d'utilisateur et l'IP de l'étape 1 :

```bash
ssh votre_nom@192.168.1.50
```

Répondez `yes` à la première question, puis tapez votre mot de passe (les caractères ne s'affichent pas, c'est normal).

Collez ensuite cette ligne (clic droit sous Windows, Cmd+V sur Mac, Ctrl+Shift+V sous Linux) :

```bash
wget https://raw.githubusercontent.com/Patart50/dns-souverain/main/install-dns-souverain.sh && sudo bash install-dns-souverain.sh
```

Répondez aux questions (`o` = oui) et laissez faire, environ 5 minutes. À la fin, le script vous demande un mot de passe pour l'interface web.

> 💡 Prudent ? Lisez le script avant de le lancer : `less install-dns-souverain.sh` (touche `q` pour quitter), puis `sudo bash install-dns-souverain.sh`.

### 4. Brancher le réseau dessus

Dans votre box, réglages **DHCP / DNS** : indiquez l'IP du serveur comme serveur DNS, puis reconnectez vos appareils (ou redémarrez-les).

**Test** depuis un autre PC :

```bash
nslookup doubleclick.net 192.168.1.50
```

Une réponse `0.0.0.0` signifie que ça marche. 🎉

> ⚠️ Certaines box (notamment la **Livebox**) ne permettent pas de changer le DNS distribué. Dans ce cas, désactivez le DHCP de la box et activez celui de Pi-hole (**Settings > DHCP** dans l'interface web).

Interface d'administration : `http://IP_DU_SERVEUR/admin`

---

## Ce que fait le script

1. Vérifie le système, l'accès Internet et détecte votre réseau local
2. Teste si votre FAI ou votre box intercepte le DNS (ce qui empêcherait Unbound de fonctionner)
3. Installe Unbound sur le port 5335 et vérifie DNSSEC
4. Applique les correctifs connus (`unbound-resolvconf` sous Debian, port 53 sous Ubuntu)
5. Installe Pi-hole avec son installeur officiel, branché **uniquement** sur Unbound
6. Ajoute une liste de blocage de référence ([StevenBlack](https://github.com/StevenBlack/hosts))
7. Active le pare-feu UFW : DNS et interface web réservés au réseau local, **accès SSH conservé**
8. Teste le tout

Le script peut être relancé sans risque : il détecte ce qui est déjà installé.

## Ce que ça apporte, honnêtement

- ✅ Pubs et pisteurs bloqués sur tous les appareils du réseau
- ✅ Plus aucun intermédiaire (Google, Cloudflare, FAI) qui centralise l'historique de vos requêtes DNS
- ✅ Réponses falsifiées rejetées grâce à DNSSEC
- ❌ **Ce n'est pas du chiffrement** : votre FAI peut toujours voir passer les requêtes
- ❌ La première visite d'un site peut être légèrement plus lente (ensuite, tout est en cache)

## Option : DNS chiffré (`--chiffre`)

Par défaut, Unbound interroge directement les serveurs d'Internet. Il n'y a aucun intermédiaire, mais les requêtes circulent en clair : presque aucun de ces serveurs n'accepte de connexion chiffrée. **Résolution directe et chiffrement sont donc incompatibles aujourd'hui.** Il faut choisir :

| | Résolution directe (défaut) | Mode chiffré (`--chiffre`) |
|---|---|---|
| Le FAI voit vos requêtes DNS | Oui | **Non** |
| Un tiers voit tout votre historique DNS | **Non** | Oui (Quad9 ou Mullvad) |
| Dépendance à un service extérieur | Aucune | Le résolveur choisi |

Pour activer le mode chiffré, remplacez la commande de l'étape 3 par :

```bash
wget https://raw.githubusercontent.com/Patart50/dns-souverain/main/install-dns-souverain.sh && sudo bash install-dns-souverain.sh --chiffre
```

Le script vous propose **Quad9** (fondation suisse à but non lucratif) ou **Mullvad** (fournisseur VPN suédois). Les requêtes partent chiffrées en DNS over TLS (port 853), et DNSSEC reste vérifié localement. Relancer le script sans `--chiffre` revient à la résolution directe.

> ⚠️ **Dans les deux cas, votre FAI voit quels sites vous visitez** : il voit les adresses IP contactées et, le plus souvent, le nom du site en clair au début de la connexion HTTPS (SNI). Seul un VPN masque cela. Un DNS chiffré réduit ce que le FAI apprend, il ne vous rend pas invisible.

## Dépannage

| Problème | Piste |
|---|---|
| « Réponse anormale des serveurs racines » | Votre box ou FAI filtre le DNS : vérifiez le contrôle parental ou la sécurité de la box |
| Unbound ne répond pas | `journalctl -u unbound -n 30` (en mode chiffré : vérifiez que le port 853 sortant n'est pas bloqué par la box) |
| Rien n'est bloqué sur les appareils | Vérifiez l'étape 4 (DNS dans la box), puis reconnectez l'appareil |
| Mot de passe de l'interface oublié | `sudo pihole setpassword` |
| Mettre à jour Pi-hole | `sudo pihole -up` |

Bloqué ? Ouvrez une [issue](https://github.com/Patart50/dns-souverain/issues) en copiant le message d'erreur exact affiché par le script.

## Licence et crédits

- Script sous licence [MIT](LICENSE), fourni sans garantie.
- Configuration Unbound adaptée de la [documentation officielle Pi-hole](https://docs.pi-hole.net/guides/dns/unbound/) (CC BY-SA 4.0).
- Pi-hole est installé via son installeur officiel, non modifié. Pi-hole et Unbound restent sous leurs licences respectives.
