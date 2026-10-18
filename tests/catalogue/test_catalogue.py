import copy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from tools.catalogue.build import build, changes, normalized
from tools.catalogue.core import ValidationError, decimal, read_json, file_digest
from tools.catalogue.validate import validate

ROOT=Path(__file__).resolve().parents[2]
FIX=ROOT/'data'/'fixtures'
REG=ROOT/'data'/'source-registry.json'

class CatalogueTests(unittest.TestCase):
    def setUp(self):
        self.pack=read_json(FIX/'fixture-v1.json')
        self.registry=read_json(REG)
    def reject(self, pack=None, registry=None, mode='development'):
        with self.assertRaises(ValidationError):
            validate(self.pack if pack is None else pack,self.registry if registry is None else registry,mode)
    def test_fixture_valid_and_multi_market_single_identity(self):
        result=validate(self.pack,self.registry)
        self.assertEqual(len(result['foods']),4)
        self.assertEqual(set(result['foods'][0]['salesCountries']),{'SE','DE'})
    def test_decimal_boundaries(self):
        for good in ('0','999999999999.999999999','0.000000001','1.0'):
            decimal(good)
        for bad in ('1000000000000','0.0000000001','01','1e2','-0','NaN','1,2',' 1','1.',1,True):
            with self.subTest(bad=bad),self.assertRaises(ValidationError): decimal(bad)
    def test_malformed_units(self):
        self.pack['foods'][0]['profile']['nutrients']['protein']['unit']='mg'
        self.reject()
    def test_invalid_basis(self):
        self.pack['foods'][0]['profile']['basis']['unit']='oz'
        self.reject()
    def test_unknown_is_not_zero(self):
        self.pack['foods'][0]['profile']['nutrients']['fibre']['value']='0'
        self.reject()
    def test_known_zero_and_trace_preserved(self):
        validate(self.pack,self.registry)
        self.assertEqual(self.pack['foods'][1]['profile']['nutrients']['fat.total']['status'],'knownZero')
        self.assertEqual(self.pack['foods'][3]['profile']['nutrients']['fibre']['upperBound'],'0.1')
    def test_known_cannot_be_zero(self):
        self.pack['foods'][0]['profile']['nutrients']['protein']['value']='0'
        self.reject()
    def test_duplicate_identity(self):
        other=copy.deepcopy(self.pack['foods'][0]);other['revision']='r2'
        self.pack['foods'].append(other);self.reject()
    def test_bad_country(self):
        self.pack['foods'][0]['salesCountries']=['ZZ'];self.reject()
    def test_source_gate_not_boolean_only(self):
        prov=self.pack['provenance']['synthetic-fixture'];prov['providerID']='bls'
        self.pack['foods'][0]['id']['namespace']='bls'
        row=next(r for r in self.registry['sources'] if r['source_id']=='bls')
        for key in ('raw_acquired','schema_verified','rights_reviewed','production_release_allowed'):row[key]=True
        self.reject()
    def test_synthetic_cannot_build_production(self): self.reject(mode='production')
    def test_unsupported_schema(self):
        self.pack['schemaVersion']=2;self.reject()
    def test_provenance_unresolved(self):
        self.pack['foods'][0]['profile']['provenanceRef']='missing';self.reject()
    def test_private_data_rejected_even_when_allowlisted(self):
        for key in ('logs','overlays','HealthSamples','outbox'):
            pack=copy.deepcopy(self.pack);pack[key]=[];self.reject(pack=pack)
    def test_personal_and_recipe_rejected(self):
        self.pack['foods'][0]['id']['scope']='personal';self.reject()
        self.pack['foods'][0]['id']['scope']='catalogue'
        self.pack['foods'][0]['kind']='recipe';self.reject()
    def test_explicit_retired_retained_diff(self):
        v2=read_json(FIX/'fixture-v2.json');validate(v2,self.registry)
        result=changes(normalized(self.pack),normalized(v2))
        self.assertEqual([v['recordID'] for v in result['retired']],['potato'])
        self.assertEqual([v['recordID'] for v in result['changed']],['potato','sausage'])
    def test_removed_is_not_silent_retirement(self):
        v2=copy.deepcopy(self.pack);v2['generationID']='00000000-0000-4000-8000-000000000002';v2['packVersion']='v2';v2['foods'].pop()
        with self.assertRaises(ValidationError):changes(self.pack,v2)
    def test_retired_requires_retained_revision(self):
        v2=read_json(FIX/'fixture-v2.json');v2['retainedRevisions']=[]
        with self.assertRaises(ValidationError):changes(self.pack,v2)
    def test_revision_cannot_change_in_place(self):
        v2=copy.deepcopy(self.pack);v2['generationID']='00000000-0000-4000-8000-000000000002';v2['packVersion']='v2';v2['foods'][0]['names']['en']='Changed'
        with self.assertRaises(ValidationError):changes(self.pack,v2)
    def test_source_only_exact_allowlist(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValidationError):
                build(FIX/'fixture-v1.json',REG,Path(tmp)/'pack', [REG])
            self.assertFalse((Path(tmp)/'pack').exists())
    def test_duplicate_json_key_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'input.json';p.write_text('{"schemaVersion":1,"schemaVersion":2}')
            with self.assertRaises(ValidationError):read_json(p)
    def test_deterministic_build_and_sqlite_semantics(self):
        with tempfile.TemporaryDirectory() as tmp:
            inp=FIX/'fixture-v1.json';reg=REG
            first=Path(tmp)/'first';second=Path(tmp)/'second'
            a=build(inp,reg,first,[inp,reg]);b=build(inp,reg,second,[inp,reg])
            self.assertEqual(a,b)
            for p in first.iterdir():self.assertEqual(file_digest(p),file_digest(second/p.name))
            with sqlite3.connect(first/'catalogue.sqlite') as db:
                self.assertEqual(db.execute('SELECT count(*) FROM food_revision WHERE current=1').fetchone()[0],4)
                self.assertEqual(db.execute("SELECT count(*) FROM markets WHERE record_id='sausage'").fetchone()[0],2)
                record=json.loads(db.execute("SELECT record_json FROM food_revision WHERE record_id='sausage'").fetchone()[0])
                self.assertEqual(record['profile']['nutrients']['fibre']['status'],'unknown')
            v2=FIX/'fixture-v2.json';out=Path(tmp)/'v2'
            build(v2,reg,out,[inp,v2,reg],previous_path=inp)
            with sqlite3.connect(out/'catalogue.sqlite') as db:
                self.assertEqual(db.execute("SELECT count(*) FROM food_revision WHERE record_id='potato'").fetchone()[0],2)
                self.assertEqual(db.execute("SELECT count(*) FROM food_revision WHERE record_id='sausage'").fetchone()[0],2)
                self.assertEqual(db.execute("SELECT count(*) FROM names WHERE record_id='potato'").fetchone()[0],0)


class StrictReviewTests(unittest.TestCase):
    setUp=CatalogueTests.setUp
    reject=CatalogueTests.reject
    def test_unknown_fields_rejected_at_each_public_layer(self):
        paths=[(),('foods',0),('foods',0,'id'),('foods',0,'profile'),
               ('foods',0,'profile','basis'),('foods',0,'profile','portions',0),
               ('foods',0,'profile','nutrients','protein'),
               ('provenance','synthetic-fixture'),('evidence','synthetic-measured')]
        for path in paths:
            with self.subTest(path=path):
                pack=copy.deepcopy(self.pack);obj=pack
                for key in path:obj=obj[key]
                obj['notes']='private payload';self.reject(pack=pack)
    def test_profile_provenance_must_be_food_provenance(self):
        self.pack['provenance']['other']=copy.deepcopy(self.pack['provenance']['synthetic-fixture'])
        self.pack['foods'][0]['profile']['provenanceRef']='other';self.reject()
    def test_evidence_resolution(self):
        for target in ('density','portion','derived'):
            with self.subTest(target=target):
                pack=copy.deepcopy(self.pack)
                if target=='density':pack['foods'][2]['profile']['density']['evidenceRef']='missing'
                elif target=='portion':pack['foods'][0]['profile']['portions'][0]['evidenceRef']='missing'
                else:pack['foods'][0]['profile']['nutrients']['protein']={'status':'derived','value':'10','unit':'g','methodID':'test','inputRefs':['missing'],'estimated':False}
                self.reject(pack=pack)
    def test_replaced_current_revision_must_be_retained(self):
        v2=read_json(FIX/'fixture-v2.json')
        v2['retainedRevisions']=[f for f in v2['retainedRevisions'] if f['id']['recordID']!='sausage']
        with self.assertRaises(ValidationError):changes(normalized(self.pack),normalized(v2))
    def test_previous_retained_revision_cannot_disappear(self):
        v2=read_json(FIX/'fixture-v2.json');v3=copy.deepcopy(v2)
        v3['generationID']='00000000-0000-4000-8000-000000000003';v3['packVersion']='v3'
        v3['retainedRevisions']=[]
        with self.assertRaises(ValidationError):changes(normalized(v2),normalized(v3))
    def test_valid_synthetic_derivation(self):
        self.pack['foods'][0]['profile']['nutrients']['protein']={'status':'derived','value':'10','unit':'g','methodID':'test','inputRefs':['synthetic-measured'],'estimated':False}
        validate(self.pack,self.registry)
    def test_nutrient_union_strict(self):
        cases=[('protein','estimated',False),('protein','inputRefs',[]),('fibre','upperBound','0.1')]
        for nutrient,key,val in cases:
            pack=copy.deepcopy(self.pack);pack['foods'][0]['profile']['nutrients'][nutrient][key]=val;self.reject(pack=pack)
        self.pack['foods'][3]['profile']['nutrients']['fibre']['reason']='extra';self.reject()
    def test_malformed_types_are_validation_errors(self):
        paths=[('foods',0),('foods',0,'profile'),('foods',0,'profile','basis'),
               ('foods',0,'profile','density'),('foods',0,'profile','portions'),
               ('foods',0,'profile','nutrients'),('foods',0,'profile','nutrients','protein'),
               ('provenance','synthetic-fixture'),('evidence','synthetic-measured'),
               ('foods',0,'kind'),('foods',0,'lifecycle'),('foods',0,'provenanceRef')]
        for path in paths:
            for val in ([],42,True):
                with self.subTest(path=path,val=val):
                    if path[-1]=='portions' and val==[]:continue
                    pack=copy.deepcopy(self.pack);obj=pack
                    for key in path[:-1]:obj=obj[key]
                    obj[path[-1]]=val;self.reject(pack=pack)
        self.reject(registry=[])
    def test_registry_boolean_version_rejected(self):
        self.registry['schema_version']=True;self.reject()
    def test_changed_pack_cannot_reuse_generation_or_version(self):
        for field in ('generationID','packVersion'):
            with self.subTest(field=field):
                v2=read_json(FIX/'fixture-v2.json');v2[field]=self.pack[field]
                with self.assertRaises(ValidationError):changes(normalized(self.pack),normalized(v2))
    def test_same_pack_repeat_is_allowed(self):
        self.assertEqual(changes(self.pack,self.pack),{'added':[],'changed':[],'retired':[]})
    def test_revision_provenance_and_evidence_immutable(self):
        for field in ('provenance','evidence'):
            with self.subTest(field=field):
                v2=read_json(FIX/'fixture-v2.json')
                if field=='provenance':v2[field]['synthetic-fixture']['transformationVersion']='changed'
                else:v2[field]['synthetic-measured']['description']='Changed'
                with self.assertRaises(ValidationError):changes(normalized(self.pack),normalized(v2))

if __name__=='__main__': unittest.main()
