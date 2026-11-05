"""Fenêtre de calme de deploy-docker-app (ADR 0029).

Un déploiement automatique (push ou schedule) ne part pas de 19:00 à 08:00,
heure de Paris, tous les jours ; un workflow_dispatch part toujours. Sortie 0 :
fenêtre ouverte. Sortie 1 : fermée (le workflow annule alors le run, qui n'est
jamais un « dernier run réussi » : le suivant rattrape ses commits).
"""

import os
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
OPEN_HOUR, CLOSE_HOUR = 8, 19  # ouvert de 08:00 inclus à 19:00 exclu


def is_open(now: datetime, event: str) -> bool:
    if event == "workflow_dispatch":
        return True
    return OPEN_HOUR <= now.astimezone(PARIS).hour < CLOSE_HOUR


if __name__ == "__main__":
    now = datetime.now(timezone.utc)
    event = os.environ.get("EVENT_NAME", "")
    ok = is_open(now, event)
    print(f"{now:%Y-%m-%d %H:%M} UTC = {now.astimezone(PARIS):%H:%M} Paris, event {event}: {'open' if ok else 'closed'}")
    sys.exit(0 if ok else 1)
