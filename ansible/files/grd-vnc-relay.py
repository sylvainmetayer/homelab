#!/usr/bin/python3
"""Relais VNC local devant GNOME Remote Desktop (ansible/pc-support.yml).

grd n'offre que le type de sécurité 18 (TLS anonyme, historique, RFC 6143),
que le client VNC du navigateur servi par Pangolin ne sait pas négocier. Le
relais écoute sur la boucle locale, ouvre lui-même ce tunnel TLS vers grd,
puis passe tout le reste tel quel : le client voit l'authentification VNC
classique (type 2) que grd propose dans le tunnel, mot de passe compris.

Le segment en clair ne quitte pas la boucle locale (Newt vise 127.0.0.1) ; le
tunnel TLS anonyme de grd ne protégeait de toute façon que contre l'écoute
passive, pas contre un intermédiaire.
"""
import asyncio
import ssl
import sys

LISTEN = ("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 5901)
UPSTREAM = ("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 5900)
RFB_38 = b"RFB 003.008\n"
SEC_TLS = 18

# TLS anonyme (ADH/AECDH) imposé par grd : pas de certificat, rien à vérifier,
# sur la boucle locale seulement (NOSONAR : le seul TLS que grd accepte).
TLS = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
TLS.check_hostname = False  # NOSONAR
TLS.verify_mode = ssl.CERT_NONE  # NOSONAR
TLS.maximum_version = ssl.TLSVersion.TLSv1_2
TLS.set_ciphers("aNULL:@SECLEVEL=0")  # NOSONAR


async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, ssl.SSLError):
        pass
    finally:
        writer.close()


async def open_upstream():
    """Poignée de main RFB 3.8 jusqu'au TLS ; renvoie le flux chiffré."""
    reader, writer = await asyncio.open_connection(*UPSTREAM)
    if await reader.readexactly(12) != RFB_38:
        raise ConnectionError("grd ne parle pas RFB 3.8")
    writer.write(RFB_38)
    count = (await reader.readexactly(1))[0]
    types = await reader.readexactly(count) if count else b""
    if SEC_TLS not in types:
        raise ConnectionError(f"grd n'offre pas le type 18 : {list(types)}")
    writer.write(bytes([SEC_TLS]))
    await writer.drain()
    await writer.start_tls(TLS)
    return reader, writer


async def handle(client_reader, client_writer):
    upstream_writer = None
    try:
        upstream_reader, upstream_writer = await asyncio.wait_for(open_upstream(), 10)
        client_writer.write(RFB_38)
        await client_writer.drain()
        # La suite du tunnel suppose un client en 3.8 (types de sécurité en liste).
        if await asyncio.wait_for(client_reader.readexactly(12), 10) != RFB_38:
            raise ConnectionError("client autre que RFB 3.8")
    except (OSError, EOFError) as err:
        print(f"connexion refusée : {err!r}", file=sys.stderr, flush=True)
        client_writer.close()
        if upstream_writer:
            upstream_writer.close()
        return
    await asyncio.gather(pipe(client_reader, upstream_writer), pipe(upstream_reader, client_writer))


async def main():
    server = await asyncio.start_server(handle, *LISTEN)
    print(f"relais {LISTEN[0]}:{LISTEN[1]} -> grd {UPSTREAM[0]}:{UPSTREAM[1]}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
