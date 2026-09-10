import tempfile
import unittest
from pathlib import Path
from pypdf import PdfReader, PdfWriter
from print_pack import merge_pdfs, verify_sources, SourceChangedError


class PrintPackTests(unittest.TestCase):
    def test_merge_preserves_page_order_sizes_and_bookmarks(self):
        with tempfile.TemporaryDirectory() as directory:
            sources = []
            for index, sizes in enumerate([[(612, 792), (792, 612)], [(612, 792)]]):
                path = Path(directory) / f'{index}.pdf'
                writer = PdfWriter()
                for width, height in sizes:
                    writer.add_blank_page(width=width, height=height)
                writer.write(path)
                sources.append({'file': path, 'label': ['Adams - Report', 'Adams - Legs'][index]})
            output = Path(directory) / 'combined.pdf'
            self.assertEqual(merge_pdfs(sources, output), 3)
            reader = PdfReader(output)
            self.assertEqual([tuple(p.mediabox[2:]) for p in reader.pages],
                             [(612, 792), (792, 612), (612, 792)])
            self.assertEqual([b.title for b in reader.outline], ['Adams - Report', 'Adams - Legs'])
            self.assertEqual(reader.metadata.author, 'RingMaster Show')

    def test_source_changes_reject_incomplete_or_stale_pack(self):
        source = {'id': 'a', 'generation': 2, 'storage_bucket': 'show-files', 'storage_path': 'a.pdf'}
        current = {**source, 'artifact_status': 'generated'}
        verify_sources([source], [current])
        for rows in ([], [current, {**current, 'id': 'b'}],
                     [{**current, 'artifact_status': 'queued'}],
                     [{**current, 'generation': 3}],
                     [{**current, 'storage_path': 'replacement.pdf'}]):
            with self.subTest(rows=rows), self.assertRaises(SourceChangedError):
                verify_sources([source], rows)


if __name__ == '__main__':
    unittest.main()
