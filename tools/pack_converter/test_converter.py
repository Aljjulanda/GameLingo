import argparse
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import struct
import tempfile
import unittest
import zipfile

spec=importlib.util.spec_from_file_location('converter',Path(__file__).with_name('convert.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)

class ConverterTests(unittest.TestCase):
    def setUp(self):self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def arguments(self,english='0x1 = Talk\n',arabic='0x1 = تحدث\n'):
        (self.root/'en.txt').write_text(english,encoding='utf-8');(self.root/'ar.txt').write_text(arabic,encoding='utf-8')
        return argparse.Namespace(english=str(self.root/'en.txt'),arabic=str(self.root/'ar.txt'),output=str(self.root/'sample.glpack'),report=str(self.root/'report.json'),game_id='fixture',title='Synthetic fixture',pack_version='1',attribution='Original synthetic tests',permission='Synthetic test strings only',timestamp='2026-11-14T00:00:00Z',english_revision='fixture',english_encoding='utf-8-sig',arabic_order='auto')
    def test_text_identifiers(self):
        self.assertEqual(c.identifier('0x55c67c82'),'0x55C67C82')
        self.assertEqual(c.identifier('1049_INTRO_1'),c.identifier('1049_intro_1'))
        self.assertRaises(ValueError,c.identifier,'../outside')
    def test_utf8_and_explicit_legacy_policy(self):
        p=self.root/'en.txt';p.write_bytes(b'0x1 = It\x92s fine\r\n')
        self.assertRaises(UnicodeDecodeError,c.parse_file,p)
        self.assertEqual(c.parse_file(p,'utf-8-or-cp1252')[0][0][1],'It’s fine')
    def test_binary_gxt2_bounds(self):
        p=self.root/'x.gxt2';p.write_bytes(struct.pack('<6I',0x47585432,1,1,24,0x47585432,29)+b'Talk\0')
        self.assertEqual(c.parse_file(p)[0],[('0x00000001','Talk')])
        p.write_bytes(struct.pack('<6I',0x47585432,1,1,200,0x47585432,29)+b'Talk\0')
        self.assertRaises(ValueError,c.parse_file,p)
    def test_bad_text_record_reported(self):
        p=self.root/'bad.txt';p.write_text('bad content\n0x1 = Talk\n',encoding='utf-8')
        self.assertEqual(c.parse_file(p)[1],[1])
    def test_logical_arabic_not_reversed(self):
        self.assertEqual(c.prepare('اذهب إلى John واجمع 11 قطعة.',True)[0],'اذهب إلى John واجمع 11 قطعة.')
    def test_visual_presentation_and_lam_alef(self):
        self.assertEqual(c.prepare('ﺙﺪﺤﺗ',True,'presentation-visual')[0],'تحدث')
        self.assertEqual(c.prepare('ﻻ',True,'presentation-visual')[0],'لا')
        self.assertFalse(c.prepare('ﺙﺪﺤﺗ',True,'auto')[2])
    def test_visual_ltr_islands_and_numbers(self):
        self.assertEqual(c.visual_line('John 11 ﺎﺒﺣﺮﻣ'),'مرحبا John 11')
        self.assertEqual(c.visual_line('(ﺎﺒﺣﺮﻣ)'),'('+'مرحبا'+')')
    def test_game_markers_and_placeholders(self):
        value,flags,usable=c.prepare('~z~Hello~n~there~sl:0.0:2.0~friend.')
        self.assertTrue(usable);self.assertEqual(value,'Hello\nthere\nfriend.')
        for value in ['Press ~INPUT_JUMP~','Collect %d items','Hi {name}','Hello ~unknown~']:
            out,flags,ok=c.prepare(value);self.assertFalse(ok);self.assertIn('unresolved_markup_or_placeholder',flags)
            self.assertTrue(any(t in out for t in ['~INPUT_JUMP~','%d','{name}','~unknown~']))
    def test_semantic_normalization(self):
        self.assertEqual(c.normalize('  We’re\nready! '),c.normalize("We're ready."))
        for a,b in [('Go left','Go right'),('Go','Do not go'),('Collect 10','Collect 11'),('He is here','She is here'),('Open door','Close door'),('Follow Arthur','Follow John'),('Get -10','Get 10')]:self.assertNotEqual(c.normalize(a),c.normalize(b))
    def test_reproducible_pack_and_indexes(self):
        args=self.arguments();report=c.build(args);before=Path(args.output).read_bytes();c.build(args)
        self.assertEqual(before,Path(args.output).read_bytes());self.assertEqual(report['package_records'],1)
        with zipfile.ZipFile(args.output) as z:
            self.assertEqual(set(z.namelist()),{'manifest.json','translations.sqlite','checksums.json'})
            self.assertEqual(z.testzip(),None)
            hashes=json.loads(z.read('checksums.json'));self.assertEqual(hashes['translations.sqlite'],c.digest(z.read('translations.sqlite')))
            db=self.root/'db';db.write_bytes(z.read('translations.sqlite'))
        with closing(sqlite3.connect(db)) as connection:
            self.assertEqual(connection.execute('PRAGMA integrity_check').fetchone()[0],'ok')
            self.assertEqual(connection.execute('SELECT target FROM entries WHERE identifier=?',('0x00000001',)).fetchone()[0],'تحدث')
            plan=connection.execute('EXPLAIN QUERY PLAN SELECT target FROM entries WHERE normalized=?',('talk',)).fetchone()[-1]
            self.assertIn('by_normalized',plan)
    def test_conflicting_english_id_is_not_arbitrarily_joined(self):
        args=self.arguments('0x1 = Talk\n0x1 = Run\n0x2 = Stop\n','0x1 = تحدث\n0x2 = توقف\n')
        result=c.build(args);self.assertEqual(result['english_conflicting_ids'],1);self.assertEqual(result['package_records'],1)
    def test_duplicate_ids_and_ambiguous_source_preserved(self):
        args=self.arguments('0x1 = Move\n0x2 = Move\n','0x1 = انطلق\n0x2 = تحرك\n0x2 = اذهب\n')
        result=c.build(args);self.assertEqual(result['arabic_duplicate_id_records'],1);self.assertEqual(result['arabic_conflicting_ids'],1);self.assertEqual(result['ambiguous_normalized_sources'],1)
    def test_coverage_not_invented(self):
        result=c.build(self.arguments('0x1 = Talk\n0x2 = Stop\n','0x1 = تحدث\n0x3 = تحرك\n'))
        self.assertEqual((result['matched_identifiers'],result['unmatched_arabic_identifiers'],result['unmatched_english_identifiers']),(1,1,1))
    def test_non_arabic_and_empty_records_are_unusable(self):
        result=c.build(self.arguments('0x1 = Talk\n0x2 = Stop\n','0x1 = Talk\n0x2 = \n'))
        self.assertEqual(result['usable_records'],0)

if __name__=='__main__':unittest.main()
