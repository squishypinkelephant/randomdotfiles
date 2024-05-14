(use-modules
    (gnu)
    (gnu home)
    (gnu home services)
    (gnu home services desktop)
    (gnu home services gnupg)
    (gnu home services guix)
    (gnu home services shells)
    (gnu home services sound)
    (guix channels)
    (nongnu packages linux)
    (nongnu system linux-initrd)
    )
(use-package-modules
    admin
    freedesktop
    gimp
    kde-frameworks
    kde-games
    kde-internet
    kde-multimedia
    kde-pim
    kde-plasma
    kde-systemtools
    kde-utils
    version-control
    )
(use-service-modules
    admin
    audio
    desktop
    guix
    linux
    networking
    pm
    sddm
    sound
    xorg
    )

(define rootdisk
    (uuid "11e5bb8d-67d1-4b04-9ace-e091d1284032"))

(define rootfs
    (file-system
        (device "tmpfs")
        (type "tmpfs")
        (mount-point "/")
        (options "defaults,size=8G,mode=755")))
(define rootfs-boot
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/boot")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/boot")))
(define rootfs-home
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/home")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/home")))
(define rootfs-swap
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/swap")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=swap")))
(define var-guix
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/var/guix")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/var/guix")))
(define var-lib
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/var/lib")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/var/lib")))
(define var-log
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/var/log")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/var/log")))
(define gnu-store
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/gnu/store")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/gnu/store")))
(define gnu-persist
    (file-system
        (device rootdisk)
        (type "btrfs")
        (mount-point "/gnu/persist")
        (create-mount-point? #t)
        (options "compress=zstd,subvol=mothership/gnu/persist")))

(define default-home
    (home-environment
        (packages (list
            gimp
            htop
            falkon
        ))
        (services (list
            (service home-bash-service-type)
            (service home-gpg-agent-service-type)
            (service home-dbus-service-type)
            (simple-service 'variant-packages-service home-channels-service-type (list
                (channel (name 'guix)
                    (url "https://git.savannah.gnu.org/git/guix.git")
                    (commit "6e86089d563ccb67ae04cd941ca7b66c1777831f"))
                (channel (name 'nonguix)
                    (url "https://gitlab.com/nonguix/nonguix")
                    (commit "7081518be7d2dbb58f3fbfeb1785254a6f0059c8"))))
                    ;; frozen to 5-14-2024
            (service home-pipewire-service-type)
        ))
    ))

(operating-system
    ;; simple things
    (host-name "Mothership")
    (timezone "America/Chicago")
    (locale "en_US.utf8")
    (keyboard-layout (keyboard-layout "us"))

    ;; kernel and bootloader
    (kernel linux)
    (initrd microcode-initrd)
    (firmware (list linux-firmware))

    (bootloader (bootloader-configuration
        (bootloader grub-efi-bootloader)
        (targets '("/boot/efi"))
        (keyboard-layout keyboard-layout)))

    ;; users and groups
    (users (append (list
        (user-account
            (name "workstation")
            (group "workstation")
            (supplementary-groups '("users" "wheel" "netdev" "audio" "video")))
        )
    %base-user-accounts))
    (groups (append (list
        (user-group
            (name "workstation")))
    %base-groups))

    ;; filesystems
    (file-systems (append (list
        rootfs
        rootfs-boot
        rootfs-home
        rootfs-swap
        var-guix
        var-lib
        var-log
        gnu-store
        gnu-persist
        ;; esp
        (file-system
            (device (uuid "9506-D66D" 'fat))
            (type "vfat")
            (dependencies (list rootfs-boot))
            (mount-point "/boot/efi")
            (create-mount-point? #t)   )
        ;; persist junk
        (file-system
            (device "/gnu/persist/etc/NetworkManager")
            (type "none")
            (dependencies (list gnu-persist))
            (mount-point "/etc/NetworkManager")
            (create-mount-point? #t)
            (flags '(bind-mount)))
        (file-system
            (device "/gnu/persist/etc/ssh")
            (type "none")
            (dependencies (list gnu-persist))
            (mount-point "/etc/ssh")
            (create-mount-point? #t)
            (flags '(bind-mount)))
        )
    %base-file-systems))
    ;; swap
    (swap-devices (list
        (swap-space
            (target "/swap/swapfile")
            (dependencies (list rootfs-swap)))
    ))

    ;; services
    (services (append (list
        (service earlyoom-service-type)
        (service fstrim-service-type)
        (service plasma-desktop-service-type)
        (service sddm-service-type)
        (service tlp-service-type)
        (service home-service-type
            '(("workstation", default-home)))
        (service zram-device-service-type
            (zram-device-configuration
                (size "8G")
                (compression-algorithm 'zstd)
                (priority "200")))
        ;; persist regular files
        (extra-special-file "/etc/machine-id" "/gnu/persist/etc/machine-id")
        )
        (modify-services %desktop-services
        (delete gdm-service-type)
        (guix-service-type config => (guix-configuration
                (inherit config)
                (substitute-urls (append (list
                    "https://substitutes.nonguix.org")
                    %default-substitute-urls))
                (authorized-keys (append (list
                    (plain-file "non-guix.pub"
                    "(public-key (ecc (curve Ed25519) (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))"))
                    %default-authorized-guix-keys)))))
    ))
    ;; global packages. this shouldn't ever be long. maybe...
    (packages (append (list
        ;; SHOULD be default ?
        git
        ;; important for users???
        xdg-desktop-portal
        xdg-desktop-portal-kde
        xdg-user-dirs
        xdg-utils
        )
    %base-packages))

)
