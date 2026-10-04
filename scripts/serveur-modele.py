#!/usr/bin/env python3
# Sert un faux modèle en local, pour tester son téléchargement par Murmure.app
# ou install.sh (MURMURE_MODEL_URL) sans tirer 550 Mo : reprise (Range),
# débit limité, coupure simulée. python3 -m http.server ignore Range.
#
#   scripts/serveur-modele.py <fichier> [--port 8770] [--debit 2000000] [--couper 3000000]
#
# /modele.bin sert le fichier ; /redirection y renvoie par un 302, comme
# Hugging Face vers son CDN. --debit limite en octets par seconde ; --couper
# ferme la première connexion après ce nombre d'octets envoyés. Chaque
# requête est journalisée avec sa plage et les octets envoyés.
import argparse
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

opts = argparse.ArgumentParser()
opts.add_argument("fichier")
opts.add_argument("--port", type=int, default=8770)
opts.add_argument("--debit", type=int, default=0)
opts.add_argument("--couper", type=int, default=0)
args = opts.parse_args()
taille = os.path.getsize(args.fichier)
coupure = {"restante": args.couper > 0}


class Serveur(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        sys.stderr.write("[%s] %s\n" % (time.strftime("%H:%M:%S"), fmt % a))

    def do_HEAD(self):
        self.repondre(corps=False)

    def do_GET(self):
        self.repondre(corps=True)

    def repondre(self, corps):
        if self.path == "/redirection":
            self.send_response(302)
            self.send_header("Location", "/modele.bin")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path != "/modele.bin":
            self.send_error(404)
            return
        plage = self.headers.get("Range")
        debut, fin = 0, taille - 1
        m = re.fullmatch(r"bytes=(\d+)-(\d*)", plage or "")
        if m:
            debut = int(m.group(1))
            if m.group(2):
                fin = min(int(m.group(2)), taille - 1)
            if debut >= taille:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % taille)
                self.send_header("Content-Length", "0")
                self.end_headers()
                self.log_message("Range %s : 416", plage)
                return
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (debut, fin, taille))
        else:
            self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(fin - debut + 1))
        self.end_headers()
        if not corps:
            return
        limite = None
        if coupure["restante"]:
            coupure["restante"] = False
            limite = args.couper
        envoyes = 0
        with open(args.fichier, "rb") as f:
            f.seek(debut)
            reste = fin - debut + 1
            while reste > 0:
                bloc = f.read(min(65536, reste))
                if limite is not None and envoyes + len(bloc) > limite:
                    bloc = bloc[: limite - envoyes]
                try:
                    self.wfile.write(bloc)
                except (BrokenPipeError, ConnectionResetError):
                    break
                envoyes += len(bloc)
                reste -= len(bloc)
                if limite is not None and envoyes >= limite:
                    self.log_message("Range %s : coupure simulée après %d octets", plage, envoyes)
                    self.close_connection = True
                    self.connection.shutdown(2)
                    return
                if args.debit:
                    time.sleep(len(bloc) / args.debit)
        self.log_message("Range %s : %d octets envoyés", plage, envoyes)


ThreadingHTTPServer(("127.0.0.1", args.port), Serveur).serve_forever()
