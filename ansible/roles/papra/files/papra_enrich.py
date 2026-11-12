#!/usr/bin/python3
"""Remplissage par l'IA du Montant, de la Fin de validité et des tags des
documents Papra (rôle papra, papra-enrich.timer).

Un document part au modèle (passerelle IA de Pangolin, format OpenAI) seulement
s'il porte au moins un tag, aucun des tags exclus ni la marque de traitement,
s'il a été importé il y a plus de 24 h et s'il a du texte (au plus skip_chars
caractères, tronqué à max_chars). Un tag exclu ou la marque introuvable dans
Papra arrête le passage avant tout envoi : la liste d'exclusion est la garde
des pièces sensibles, un tag pas encore créé n'en protégerait aucune.

Seuls les champs vides sont remplis ; les tags ajoutés sont pris parmi ceux
qui existent, hors exclus, jamais créés ; la marque est posée en premier. Journal :
identifiant, champs remplis, tokens, jamais le nom ni le contenu. Une erreur
de la passerelle, un 429 ou un 5xx arrête le passage, sans nouvel essai ; un
document que Papra refuse (4xx) est journalisé et laissé.

Bibliothèque standard seule. Configuration (clés Papra et passerelle) : un
fichier JSON 0600 du compte de l'unité, jamais la ligne de commande.

Usage :
  papra_enrich.py --config /etc/papra-enrich.json [--dry-run] [--limit N]
  --dry-run : interroge le modèle (des tokens partent), n'écrit rien dans
  Papra et affiche les valeurs proposées : à lancer dans un terminal, jamais
  par l'unité (le journal ne garde aucune valeur).
"""

import argparse
import datetime
import json
import math
import subprocess
import sys
import urllib.error
import urllib.request

PAPRA_PORT = 1221
MIN_AGE = datetime.timedelta(hours=24)
PROMPT = """Tu lis le texte d'un document personnel (facture, contrat, courrier...) et tu réponds uniquement par un objet JSON :
{"montant": nombre ou null, "fin_validite": "AAAA-MM-JJ" ou null, "tags": [noms]}
- montant : le total TTC à payer de la facture, frais compris, en nombre (point décimal). Pas une facture, ou pas de total : null.
- fin_validite : seulement une date de fin de garantie, de fin de contrat ou d'expiration écrite explicitement dans le document. Jamais une date d'échéance de paiement, d'émission ou de facture. Sinon null.
- tags : ceux de la liste donnée qui décrivent le document, recopiés à l'identique ; aucun autre. Liste vide si aucun ne convient.
N'invente rien : dans le doute, null ou liste vide."""


def log(message):
    print(message, flush=True)


def papra_url(container):
    """Papra par l'IP de son conteneur sur le réseau newt : aucun port publié
    sur l'hôte, et l'URL publique passe par le mur SSO."""
    # container : configuration 0600 écrite par Ansible, pas une entrée extérieure.
    out = subprocess.run(  # NOSONAR
        ["docker", "inspect", "-f", '{{(index .NetworkSettings.Networks "newt").IPAddress}}', container],
        capture_output=True, text=True, check=True,
    )
    if not out.stdout.strip():
        raise RuntimeError(f"conteneur {container} sans adresse sur le réseau newt")
    # IP d'un conteneur du réseau Docker local : pas de TLS à vérifier.
    return f"http://{out.stdout.strip()}:{PAPRA_PORT}"  # NOSONAR


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Aucune redirection suivie : urllib rejouerait le Bearer (Papra ou passerelle) vers
# la cible ; la 3xx lève HTTPError et arrête le passage.
_OPENER = urllib.request.build_opener(_NoRedirect)


def call(url, key, body=None, method=None):
    # URL faite de la configuration (0600, écrite par Ansible) et d'identifiants rendus par Papra.
    request = urllib.request.Request(  # NOSONAR
        url,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method=method,
    )
    with _OPENER.open(request, timeout=120) as response:  # NOSONAR
        payload = response.read()
    return json.loads(payload) if payload else None


def tag_names(doc):
    return {tag["name"].casefold() for tag in doc.get("tags", [])}


def eligible(doc, ctx):
    tags = tag_names(doc)
    created = datetime.datetime.fromisoformat(doc["createdAt"].replace("Z", "+00:00"))
    return bool(tags) and not tags & ctx["excluded"] and ctx["done"] not in tags and ctx["now"] - created > MIN_AGE


def amount(value):
    ok = isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    return value if ok else None


def expiry(value):
    try:
        return datetime.date.fromisoformat(value).isoformat()
    except (TypeError, ValueError):
        return None


def ask(config, allowed, text):
    """Réponse du modèle (dict ; RuntimeError si elle n'en contient pas) et tokens consommés."""
    body = {
        "model": config["model"],
        # Large : les modèles Claude 5 réfléchissent avant de répondre, et cette
        # réflexion compte dans max_tokens (à 300, la réponse revenait vide).
        "max_tokens": 3000,
        "messages": [
            {"role": "system", "content": PROMPT},
            {"role": "user", "content": f"Tags existants : {json.dumps(allowed, ensure_ascii=False)}\n\nTexte :\n{text}"},
        ],
    }
    reply = call(f"{config['ai_base_url']}/chat/completions", config["ai_api_key"], body)
    content = reply["choices"][0]["message"]["content"] or ""
    tokens = reply.get("usage", {}).get("total_tokens", "?")
    try:
        answer = json.loads(content[content.index("{") : content.rindex("}") + 1])
    except ValueError:
        answer = None
    if not isinstance(answer, dict):
        # Arrête le passage : continuer marquerait « traité » un document resté
        # vide, et le renverrait au modèle pour rien s'il ne l'était pas.
        reason = reply["choices"][0].get("finish_reason")
        raise RuntimeError(f"réponse du modèle sans objet JSON (fin : {reason}, {tokens} tokens)")
    return answer, tokens


def enrich(ctx, doc_id):
    """Traite un document ; vrai s'il est parti au modèle."""
    config, base, key = ctx["config"], ctx["base"], ctx["config"]["papra_api_key"]
    doc = call(f"{base}/documents/{doc_id}", key)["document"]
    if not eligible(doc, ctx):  # relu : un tag exclu a pu arriver depuis la liste
        return False
    text = (doc.get("content") or "").strip()
    if not text or len(text) > config["skip_chars"]:
        log(f"Document {doc_id} : sauté ({f'{len(text)} caractères' if text else 'sans texte'})")
        return False
    answer, tokens = ask(config, ctx["allowed"], text[: config["max_chars"]])
    current = {prop["name"]: prop["value"] for prop in doc.get("customProperties", [])}
    fields = {}
    for field, check in (("montant", amount), ("fin_validite", expiry)):
        definition = ctx["properties"][field]
        value = check(answer.get(field))
        if value is not None and current.get(definition["name"]) is None:  # jamais une valeur saisie
            fields[field] = (definition["id"], value)
    proposed = answer.get("tags") if isinstance(answer.get("tags"), list) else []
    allowed = {name.casefold() for name in ctx["allowed"]}
    new_tags = sorted(
        {name.casefold() for name in proposed if isinstance(name, str)} & allowed - tag_names(doc)
    )
    if ctx["dry_run"]:
        shown = {field: value for field, (_, value) in fields.items()}
        names = [ctx["tags"][name]["name"] for name in new_tags]
        log(f"Document {doc_id} (à blanc) : {shown}, tags {names}, {tokens} tokens")
        return True
    # La marque d'abord : une écriture refusée ensuite ne renvoie pas le document au modèle.
    for name in [ctx["done"]] + new_tags:
        call(f"{base}/documents/{doc_id}/tags", key, {"tagId": ctx["tags"][name]["id"]})
    for definition_id, value in fields.values():
        call(f"{base}/documents/{doc_id}/custom-properties/{definition_id}", key, {"value": value}, "PUT")
    filled = ", ".join(fields) or "aucun champ"
    log(f"Document {doc_id} : {filled} rempli(s), {len(new_tags)} tag(s) ajouté(s), {tokens} tokens")
    return True


def run(config, dry_run, limit):
    base = f"{papra_url(config['container'])}/api/organizations/{config['organization_id']}"
    key = config["papra_api_key"]
    tags = {tag["name"].casefold(): tag for tag in call(f"{base}/tags", key)["tags"]}
    guarded = config["excluded_tags"] + [config["done_tag"]]
    missing = [name for name in guarded if name.casefold() not in tags]
    if missing:
        raise RuntimeError(f"tag(s) introuvable(s) dans Papra : {', '.join(missing)} ; rien n'est envoyé")
    definitions = {d["name"]: d for d in call(f"{base}/custom-properties", key)["propertyDefinitions"]}
    properties = {}
    for field, name, kind in (("montant", config["amount_property"], "number"), ("fin_validite", config["expiry_property"], "date")):
        if definitions.get(name, {}).get("type") != kind:
            raise RuntimeError(f"propriété « {name} » de type {kind} introuvable dans Papra")
        properties[field] = definitions[name]
    excluded = {name.casefold() for name in guarded}
    ctx = {
        "config": config, "base": base, "tags": tags, "properties": properties, "dry_run": dry_run,
        "excluded": excluded, "done": config["done_tag"].casefold(),
        "allowed": sorted(tag["name"] for name, tag in tags.items() if name not in excluded),
        "now": datetime.datetime.now(datetime.timezone.utc),
    }
    sent, page = 0, 0
    # Les plus anciens d'abord : l'arriéré, puis les nouveaux au fil de l'eau.
    # limit : batch_size de la configuration (Ansible) ou --limit ; la boucle s'arrête à la page vide.
    while sent < limit:  # NOSONAR
        query = f"pageIndex={page}&pageSize=100&sortField=createdAt&sortOrder=asc"
        docs = call(f"{base}/documents?{query}", key)["documents"]
        if not docs:
            break
        for doc in docs:
            if sent >= limit or not eligible(doc, ctx):
                continue
            try:
                sent += enrich(ctx, doc["id"])
            except urllib.error.HTTPError as e:
                # Un document que Papra refuse (404, 400) ne bloque pas les suivants ;
                # la passerelle, un 429 ou un 5xx arrêtent le passage.
                if not str(e.filename).startswith(base) or e.code == 429 or e.code >= 500:
                    raise
                log(f"Document {doc['id']} : HTTP {e.code} de Papra, laissé")
        page += 1
    log(f"Passage terminé : {sent} document(s) envoyé(s) au modèle")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True)
    parser.add_argument("--dry-run", action="store_true", help="rien n'est écrit dans Papra")
    parser.add_argument("--limit", type=int, help="documents envoyés au plus (défaut : batch_size)")
    args = parser.parse_args()
    # Chemin donné par l'unité systemd (ou l'opérateur).
    with open(args.config, encoding="utf-8") as f:  # NOSONAR
        config = json.load(f)
    try:
        run(config, args.dry_run, config["batch_size"] if args.limit is None else args.limit)
    except urllib.error.HTTPError as e:
        # Jamais le corps de la réponse : il pourrait reprendre le document.
        log(f"Passage arrêté : HTTP {e.code} sur {str(e.filename).split('?')[0]}")
        return 1
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as e:
        log(f"Passage arrêté : {type(e).__name__}: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
