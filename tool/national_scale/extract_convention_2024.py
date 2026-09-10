"""Extract the supplied ShowPro count PDFs; requires pdfplumber, runs offline.

No PDF code or document instructions are executed. All numeric levels must
reconcile before the fixture source is written. Original labels are preserved.
"""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path
import re

import pdfplumber


def columns(path, first_top):
    with pdfplumber.open(path) as document:
        for page_number, page in enumerate(document.pages, 1):
            for left, right in [(0, 306), (306, 612)]:
                top = first_top if page_number == 1 else 45
                for line in page.crop((left, top, right, 760)).extract_text_lines():
                    yield page_number, line['x0'] - left, line['text']


def extract(open_path, youth_path):
    breeds = {}
    for page, x, text in columns(open_path, 140):
        if text == str(page):  # Repeated page number below the breed table.
            continue
        match = re.fullmatch(r'([A-Z][A-Z ]+) (\d+)', text)
        if not match:
            raise ValueError(f'Unexpected Open line: {text}')
        name, count = match.groups()
        assert name not in breeds, name
        breeds[name] = dict(open=int(count), youth=0, youth_classes=[])

    breed = group = variety = ''
    group_totals, variety_totals = {}, {}
    seen_breeds = set()
    for page, x, text in columns(youth_path, 160):
        header = re.fullmatch(r'([A-Z][A-Z ]+) (\d+)', text)
        if header:
            breed, count = header.groups()
            assert breed in breeds and breed not in seen_breeds, breed
            seen_breeds.add(breed)
            breeds[breed]['youth'] = int(count)
            group = variety = ''
            continue
        line = re.fullmatch(r'(\d+)(?: (.*))?', text)
        if not line or not breed:
            raise ValueError(f'Unexpected Youth page {page} line: {text}')
        count, label = int(line[1]), line[2] or ''
        if re.fullmatch(r'(PREJUNIOR|JUNIOR|INTERMEDIATE|SENIOR) (BUCK|DOE)', label):
            breeds[breed]['youth_classes'].append([group, variety, label, count, page])
        elif label.startswith('GROUP '):
            group = label
            group_totals[breed, group] = count
        elif not label and x >= 120:
            assert count == breeds[breed]['youth'], breed
        else:
            variety = label
            key = breed, group, variety
            assert key not in variety_totals, key
            variety_totals[key] = count

    actual_groups, actual_varieties = defaultdict(int), defaultdict(int)
    for name, data in breeds.items():
        assert data['youth'] == sum(row[3] for row in data['youth_classes']), name
        for group, variety, _, count, _ in data['youth_classes']:
            actual_groups[name, group] += count
            actual_varieties[name, group, variety] += count
    assert dict(actual_varieties) == variety_totals, 'Youth variety totals differ'
    assert all(actual_groups[key] == count for key, count in group_totals.items())
    assert len(breeds) == 56 and seen_breeds == breeds.keys()
    assert sum(b['open'] for b in breeds.values()) == 18867
    assert sum(b['youth'] for b in breeds.values()) == 6844
    return dict(
        sources=[dict(file=p.name, sha256=hashlib.sha256(p.read_bytes()).hexdigest())
                 for p in [open_path, youth_path]],
        totals=dict(open=18867, youth=6844, entries=25711, exhibitors=2528),
        youth_class_columns=['group', 'variety', 'class', 'count', 'pdf_page'],
        breeds=breeds,
    )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('open_pdf', type=Path)
    parser.add_argument('youth_pdf', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = extract(args.open_pdf, args.youth_pdf)
    # Compact arrays keep the class-count rows practical to review.
    output = json.dumps(result, indent=2)
    output = re.sub(r'\[\n\s+("[^\n]*),\n\s+("[^\n]*),\n\s+("[^\n]*),\n\s+(\d+),\n\s+(\d+)\n\s+\]',
                    r'[\1, \2, \3, \4, \5]', output)
    args.output.write_text(output + '\n')
    print(json.dumps(dict(totals=result['totals'], categories=len(result['breeds']),
                          youth_classes=sum(len(b['youth_classes']) for b in result['breeds'].values()))))
