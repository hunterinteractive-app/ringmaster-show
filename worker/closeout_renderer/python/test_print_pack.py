import tempfile
import unittest
from pathlib import Path
from pypdf import PdfReader, PdfWriter
from pypdf.generic import DictionaryObject, DecodedStreamObject, NameObject, NumberObject
from print_pack import merge_pdfs, verify_sources, SourceChangedError


class PrintPackTests(unittest.TestCase):
    def test_omits_only_empty_leg_pages_and_their_bookmarks(self):
        with tempfile.TemporaryDirectory() as directory:
            sources = []
            for index, (report_name, texts) in enumerate([
                ('exhibitor_report', ['No leg certificates earned.']),
                ('legs', ['No leg certificates earned.']),
                ('legs', ['Actual leg certificate', 'No leg certificates earned.']),
            ]):
                writer = PdfWriter()
                for text in texts:
                    page = writer.add_blank_page(width=612, height=792)
                    font = DictionaryObject({NameObject('/Type'): NameObject('/Font'),
                        NameObject('/Subtype'): NameObject('/Type1'),
                        NameObject('/BaseFont'): NameObject('/Helvetica')})
                    page[NameObject('/Resources')] = DictionaryObject({
                        NameObject('/Font'): DictionaryObject({NameObject('/F1'): writer._add_object(font)})})
                    content = DecodedStreamObject()
                    content.set_data(f'BT /F1 12 Tf 20 20 Td ({text}) Tj ET'.encode())
                    page[NameObject('/Contents')] = writer._add_object(content)
                path = Path(directory) / f'{index}.pdf'
                writer.write(path)
                sources.append({'file': path, 'label': str(index), 'report_name': report_name})
            output = Path(directory) / 'combined.pdf'
            self.assertEqual(merge_pdfs(sources, output), 2)
            reader = PdfReader(output)
            self.assertEqual([p.extract_text() for p in reader.pages],
                             ['No leg certificates earned.', 'Actual leg certificate'])
            self.assertEqual([b.title for b in reader.outline], ['0', '2'])

    def test_repeated_artwork_with_different_resource_names_is_losslessly_shared(self):
        with tempfile.TemporaryDirectory() as directory:
            sources = []
            for index in range(2):
                writer = PdfWriter()
                page = writer.add_blank_page(width=612, height=792)
                mask = DecodedStreamObject()
                mask.set_data(b'\xff')
                mask.update({NameObject('/Type'): NameObject('/XObject'),
                             NameObject('/Subtype'): NameObject('/Image'),
                             NameObject('/Width'): NumberObject(1),
                             NameObject('/Height'): NumberObject(1),
                             NameObject('/BitsPerComponent'): NumberObject(8),
                             NameObject('/ColorSpace'): NameObject('/DeviceGray'),
                             NameObject('/Name'): NameObject(f'/Mask{index}')})
                image = DecodedStreamObject()
                image.set_data(b'\x10\x20\x30')
                image.update({**mask, NameObject('/ColorSpace'): NameObject('/DeviceRGB'),
                              NameObject('/Name'): NameObject(f'/Image{index}'),
                              NameObject('/SMask'): writer._add_object(mask)})
                page[NameObject('/Resources')] = DictionaryObject({
                    NameObject('/XObject'): DictionaryObject({NameObject(f'/Image{index}'): writer._add_object(image)})})
                path = Path(directory) / f'{index}.pdf'
                writer.write(path)
                sources.append({'file': path, 'label': str(index)})
            output = Path(directory) / 'combined.pdf'
            merge_pdfs(sources, output)
            reader = PdfReader(output)
            images = [next(iter(p['/Resources']['/XObject'].values())) for p in reader.pages]
            self.assertEqual(images[0].idnum, images[1].idnum)
            self.assertEqual(images[0].get_object().get_data(), b'\x10\x20\x30')
            self.assertEqual(images[0].get_object()['/SMask'].get_data(), b'\xff')

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
