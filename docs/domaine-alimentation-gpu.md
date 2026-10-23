# Domaine d'alimentation GPU : module chargé tôt, ou compilé en dur

**Statut** : contournement appliqué (chargement depuis l'initrd). Migration vers
`CONFIG_SUN50I_H6_PRCM_PPU=y` documentée ci-dessous, **non faite**.
**Décideur** : contrainte de démarrage — sans domaine d'alimentation enregistré,
panfrost ne sonde pas et il n'y a ni EGL ni hwaccel.

## Symptôme

Au boot, sur Orange Pi Zero 3 (H618) :

```
panfrost 1800000.gpu: probe with driver panfrost failed with error -110
```

`/dev/dri` ne contient que `card0` : pas de `renderD128`. Conséquences en
cascade, toutes silencieuses :

- Kodi en GBM n'a pas d'EGL et ne s'affiche pas ;
- `ffmpeg -hwaccel drm -hwaccel_device /dev/dri/renderD128` refuse
  `/dev/video0` (« probably not a DRM device? »), donc pas de décodage
  matériel non plus.

Après le boot, la sonde réussit si on la relance à la main :

```
echo 1800000.gpu > /sys/bus/platform/drivers/panfrost/bind
# mali-g31 id 0x7093, [drm] Initialized panfrost, /dev/dri/renderD128 apparaît
```

Ce qui prouve que le GPU et panfrost vont bien : c'est **l'ordre
d'initialisation** qui est en cause.

## Cause

Le domaine d'alimentation du GPU est fourni par le driver
`sun50i_h6_prcm_ppu`. Dans la config Armbian de la famille sunxi64, il est
compilé **en module** :

```
# linux-sunxi64-edge.config
CONFIG_SUN50I_H6_PRCM_PPU=m
```

Le lien matériel est explicite dans le DTB :

```
power-controller@7010250 {
        compatible = "allwinner,sun50i-h616-prcm-ppu";
        #power-domain-cells = <0x01>;
        phandle = <0x11>;
};
gpu@1800000 {
        compatible = "allwinner,sun50i-h616-mali", "arm,mali-bifrost";
        power-domains = <0x11 0x02>;
};
```

`panfrost` et `sun50i_h6_prcm_ppu` sont tous deux des modules, chargés par udev
via leur alias OF :

```
alias of:N*T*Callwinner,sun50i-h616-prcm-ppuC* sun50i_h6_prcm_ppu
```

udev traite les événements `of:` en parallèle : **l'ordre n'est pas garanti**.
Quand panfrost sonde en premier, le fournisseur de domaine n'existe pas encore ;
le noyau attend le *deferred probe timeout* puis force la sonde, qui échoue
faute de fournisseur (-110).

`softdep panfrost pre: sun50i_h6_prcm_ppu` **ne corrige pas** cela : `softdep`
est appliqué par `modprobe`, pas par le chargement par alias d'udev. Mesuré :
le -110 persiste avec le softdep en place.

## Contournement en place

Charger le module **avant** tout coldplug udev, c'est-à-dire depuis l'initrd :

```nix
boot.kernelModules = [ "zram" "sun50i_h6_prcm_ppu" ];
boot.initrd.kernelModules = [ "sun50i_h6_prcm_ppu" ];
```

`boot.kernelModules` n'est pas décoratif : l'élagage des modules du noyau
n'embarque que les modules cités dans `boot.kernelModules` (plus une liste
d'exceptions), donc sans cette ligne le `.ko` disparaît de l'image.

Vérification — dans l'initrd produit, pas dans l'option Nix :

```
initrd=…-initrd-linux-*.initrd
zstdcat "$initrd" | cpio -t | grep prcm-ppu          # le .ko est présent
zstdcat "$initrd" | cpio -idm && cat etc/modules-load.d/nixos.conf
#   → sun50i_h6_prcm_ppu
ls etc/systemd/system/*.wants/systemd-modules-load.service
#   → activé (sysinit.target.wants ou basic.target.wants selon la version)
zstdcat "$initrd" | cpio -t | grep panfrost           # absent : ne peut pas sonder
```

Le dernier point est ce qui rend la garantie solide : `panfrost` n'est pas dans
l'initrd, il ne sonde donc qu'après le switch-root, quand le domaine est déjà
enregistré. L'ordre interne de l'initrd n'a plus d'importance.

Deux filets restent en place, sans être la garantie principale : le `softdep`,
et une unité `panfrost-rebind` qui rebinde si `/dev/dri/renderD128` manque. Sa
garde doit porter sur `/sys/bus/platform/devices/1800000.gpu` — **pas** sur
`/sys/bus/platform/drivers/panfrost/1800000.gpu`, qui n'existe qu'une fois
l'appareil déjà lié, donc jamais quand il faut.

## Migration vers `=y`

Objectif : que le domaine soit enregistré à l'initialisation du noyau, avant
tout module. Plus de dépendance à l'initrd ni à l'élagage.

1. **Côté noyau** (`nixbian`) — passer le symbole en dur dans les configs de la
   famille sunxi64 :

   ```
   metadata/nix/families/sunxi64/configs/linux-sunxi64-edge.config
   metadata/nix/families/sunxi64/configs/linux-sunxi64-current.config
   metadata/nix/families/sunxi64/configs/linux-sunxi64-legacy.config
   CONFIG_SUN50I_H6_PRCM_PPU=m   →   CONFIG_SUN50I_H6_PRCM_PPU=y
   ```

   Ces fichiers sont **régénérés** (`src/armbian_extractor/generator.py`,
   pipeline `sync-kernel-versions`). Éditer le `.config` sans traiter la source
   de vérité, c'est perdre la modification à la régénération suivante : vérifier
   d'abord si le générateur expose un fragment de famille, sinon ajouter la
   ligne au générateur en même temps.

2. **CI noyau** : le noyau est reconstruit (les runners natifs + cross
   remplissent le cache binaire). Coût payé une fois, pour toutes les boards
   sunxi64.

3. **Côté image** — bumper la révision nixbian épinglée, puis **retirer** dans
   le profil kiosque, dans cet ordre :

   - `boot.initrd.kernelModules = [ "sun50i_h6_prcm_ppu" ]` → **obligatoire** :
     le module n'existe plus, l'initrd échoue au build ;
   - `"sun50i_h6_prcm_ppu"` dans `boot.kernelModules` ;
   - `boot.extraModprobeConfig = "softdep panfrost pre: sun50i_h6_prcm_ppu"` ;
   - `systemd.services.panfrost-rebind` et son descripteur.

4. **Validation** :

   ```
   ls /dev/dri                      # card0 + renderD128 dès le boot
   dmesg | grep -iE "panfrost|prcm" # mali-g31 id 0x7093, aucun -110
   ```

   Le driver compilé en dur apparaît toujours dans
   `/sys/bus/platform/drivers/sun50i_h6_prcm_ppu` (pas dans `modinfo`).

## Coût comparé

| | `=m` + initrd (actuel) | `=y` (cible) |
|---|---|---|
| Garantie portée par | la config de l'image (initrd + allowlist d'élagage) | le noyau |
| Dépend du chemin de boot | oui (netboot, kexec, initrd custom) | non |
| Échec possible si | ligne retirée, module élagué, initrd régénéré ailleurs | config perdue à la régénération |
| Coût de mise en place | nul | rebuild noyau partagé (CI) |
| Empreinte | ~250 Ko d'initrd | quelques Ko dans l'image noyau, sur toutes les boards sunxi64 |

## Ce qu'il ne faut pas faire

- **`softdep` seul** : mesuré inefficace, udev ne passe pas par `modprobe` pour
  les alias OF.
- **Charger le module depuis un service après udev** : trop tard, panfrost a
  déjà été sondé et a échoué ; le rebind manuel n'est qu'un rattrapage.
- **Rendre l'unité de rebind obligatoire** : elle masque la cause au lieu de la
  traiter, et un rebind tardif laisse Kodi sans EGL au démarrage.
