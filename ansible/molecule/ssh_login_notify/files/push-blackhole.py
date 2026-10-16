#!/usr/bin/env python3
"""Uptime Kuma qui ne répond jamais : accepte la connexion TCP (file
d'attente du listen) sans jamais lire ni répondre. curl attend donc jusqu'à
son --max-time ; le login, lui, ne doit pas attendre."""
import socket
import time

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 18081))
sock.listen(64)
while True:
    time.sleep(3600)
