"""Merge a restricted print-pack job without changing its source PDFs."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from pypdf import PdfReader, PdfWriter
from pypdf.generic import DictionaryObject


class SourceChangedError(Exception):
    pass


def merge_pdfs(sources, destination):
    writer = PdfWriter()
    expected_pages = 0
    for source in sources:
        with open(source['file'], 'rb') as stream:
            reader = PdfReader(stream)
            if reader.is_encrypted or not reader.pages:
                raise ValueError('Source PDF is encrypted or empty')
            pages = [index for index, page in enumerate(reader.pages)
                     if not (source.get('report_name') == 'legs'
                             and ' '.join((page.extract_text() or '').split()).casefold().rstrip('.')
                             == 'no leg certificates earned')]
            if not pages:
                continue
            expected_pages += len(pages)
            writer.append(reader, pages=pages, outline_item=source['label'], import_outline=False)
    if not expected_pages:
        raise ValueError('No printable report pages remain')
    writer.add_metadata({
        '/Title': 'Exhibitor Reports & Legs Print Pack',
        '/Author': 'RingMaster Show',
        '/Subject': 'Exhibitor reports and leg certificates in exhibitor order',
        '/Creator': 'RingMaster Show',
    })
    compact_shared_artwork(writer)
    writer.write(destination)
    writer.close()
    with open(destination, 'rb') as stream:
        if len(PdfReader(stream).pages) != expected_pages:
            raise ValueError('Merged PDF page count does not match source PDFs')
    return expected_pages


def compact_shared_artwork(writer):
    # Resource dictionary keys identify images in page content. The optional,
    # obsolete /Name inside the image itself is not used for that lookup, but
    # Dart's generated per-document names prevent identical-image detection.
    visited = set()

    def visit(value):
        obj = value.get_object()
        if not isinstance(obj, DictionaryObject) or id(obj) in visited:
            return
        visited.add(id(obj))
        if obj.get('/Subtype') == '/Image':
            obj.pop('/Name', None)
            if '/SMask' in obj:
                visit(obj['/SMask'])
        resources = obj.get('/Resources', {})
        if hasattr(resources, 'get_object'):
            resources = resources.get_object()
        if '/XObject' in resources:
            for image in resources['/XObject'].get_object().values():
                visit(image)

    for page in writer.pages:
        visit(page)
    # First combine masks; then images which reference those masks. The final
    # pass can combine their resource dictionaries. All stream bytes stay intact.
    for _ in range(3):
        writer.compress_identical_objects(remove_duplicates=True, remove_unreferenced=True)


class Api:
    def __init__(self):
        self.url = os.environ['SUPABASE_URL'].rstrip('/')
        self.key = os.environ['SUPABASE_SERVICE_ROLE_KEY']

    def request(self, path, method='GET', data=None, binary=False, headers=None):
        req_headers = {'apikey': self.key, 'Authorization': f'Bearer {self.key}'}
        if data is not None and not isinstance(data, bytes):
            data = json.dumps(data).encode()
            req_headers['Content-Type'] = 'application/json'
        req_headers.update(headers or {})
        request = urllib.request.Request(self.url + path, data=data,
                                         method=method, headers=req_headers)
        with urllib.request.urlopen(request, timeout=120) as response:
            result = response.read()
        return result if binary else (json.loads(result) if result else None)

    def current_sources(self, show_id):
        rows = []
        offset = 0
        while True:
            page = self.request('/rest/v1/show_report_artifacts?' + urllib.parse.urlencode({
                'show_id': f'eq.{show_id}', 'is_current': 'eq.true',
                'report_name': 'in.(exhibitor_report,legs)',
                'select': 'id,generation,storage_bucket,storage_path,artifact_status',
                'order': 'id', 'limit': 500, 'offset': offset,
            }))
            rows.extend(page)
            if len(page) < 500:
                return rows
            offset += len(page)


def verify_sources(manifest, current):
    by_id = {row['id']: row for row in current}
    if len(manifest) != len(by_id) or not manifest:
        raise SourceChangedError()
    for source in manifest:
        row = by_id.get(source['id'])
        if row is None or row['artifact_status'] != 'generated' or any(
            source[key] != row[key]
            for key in ('generation', 'storage_bucket', 'storage_path')
        ):
            raise SourceChangedError()


def run_once(api):
    jobs = api.request('/rest/v1/rpc/claim_exhibitor_print_pack', 'POST', {})
    if not jobs:
        return
    job = jobs[0]
    job_filter = '/rest/v1/exhibitor_print_packs?' + urllib.parse.urlencode({
        'id': 'eq.' + job['id'], 'claim_token': 'eq.' + job['claim_token'],
        'artifact_status': 'eq.running', 'is_current': 'eq.true',
    })
    try:
        account = api.request('/rest/v1/exhibitor_print_pack_accounts?' + urllib.parse.urlencode({
            'user_id': 'eq.' + job['requested_by'], 'select': 'user_id',
        }))
        if not account:
            raise PermissionError('Print pack access was revoked')
        verify_sources(job['sources'], api.current_sources(job['show_id']))
        with tempfile.TemporaryDirectory(prefix='print-pack-') as directory:
            def download_source(item):
                index, source = item
                path = '/storage/v1/object/authenticated/' + urllib.parse.quote(
                    source['storage_bucket'] + '/' + source['storage_path'], safe='/')
                content = api.request(path, binary=True)
                if source.get('sha256') and hashlib.sha256(content).hexdigest() != source['sha256']:
                    raise SourceChangedError()
                local = Path(directory) / f'{index}.pdf'
                local.write_bytes(content)
                return {'file': local, 'label': source['label'], 'report_name': source['report_name']}
            # Bounded downloads avoid hundreds of sequential TLS round trips;
            # map preserves the manifest's exhibitor/report order.
            with ThreadPoolExecutor(max_workers=4) as executor:
                local_sources = list(executor.map(download_source, enumerate(job['sources'])))
            output = Path(directory) / 'report.pdf'
            page_count = merge_pdfs(local_sources, output)
            verify_sources(job['sources'], api.current_sources(job['show_id']))
            content = output.read_bytes()
            api.request('/storage/v1/object/' + urllib.parse.quote(
                job['storage_bucket'] + '/' + job['storage_path'], safe='/'),
                'POST', content, headers={'Content-Type': 'application/pdf', 'x-upsert': 'true'})
            from datetime import datetime, timezone
            api.request(job_filter, 'PATCH', {
                'artifact_status': 'generated', 'page_count': page_count,
                'file_size_bytes': len(content),
                'generated_at': datetime.now(timezone.utc).isoformat(),
                'error_message': None,
            })
            print(json.dumps({'event': 'print_pack_generated', 'id': job['id'],
                              'pages': page_count, 'bytes': len(content)}))
    except Exception as error:
        message = ('Source reports changed. Finish Step 5 and generate the print pack again.'
                   if isinstance(error, SourceChangedError)
                   else 'Unable to generate the print pack. Please try again.')
        api.request(job_filter, 'PATCH', {'artifact_status': 'failed', 'error_message': message})
        # Do not log report content, source labels, credentials, or signed URLs.
        print(json.dumps({'event': 'print_pack_failed', 'id': job['id'],
                          'error_type': type(error).__name__}))


if __name__ == '__main__':
    run_once(Api())
