# ntfy : plus aucune notification sur Android

## Symptôme

Le **29/10/2026**, le téléphone Android n'a plus reçu aucune notification ntfy
**de 18:24 au lendemain 07:27**, sans erreur visible. Telegram recevait toujours
les alertes.

## Cause

Le retrait du topic `beszel` (PR #978) alors qu'il restait abonné dans
l'appli. L'appli Android ouvre **une seule connexion pour tous ses topics** : si
`sylvain` ne peut plus en lire un seul, ntfy refuse la connexion entière (403).
L'appli iOS interroge chaque topic à part : seul le topic retiré y échoue.

## Ce qui a manqué

- Le contrôle de santé de ntfy restait **vert** : il ne voit pas des téléphones
  qui ne reçoivent plus.
- Aucune alerte côté serveur, aucune erreur visible dans l'appli.
- Une procédure de retrait d'un topic ; elle est écrite depuis (ce qui existait
  avant : à confirmer).

## Action

- `sylvain` lit tous les topics (joker en lecture) : un topic retiré reste
  lisible, vide. **Ne pas retirer ce joker.**
- Alerte « aucun abonné » : une vérification toutes les 10 minutes sur la VM
  docker lit les relevés `Server stats` de ntfy et passe au rouge après 8
  heures sans abonné. Elle ne voit rien si un autre téléphone ou l'interface
  web reste abonné.
- Procédure de retrait : [ansible/roles/ntfy/README.md](../../ansible/roles/ntfy/README.md),
  « Retirer un topic » (désabonner d'abord, puis merger).

Sources : `ansible/roles/ntfy/README.md` ; `ansible/roles/ci_key_audit/README.md`
(ntfy accepte une publication sans abonné, d'où le doublon Telegram).
