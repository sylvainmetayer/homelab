# Image de test Molecule : Debian 13 (comme la VM Docker, Pangolin et flip)
# avec systemd en PID 1, pour que les unités système, les unités *user*
# (dc@<service>, lingering) et un démon Docker tournent comme sur un vrai hôte.
#
# Construite une fois par job CI (`mise run molecule-image`), puis réutilisée
# par tous les scénarios (`pre_build_image: true` dans .config/molecule/config.yml).
ARG BASE_IMAGE=debian:trixie
FROM ${BASE_IMAGE}

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive

# Les listes apt restent dans l'image : les rôles installent leurs paquets sans
# toujours rafraîchir le cache, comme sur les hôtes réels.
# docker.io + docker-cli + docker-compose (plugin `docker compose`) : le démon
# sert à créer le réseau `newt` et aux rôles qui inspectent Docker ;
# `docker compose config` valide les compose templatés. Aucune image applicative n'est tirée (cf. _shared/prepare.yml).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        dbus-user-session \
        docker-cli \
        docker-compose \
        docker.io \
        gnupg \
        iproute2 \
        libpam-systemd \
        procps \
        python3 \
        python3-apt \
        python3-packaging \
        python3-venv \
        sudo \
        systemd \
        systemd-sysv \
    && apt-get clean \
    && docker --version \
    && docker compose version

# Les playbooks se connectent en `sylvain` et passent root par sudo : on
# reproduit ce modèle, c'est lui que docker_service (unités user, lingering)
# et les `become` des rôles supposent.
RUN useradd --create-home --shell /bin/bash --uid 1000 sylvain \
    && usermod -aG docker sylvain \
    && echo 'sylvain ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/sylvain \
    && chmod 0440 /etc/sudoers.d/sylvain

# Unités inutiles ou impossibles dans un conteneur.
RUN systemctl mask \
        getty.target \
        console-getty.service \
        systemd-firstboot.service \
        systemd-udevd.service \
        systemd-udev-trigger.service \
        systemd-remount-fs.service \
        dev-hugepages.mount \
        sys-fs-fuse-connections.mount

STOPSIGNAL SIGRTMIN+3
VOLUME ["/var/lib/docker"]
CMD ["/lib/systemd/systemd"]
