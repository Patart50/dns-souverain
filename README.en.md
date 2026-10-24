# dns-souverain 🛡️

🇫🇷 [Version française](README.md) · 🇬🇧 English

> ⚠️ **Early-stage project, feedback welcome**
> This script was written carefully, but I haven't been able to test it on every possible setup (router models, Debian/Ubuntu versions, ISPs…). Some bugs may remain, and I apologise in advance.
> If something doesn't work for you, please open an [issue](https://github.com/Patart50/dns-souverain/issues) with the exact error message, your system and your router model, and I'll fix it as quickly as I can. Read the script before running it, and try it first on a machine with no important data.

Turn an old PC into a **DNS server for your whole home**: ads and trackers blocked on every device (computers, phones, TV), without going through Google, Cloudflare or your ISP.

The script automatically installs and wires together:

- **[Pi-hole](https://pi-hole.net)**: blocks advertising and tracking domains
- **[Unbound](https://nlnetlabs.nl/projects/unbound/)**: resolves names by querying the Internet's root servers directly, with no middleman, and validates DNSSEC

Supported systems: **Debian 12/13** and **Ubuntu Server 22.04/24.04**.

> ℹ️ The script's on-screen messages are in French. Yes/no prompts expect `o` (oui = yes); `y` also works.

---

## Installation in 4 steps

### 1. An old PC running Linux

1. Download [Debian](https://www.debian.org/download) or [Ubuntu Server](https://ubuntu.com/download/server).
2. Write the image to a USB stick with [Rufus](https://rufus.ie) (Windows) or [balenaEtcher](https://etcher.balena.io) (Mac/Linux).
3. Boot the PC from the stick (press **F12**, **F8** or **Del** at startup) and follow the installer.

> ⚠️ The PC's disk will be **completely erased**.
>
> ⚠️ During installation, **tick "OpenSSH server"** ("SSH server" in Debian's software selection). This is what lets you control the server from your everyday computer.

When it's done, log in and type `ip a` to note the server's address (for example `192.168.1.50`).

### 2. A fixed address for this PC

In your router's admin page, under **DHCP**, reserve the server's current IP address ("static lease", "DHCP reservation" or "fixed IP"). No need to touch Linux for this.

### 3. Run the script from your everyday computer

Open a terminal **on your everyday computer** (not on the server):

| System | How to open a terminal |
|---|---|
| Windows | Windows key, type `terminal` (or `powershell`), Enter |
| Mac | Cmd + Space, type `terminal`, Enter |
| Linux | Ctrl + Alt + T |

Connect to the server using the username and IP from step 1:

```bash
ssh your_name@192.168.1.50
```

Answer `yes` to the first question, then type your password (characters don't show up, that's normal).

Then paste this line (right-click on Windows, Cmd+V on Mac, Ctrl+Shift+V on Linux):

```bash
wget https://raw.githubusercontent.com/Patart50/dns-souverain/main/install-dns-souverain.sh && sudo bash install-dns-souverain.sh
```

Answer the questions (`o` = yes) and let it run, about 5 minutes. At the end, the script asks you for a password for the web interface.

> 💡 Cautious? Read the script before running it: `less install-dns-souverain.sh` (press `q` to quit), then `sudo bash install-dns-souverain.sh`.

### 4. Point your network at it

In your router's **DHCP / DNS** settings, enter the server's IP as the DNS server, then reconnect (or restart) your devices.

**Test** from another computer:

```bash
nslookup doubleclick.net 192.168.1.50
```

An answer of `0.0.0.0` means it works. 🎉

> ⚠️ Some ISP routers (for example Orange's **Livebox** in France) don't let you change the DNS server they hand out. In that case, disable the router's DHCP server and enable Pi-hole's instead (**Settings > DHCP** in the web interface).

Admin interface: `http://SERVER_IP/admin`

---

## What the script does

1. Checks the system and Internet access, and detects your local network
2. Tests whether your ISP or router intercepts DNS traffic (which would stop Unbound from working)
3. Installs Unbound on port 5335 and checks DNSSEC validation
4. Applies known fixes (`unbound-resolvconf` on Debian, port 53 on Ubuntu)
5. Installs Pi-hole with its official installer, connected **only** to Unbound
6. Adds a reference blocklist ([StevenBlack](https://github.com/StevenBlack/hosts))
7. Enables the UFW firewall: DNS and web interface restricted to the local network, **SSH access kept**
8. Tests everything

The script is safe to re-run: it detects what is already installed.

## What you get, honestly

- ✅ Ads and trackers blocked on every device on the network
- ✅ No more middleman (Google, Cloudflare, ISP) collecting your DNS history in one place
- ✅ Forged answers rejected thanks to DNSSEC
- ❌ **This is not encryption**: your ISP can still see the queries go by
- ❌ The first visit to a site can be slightly slower (after that, everything is cached)

## Option: encrypted DNS (`--chiffre`)

By default, Unbound queries the Internet's servers directly. There's no middleman, but queries travel in clear text: almost none of those servers accept encrypted connections. **Direct resolution and encryption are therefore incompatible today.** You have to choose:

| | Direct resolution (default) | Encrypted mode (`--chiffre`) |
|---|---|---|
| Your ISP sees your DNS queries | Yes | **No** |
| A third party sees your whole DNS history | **No** | Yes (Quad9 or Mullvad) |
| Dependence on an outside service | None | The chosen resolver |

To enable encrypted mode, replace the step 3 command with:

```bash
wget https://raw.githubusercontent.com/Patart50/dns-souverain/main/install-dns-souverain.sh && sudo bash install-dns-souverain.sh --chiffre
```

The script lets you pick **Quad9** (Swiss non-profit foundation) or **Mullvad** (Swedish VPN provider). You can also skip the question with `--chiffre=quad9` or `--chiffre=mullvad`. Queries are sent encrypted over DNS over TLS (port 853), and DNSSEC is still validated locally. Re-running the script without `--chiffre` switches back to direct resolution.

> ⚠️ **Either way, your ISP can see which sites you visit**: it sees the IP addresses you connect to and, in most cases, the site name in clear text at the start of the HTTPS connection (SNI). Only a VPN hides that. Encrypted DNS reduces what your ISP learns; it doesn't make you invisible.

## Troubleshooting

| Problem | What to check |
|---|---|
| "Réponse anormale des serveurs racines" (abnormal answer from root servers) | Your router or ISP filters DNS: check the router's parental controls or security features |
| Unbound doesn't respond | `journalctl -u unbound -n 30` (in encrypted mode: check that outgoing port 853 isn't blocked by your router) |
| Nothing is blocked on devices | Check step 4 (DNS in the router), then reconnect the device |
| Forgot the web interface password | `sudo pihole setpassword` |
| Update Pi-hole | `sudo pihole -up` |

Stuck? Open an [issue](https://github.com/Patart50/dns-souverain/issues) and paste the exact error message shown by the script.

## License and credits

- Script released under the [MIT](LICENSE) license, provided without warranty.
- Unbound configuration adapted from the [official Pi-hole documentation](https://docs.pi-hole.net/guides/dns/unbound/) (CC BY-SA 4.0).
- Pi-hole is installed with its official, unmodified installer. Pi-hole and Unbound remain under their respective licenses.
