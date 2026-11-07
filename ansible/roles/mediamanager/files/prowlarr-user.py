#!/usr/bin/env python3
# Crée ou change le compte de l'interface de Prowlarr par son API (clé lue dans le conteneur).
import getpass, json, subprocess, sys
C = "mediamanager-prowlarr"
A = "http://127.0.0.1:9696/api/v1/config/host"
key = subprocess.check_output(["docker", "exec", C, "printenv", "PROWLARR__AUTH__APIKEY"], text=True).strip()
def curl(*args, data=None):
    return subprocess.run(["docker", "exec", "-i", C, "curl", "-s", "-H", f"X-Api-Key: {key}", *args],
                          input=data, capture_output=True, text=True, check=True).stdout
cfg = json.loads(curl(A))
user = input("Identifiant : ").strip()
pw = getpass.getpass("Mot de passe : ")
if not user or len(pw) < 8 or pw != getpass.getpass("Encore : "):
    sys.exit("Identifiant vide, mot de passe trop court (8 min.) ou différent : rien n'est changé.")
cfg.update(username=user, password=pw, passwordConfirmation=pw)
out = curl("-o", "/dev/null", "-w", "%{http_code}", "-H", "Content-Type: application/json",
           "-X", "PUT", "--data-binary", "@-", f"{A}/{cfg['id']}", data=json.dumps(cfg))
print("OK, connecte-toi sur https://prowlarr.sylvain.cloud" if out.startswith("2") else f"Échec HTTP {out}")
