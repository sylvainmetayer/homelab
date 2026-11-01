// Crée une note Enclosed avec le contenu de l'entrée standard et n'écrit que
// son lien public (https://<domaine>/<id>#dar:<clé>) sur la sortie standard.
//
// Lancé par /usr/local/bin/enclosed-share dans un conteneur jetable du seul
// réseau interne enclosed-cli : le clair ne quitte jamais ce conteneur, la
// bibliothèque officielle (@enclosed/lib, même version que le serveur) le
// chiffre avant l'envoi, et la clé ne figure que dans le fragment du lien.
// Rien d'autre n'est écrit : ni le contenu, ni la clé dans un message d'erreur.
import process from 'node:process';
import { createNote } from '@enclosed/lib';

function fail(message) {
  process.stderr.write(`enclosed-share : ${message}\n`);
  process.exit(1);
}

const apiBaseUrl = process.env.ENCLOSED_API_URL;
const clientBaseUrl = process.env.ENCLOSED_PUBLIC_URL;
const ttlInSeconds = Number(process.env.ENCLOSED_TTL_SECONDS);
const deleteAfterReading = process.env.ENCLOSED_DELETE_AFTER_READING === 'true';

// Sans ces deux URL, la bibliothèque viserait https://enclosed.cc : refusé.
if (!apiBaseUrl || !clientBaseUrl) {
  fail('ENCLOSED_API_URL et ENCLOSED_PUBLIC_URL sont obligatoires');
}

const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(chunk);
}
// Un seul saut de ligne final retiré : celui d'un `echo` ou d'un here-string.
const content = Buffer.concat(chunks).toString('utf8').replace(/\r?\n$/, '');

if (content.length === 0) {
  fail('entrée standard vide, aucune note créée');
}

try {
  const { noteUrl } = await createNote({
    content,
    ttlInSeconds,
    deleteAfterReading,
    apiBaseUrl,
    clientBaseUrl,
  });
  process.stdout.write(`${noteUrl}\n`);
}
catch (error) {
  // Le statut HTTP seulement : le corps d'erreur et la pile n'ont rien à dire
  // d'utile ici, et rien de la note ne doit sortir.
  const status = error?.response?.status;
  fail(status ? `création refusée par le serveur (HTTP ${status})` : `création impossible (${error?.code ?? error?.name ?? 'erreur'})`);
}
