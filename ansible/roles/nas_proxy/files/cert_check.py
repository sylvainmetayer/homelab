#!/usr/bin/python3
"""Échéance des certificats que sert le Traefik du NAS (rôle nas_proxy).

Lancé chaque jour par nas-proxy-cert-check.timer, en root, sur le NAS même :
ses noms pointent sur son IP LAN, hors de portée de l'Uptime Kuma hébergé chez
PikaPods. Se connecte au port publié avec chaque nom en SNI, vérifie la chaîne
et le nom contre le magasin du système (ce que vérifie un navigateur de la
maison), puis pousse le résultat au moniteur push « Certificats NAS »
(tofu/pangolin_config) : status=up avec les jours restants de chaque nom, ou
status=down avec la raison, aussitôt. Sans aucun push (NAS éteint, timer
mort), le moniteur passe aussi au rouge au bout de son intervalle.

Bibliothèque standard seule : UGOS n'installe rien (pas d'apt), mais Ansible
s'appuie déjà sur son /usr/bin/python3. L'URL push porte le jeton du
moniteur : lue dans l'environnement (EnvironmentFile de l'unité, 0600 root),
jamais sur la ligne de commande, jamais affichée.
"""

import argparse
import os
import socket
import ssl
import sys
import time
import urllib.parse
import urllib.request

PUSH_URL_VARIABLE = "NAS_PROXY_CERT_PUSH_URL"


def days_left(host, port, name, context):
    """Jours restants avant le notAfter du certificat servi pour `name`."""
    # Hôte et port viennent de l'ExecStart de l'unité (root), pas d'une entrée
    # extérieure : la règle SSRF de Sonar ne s'applique pas.
    with (
        socket.create_connection((host, port), timeout=15) as sock,  # NOSONAR
        context.wrap_socket(sock, server_hostname=name) as tls,
    ):
        cert = tls.getpeercert()
    return (ssl.cert_time_to_seconds(cert["notAfter"]) - time.time()) / 86400


def push(url, status, msg):
    query = urllib.parse.urlencode({"status": status, "msg": msg, "ping": ""})
    separator = "&" if "?" in url else "?"
    with urllib.request.urlopen(url + separator + query, timeout=30) as response:
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--min-days", type=int, required=True)
    parser.add_argument("names", nargs="+")
    args = parser.parse_args(argv)

    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    problems, report = [], []
    for name in args.names:
        try:
            days = days_left(args.host, args.port, name, context)
        except (OSError, ValueError, KeyError) as error:
            # ssl.SSLCertVerificationError (expiré, mauvais nom, AC inconnue)
            # est une OSError, comme une connexion refusée.
            problems.append(f"{name}: {error}")
            continue
        report.append(f"{name}: {days:.0f} j")
        if days < args.min_days:
            problems.append(f"{name}: expire dans {days:.1f} j (seuil {args.min_days} j)")

    status = "down" if problems else "up"
    msg = "; ".join(problems or report)
    print(f"{status}: {msg}", flush=True)

    url = os.environ.get(PUSH_URL_VARIABLE, "")
    if url:
        try:
            push(url, status, msg)
        except OSError as error:
            # Une erreur d'urllib peut citer l'URL : sa classe seule est affichée.
            print(f"push vers Uptime Kuma en échec : {type(error).__name__}", file=sys.stderr)
            return 2
    else:
        print(f"{PUSH_URL_VARIABLE} vide : rien n'est poussé.", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
