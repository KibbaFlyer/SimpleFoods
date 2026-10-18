import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
from .core import canonical, digest, file_digest, read_json, allowed_input, require
from .validate import validate, identity
from .policy import registry_sources

TOOL_VERSION='catalogue-scaffold-1'

def normalized(pack):
    # Preserve validated source fields; canonicalize decimal spelling and set ordering.
    result=json.loads(canonical(pack))
    def number(value):
        return value.rstrip('0').rstrip('.') if '.' in value else value
    def decimal_field(obj,key):
        if obj.get(key) is not None: obj[key]=number(obj[key])
    for collection in ('foods','retainedRevisions'):
        for food in result[collection]:
            for field in ('salesCountries','manufacturingCountries','ingredientOrigins','barcodes'):
                food[field]=sorted(food[field])
        for food in result[collection]:
            profile=food['profile'];decimal_field(profile['basis'],'quantity')
            if profile['density']:decimal_field(profile['density'],'gramsPerMillilitre')
            for portion in profile['portions']:
                decimal_field(portion,'massGrams');decimal_field(portion,'volumeMillilitres')
            for nutrient in profile['nutrients'].values():
                decimal_field(nutrient,'value');decimal_field(nutrient,'upperBound')
        result[collection].sort(key=lambda f:(*identity(f),f['revision']))
    return result

def changes(previous, current):
    before={identity(f):f for f in previous['foods']} if previous else {}
    after={identity(f):f for f in current['foods']}
    if previous and canonical(previous) != canonical(current):
        require(previous['generationID'] != current['generationID'], 'changed pack must have new generation ID')
        require(previous['packVersion'] != current['packVersion'], 'changed pack must have new pack version')
    missing=set(before)-set(after)
    require(not missing,'removed identity requires explicit retired record')
    all_before={(*identity(f),f['revision']):f for f in (previous['foods']+previous['retainedRevisions'])} if previous else {}
    all_after={(*identity(f),f['revision']):f for f in current['foods']+current['retainedRevisions']}
    require(all_before.keys() <= all_after.keys(), 'previous immutable revisions must be retained; safe GC is unsupported')
    for key in all_before.keys() & all_after.keys():
        require(canonical(all_before[key])==canonical(all_after[key]),'immutable revision changed')
        old_food, new_food = all_before[key], all_after[key]
        refs={old_food['provenanceRef'],old_food['profile']['provenanceRef']}
        for ref in refs:
            require(canonical(previous['provenance'][ref]) == canonical(current['provenance'].get(ref)), 'immutable revision provenance changed')
        # Evidence referenced by a retained immutable record is immutable too.
        profile=old_food['profile']; evidence_refs=[]
        if profile['density']: evidence_refs.append(profile['density']['evidenceRef'])
        evidence_refs.extend(p['evidenceRef'] for p in profile['portions'])
        for nutrient in profile['nutrients'].values(): evidence_refs.extend(nutrient.get('inputRefs',[]))
        for ref in evidence_refs:
            require(canonical(previous.get('evidence',{}).get(ref)) == canonical(current.get('evidence',{}).get(ref)), 'immutable revision evidence changed')
            evidence_prov=previous['evidence'][ref]['provenanceRef']
            require(canonical(previous['provenance'][evidence_prov]) == canonical(current['provenance'].get(evidence_prov)), 'immutable evidence provenance changed')
    added=[]; changed=[]; retired=[]
    for fid, food in sorted(after.items()):
        tagged=food['id']
        if fid not in before:
            added.append(tagged)
        elif canonical(before[fid]) != canonical(food):
            changed.append(tagged)
            if before[fid]['lifecycle']!='retired' and food['lifecycle']=='retired':
                retired.append(tagged)
                prior=(*fid,before[fid]['revision'])
                require(prior in all_after,'retirement must retain previous revision')
    return {'added':added,'changed':changed,'retired':retired}

def build(input_path, registry_path, output_dir, allowlisted_inputs, mode='development',
          previous_path=None, evidence_allowlist=()):
    source=allowed_input(input_path,allowlisted_inputs)
    reg=allowed_input(registry_path,allowlisted_inputs)
    registry=read_json(reg)
    pack=normalized(validate(read_json(source),registry,mode,evidence_allowlist))
    previous=None
    if previous_path:
        previous=normalized(validate(read_json(allowed_input(previous_path,allowlisted_inputs)),registry,mode,evidence_allowlist))
        require(previous['packID']==pack['packID'],'diff requires same pack identity')
    delta=changes(previous,pack)
    target=Path(output_dir)
    require(not target.exists(),'output already exists; choose new generation directory')
    target.parent.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix='.catalogue-stage-',dir=target.parent))
    try:
        db=sqlite3.connect(stage/'catalogue.sqlite')
        try:
            db.executescript('''PRAGMA page_size=4096; PRAGMA journal_mode=DELETE;
                PRAGMA user_version=1;
                CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
                CREATE TABLE food_revision(namespace TEXT NOT NULL, record_id TEXT NOT NULL,
                  revision TEXT NOT NULL, lifecycle TEXT NOT NULL, current INTEGER NOT NULL CHECK(current IN (0,1)),
                  record_json TEXT NOT NULL, record_sha256 TEXT NOT NULL,
                  PRIMARY KEY(namespace,record_id,revision)) WITHOUT ROWID;
                CREATE UNIQUE INDEX current_identity ON food_revision(namespace,record_id) WHERE current=1;
                CREATE TABLE names(namespace TEXT NOT NULL, record_id TEXT NOT NULL, locale TEXT NOT NULL,
                  name TEXT NOT NULL, PRIMARY KEY(namespace,record_id,locale)) WITHOUT ROWID;
                CREATE INDEX names_lookup ON names(locale,name);
                CREATE TABLE markets(namespace TEXT NOT NULL, record_id TEXT NOT NULL, country TEXT NOT NULL,
                  PRIMARY KEY(namespace,record_id,country)) WITHOUT ROWID;
                CREATE INDEX market_lookup ON markets(country,namespace,record_id);
                CREATE TABLE barcodes(barcode TEXT NOT NULL, namespace TEXT NOT NULL, record_id TEXT NOT NULL,
                  PRIMARY KEY(barcode,namespace,record_id)) WITHOUT ROWID;
                CREATE TABLE provenance(reference TEXT PRIMARY KEY, record_json TEXT NOT NULL) WITHOUT ROWID;
                CREATE TABLE evidence(reference TEXT PRIMARY KEY, record_json TEXT NOT NULL) WITHOUT ROWID;
            ''')
            for key in ('schemaVersion','generationID','packID','packVersion','calculationVersion','fixtureOnly'):
                db.execute('INSERT INTO metadata VALUES (?,?)',(key,canonical(pack[key])))
            for ref, value in sorted(pack['provenance'].items()):
                db.execute('INSERT INTO provenance VALUES (?,?)',(ref,canonical(value)))
            for ref, value in sorted(pack.get('evidence',{}).items()):
                db.execute('INSERT INTO evidence VALUES (?,?)',(ref,canonical(value)))
            for field,current_flag in (('foods',1),('retainedRevisions',0)):
                for food in pack[field]:
                    namespace,rid=identity(food); encoded=canonical(food)
                    db.execute('INSERT INTO food_revision VALUES (?,?,?,?,?,?,?)',
                               (namespace,rid,food['revision'],food['lifecycle'],current_flag,encoded,digest(encoded.encode())))
                    if current_flag and food['lifecycle']=='active':
                        db.executemany('INSERT INTO names VALUES (?,?,?,?)',[(namespace,rid,loc,name) for loc,name in sorted(food['names'].items())])
                        db.executemany('INSERT INTO markets VALUES (?,?,?)',[(namespace,rid,c) for c in food['salesCountries']])
                        db.executemany('INSERT INTO barcodes VALUES (?,?,?)',[(b,namespace,rid) for b in food['barcodes']])
            db.commit()
            require(db.execute('PRAGMA integrity_check').fetchone()[0]=='ok','SQLite integrity failure')
            db.execute('VACUUM')
        finally: db.close()
        sources=registry_sources(registry)
        used=sorted({v['providerID'] for v in pack['provenance'].values()})
        notices=[{'sourceID':sid,'licence':sources[sid].get('licence_id'),
                  'attribution':sources[sid].get('attribution_text') or 'Mealtracker synthetic development fixtures; fictional values, not production food evidence.'} for sid in used]
        (stage/'attribution.json').write_text(canonical(notices)+'\n',encoding='utf-8')
        (stage/'diff.json').write_text(canonical(delta)+'\n',encoding='utf-8')
        (stage/'catalogue.normalized.json').write_text(canonical(pack)+'\n',encoding='utf-8')
        manifest={key:pack[key] for key in ('schemaVersion','generationID','packID','packVersion','calculationVersion','fixtureOnly')}
        manifest.update(toolVersion=TOOL_VERSION,minimumReaderVersion=1,mode=mode,
                        currentRecordCount=len(pack['foods']),retainedRevisionCount=len(pack['retainedRevisions']),
                        sourceIDs=used,sourceVersions={sid:sorted({v['upstreamVersion'] for v in pack['provenance'].values() if v['providerID']==sid}) for sid in used},inputSHA256=file_digest(source),registrySHA256=file_digest(reg),
                        logicalSHA256=digest(canonical(pack).encode()),
                        files={p.name:file_digest(p) for p in sorted(stage.iterdir())})
        (stage/'manifest.json').write_text(canonical(manifest)+'\n',encoding='utf-8')
        os.rename(stage,target)
        return manifest
    finally:
        if stage.exists(): shutil.rmtree(stage)
