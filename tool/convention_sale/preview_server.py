#!/usr/bin/env python3
"""Serve the local Flutter QA build and an in-memory settings fixture. No payments."""
import argparse
import json
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser()
parser.add_argument('directory')
args = parser.parse_args()
settings = dict(enabled=True, title='Convention token bonus', venue='Reno–Sparks Convention Center',
                address='4590 S Virginia St, Reno, NV 89502', latitude=39.4861, longitude=-119.7911,
                radius_miles=1.0, time_zone='America/Los_Angeles', starts_local='2026-10-26T00:00',
                ends_local='2026-10-27T00:00', single_bonus=1, four_bonus=2, unlimited_bonus_months=2, revision=1)

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=args.directory, **kw)

    def reply(self, value, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())

    def do_OPTIONS(self):
        self.reply({})

    def do_POST(self):
        if self.path == '/rest/v1/rpc/convention_sale_visitors':
            self.rfile.read(int(self.headers.get('Content-Length', 0)))
            return self.reply([
                dict(id='example-reno', email='sample-buyer@example.invalid', plan='four_shows',
                     venue=settings['venue'], checked_at='2026-10-26T17:30:00Z', eligible=True,
                     city='Reno', state='NV', locality_status='resolved', purchased=True),
                dict(id='example-sparks', email='sample-visitor@example.invalid', plan='single_show',
                     venue=settings['venue'], checked_at='2026-10-26T17:00:00Z', eligible=False,
                     city='Sparks', state='NV', locality_status='resolved', purchased=False),
                dict(id='example-unavailable', email='sample-lookup@example.invalid', plan='unlimited',
                     venue=settings['venue'], checked_at='2026-10-26T16:30:00Z', eligible=True,
                     city=None, state=None, locality_status='unavailable', purchased=False),
            ])
        if self.path == '/functions/v1/convention-sale-checkout':
            return self.reply({'products': [
                {'plan': 'single_show', 'amount': 5000, 'currency': 'usd', 'tax_inclusive': True},
                {'plan': 'four_shows', 'amount': 15000, 'currency': 'usd', 'tax_inclusive': True},
                {'plan': 'unlimited', 'amount': 25000, 'currency': 'usd', 'tax_inclusive': True},
            ]})
        if self.path not in ['/rest/v1/rpc/convention_sale_admin', '/rest/v1/rpc/convention_sale_settings']:
            return self.reply({'message': 'Not available in the local preview.'}, 404)
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or '{}') or {}
        if body.get('p_settings'):
            settings.update(body['p_settings'])
            settings['revision'] += 1
        zone = ZoneInfo(settings['time_zone'])
        start = datetime.fromisoformat(settings['starts_local']).replace(tzinfo=zone)
        end = datetime.fromisoformat(settings['ends_local']).replace(tzinfo=zone)
        now = datetime.now(timezone.utc)
        self.reply({**settings, 'starts_at': start.isoformat(), 'ends_at': end.isoformat(),
                    'active': settings['enabled'] and start <= now < end, 'server_now': now.isoformat()})

print('Local preview: http://127.0.0.1:58620', flush=True)
ThreadingHTTPServer(('127.0.0.1', 58620), Handler).serve_forever()
