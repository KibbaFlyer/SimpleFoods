from uuid import UUID
from decimal import localcontext
from .core import require, decimal
from .policy import registry_sources, gate, iso_instant, url

UNITS = {'energy.declared':'kcal', 'protein':'g', 'carbohydrate.euAvailable':'g',
         'carbohydrate.total':'g', 'fat.total':'g', 'fat.saturated':'g', 'sugars':'g',
         'fibre':'g', 'salt.equivalent':'g', 'sodium':'mg'}
COUNTRIES = set('AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW'.split())
# ISO 3166-1 assigned alpha-2 values. No origin inference from any of these.
COUNTRIES.update({'HN','IL','IN'})

def shape(value, required, optional=(), label='object'):
    require(isinstance(value,dict),label+' must be object')
    require(all(isinstance(k,str) for k in value),label+' keys must be strings')
    require(set(required)<=set(value),label+' missing required fields')
    require(set(value)<=set(required)|set(optional),label+' unknown fields forbidden in public schema')

def text(value, label):
    require(isinstance(value,str) and 0<len(value)<=4096 and not any(ord(c)<32 for c in value),label+' requires nonempty safe string')

def string_list(value,label):
    require(isinstance(value,list),label+' must be list')
    for item in value:text(item,label)

def identity(food):
    require(isinstance(food,dict),'food must be object')
    fid=food.get('id')
    shape(fid,('scope','namespace','recordID'),label='catalogue identity')
    require(fid['scope']=='catalogue','only catalogue identities permitted')
    text(fid['namespace'],'namespace');text(fid['recordID'],'recordID')
    return fid['namespace'],fid['recordID']

def names(value):
    require(isinstance(value,dict) and value,'names required')
    for language,name in value.items():
        require(language in {'sv','en','de'},'unsupported name language')
        text(name,'name')

def country_set(value):
    require(isinstance(value,list) and all(isinstance(v,str) and v in COUNTRIES for v in value),'invalid ISO country code')
    require(len(set(value))==len(value),'duplicate country membership')

def evidence_ref(ref,evidence,provider,provenance):
    text(ref,'evidence reference')
    require(ref in evidence,'unresolved evidence reference')
    require(provenance[evidence[ref]['provenanceRef']]['providerID']==provider,'cross-source evidence unsupported')

def nutrient(key,value,evidence,provider,provenance):
    require(key in UNITS and isinstance(value,dict),'unsupported nutrient definition')
    status=value.get('status')
    require(isinstance(status,str) and status in {'known','knownZero','unknown','trace','derived'},'unsupported nutrient status')
    required={'known':('status','value','unit'),'knownZero':('status','value','unit'),
              'unknown':('status','reason','unit'),'trace':('status','upperBound','unit'),
              'derived':('status','value','unit','methodID','inputRefs','estimated')}[status]
    shape(value,required,label='nutrient '+status)
    require(value['unit']==UNITS[key],'invalid canonical nutrient unit')
    if status in {'known','knownZero','derived'}:
        amount=decimal(value['value'])
        require(status!='known' or amount>0,'known must be positive')
        require(status!='knownZero' or amount==0,'knownZero must be zero')
    elif status=='unknown':text(value['reason'],'unknown reason')
    elif value['upperBound'] is not None:decimal(value['upperBound'],positive=True)
    if status=='derived':
        text(value['methodID'],'derivation method')
        string_list(value['inputRefs'],'derivation inputs')
        require(value['inputRefs'],'derivation inputs required')
        for ref in value['inputRefs']:evidence_ref(ref,evidence,provider,provenance)
        require(type(value['estimated']) is bool,'derived estimated flag required')

def profile(value,provenance,evidence,food_provenance):
    shape(value,('profileRevision','basis','preparation','density','nutrients','portions','provenanceRef'),label='profile')
    text(value['profileRevision'],'profile revision')
    # No composition/cross-source profiles in this bounded schema.
    require(value['provenanceRef']==food_provenance,'profile provenance must equal food provenance')
    provider=provenance[food_provenance]['providerID']
    basis=value['basis'];shape(basis,('quantity','unit','portionID'),label='basis')
    decimal(basis['quantity'],positive=True)
    require(isinstance(basis['unit'],str) and basis['unit'] in {'g','ml','definedPortion'},'unsupported basis unit')
    require(isinstance(value['preparation'],str) and value['preparation'] in {'raw','cooked','drained','frozenAsSold','prepared','other'},'invalid preparation')
    require(isinstance(value['nutrients'],dict),'nutrient map required')
    for key,item in value['nutrients'].items():nutrient(key,item,evidence,provider,provenance)
    density=value['density']
    if density is not None:
        shape(density,('gramsPerMillilitre','evidenceRef','quality'),label='density')
        decimal(density['gramsPerMillilitre'],positive=True)
        evidence_ref(density['evidenceRef'],evidence,provider,provenance)
        require(isinstance(density['quality'],str) and density['quality'] in {'measured','estimated'},'invalid density quality')
    portions=value['portions'];require(isinstance(portions,list),'portions required')
    ids=set()
    for portion in portions:
        shape(portion,('id','names','massGrams','volumeMillilitres','quality','evidenceRef'),label='portion')
        text(portion['id'],'portion ID');require(portion['id'] not in ids,'duplicate portion ID');ids.add(portion['id'])
        if portion['names'] is not None:
            require(isinstance(portion['names'],dict),'portion names must be object or null')
            if portion['names']:names(portion['names'])
        require(isinstance(portion['quality'],str) and portion['quality'] in {'measured','estimated'},'invalid portion quality')
        evidence_ref(portion['evidenceRef'],evidence,provider,provenance)
        mass,volume=portion['massGrams'],portion['volumeMillilitres']
        require(mass is not None or volume is not None,'portion requires equivalence')
        if mass is not None:decimal(mass,positive=True)
        if volume is not None:decimal(volume,positive=True)
        if mass is not None and volume is not None:
            require(density is not None,'dual equivalents require density')
            with localcontext() as context:
                context.prec=50
                require(decimal(mass)==decimal(volume)*decimal(density['gramsPerMillilitre']),'inconsistent density equivalents')
    if basis['unit']=='definedPortion':
        text(basis['portionID'],'basis portion ID');require(basis['portionID'] in ids,'unresolved basis portion')
    else:require(basis['portionID'] is None,'mass/volume basis must not specify portion')

def validate(pack,registry,mode='development',evidence_allowlist=()):
    shape(pack,('schemaVersion','fixtureOnly','generationID','packID','packVersion','calculationVersion','provenance','foods','retainedRevisions'),('evidence',),label='pack')
    require(type(pack['schemaVersion']) is int and pack['schemaVersion']==1,'unsupported pack schema version')
    text(pack['generationID'],'generation ID')
    try:require(str(UUID(pack['generationID']))==pack['generationID'],'noncanonical generation UUID')
    except ValueError:require(False,'invalid generation UUID')
    for key in ('packID','packVersion','calculationVersion'):text(pack[key],key)
    require(type(pack['fixtureOnly']) is bool,'fixtureOnly flag required')
    require(mode!='production' or not pack['fixtureOnly'],'fixture pack forbidden in production')
    sources=registry_sources(registry)
    provenance=pack['provenance'];require(isinstance(provenance,dict) and provenance,'provenance required')
    for ref,prov in provenance.items():
        text(ref,'provenance reference')
        shape(prov,('providerID','sourceRecordID','sourceURL','upstreamVersion','retrievedAt','sourceLanguage','licenceReference','transformationVersion','reviewStatus'),('rawSHA256','termsEvidenceRef','reviewerDecision','distributionOfferURL'),label='provenance')
        sid=prov['providerID'];text(sid,'provider ID');require(sid in sources,'unregistered provenance provider')
        gate(sources[sid],mode,evidence_allowlist)
        for key in ('sourceRecordID','upstreamVersion','sourceLanguage','licenceReference','transformationVersion','reviewStatus'):text(prov[key],key)
        require(prov['sourceLanguage'] in {'sv','en','de'},'unsupported source language in leaf scaffold')
        iso_instant(prov['retrievedAt'])
        if sid=='mealtracker.synthetic':
            require(pack['fixtureOnly'] and prov['reviewStatus']=='syntheticOnly','synthetic fixture provenance required')
            require(prov['sourceURL'] is None,'synthetic source URL must be null')
            require(not(set(prov)&{'rawSHA256','termsEvidenceRef','reviewerDecision','distributionOfferURL'}),'synthetic provenance cannot claim real-source review')
        else:
            url(prov['sourceURL'])
            require(prov['upstreamVersion']==sources[sid]['upstream_version'],'upstream version mismatch')
            require(prov['licenceReference']==sources[sid]['licence_id'],'licence mismatch')
            require(prov.get('rawSHA256')==sources[sid]['sha256'],'raw provenance checksum mismatch')
            for key in ('termsEvidenceRef','reviewerDecision'):text(prov.get(key),key)
            require(prov['reviewerDecision']==sources[sid]['reviewer_decision_reference'],'provenance reviewer mismatch')
    evidence=pack.get('evidence',{});require(isinstance(evidence,dict),'evidence must be dictionary')
    for ref,item in evidence.items():
        text(ref,'evidence ID');shape(item,('kind','provenanceRef','description'),label='evidence')
        text(item['provenanceRef'],'evidence provenance')
        require(item['provenanceRef'] in provenance,'unresolved evidence provenance')
        text(item['description'],'evidence description')
        # Real-source evidence modelling is deferred to reviewed adapter schemas.
        require(item['kind']=='synthetic' and pack['fixtureOnly'] and provenance[item['provenanceRef']]['providerID']=='mealtracker.synthetic','only synthetic evidence supported by v1 scaffold')
    current,retained=pack['foods'],pack['retainedRevisions']
    require(isinstance(current,list) and isinstance(retained,list),'foods/retainedRevisions lists required')
    seen=set();current_ids=set()
    for collection,current_flag in ((current,True),(retained,False)):
        for food in collection:
            shape(food,('id','revision','kind','lifecycle','names','salesCountries','manufacturingCountries','ingredientOrigins','barcodes','profile','provenanceRef'),label='food')
            fid=identity(food);text(food['revision'],'food revision')
            key=(*fid,food['revision']);require(key not in seen,'duplicate food revision');seen.add(key)
            if current_flag:require(fid not in current_ids,'duplicate current identity');current_ids.add(fid)
            require(isinstance(food['kind'],str) and food['kind'] in {'ingredient','product'},'only leaf foods supported in schema 1 scaffold')
            require(isinstance(food['lifecycle'],str) and food['lifecycle'] in {'active','retired'},'invalid public lifecycle')
            names(food['names'])
            for field in ('salesCountries','manufacturingCountries','ingredientOrigins'):country_set(food[field])
            require(isinstance(food['barcodes'],list) and all(isinstance(b,str) and b.isascii() and b.isdigit() for b in food['barcodes']),'barcodes must be digit strings')
            require(len(set(food['barcodes']))==len(food['barcodes']),'duplicate barcode')
            ref=food['provenanceRef'];text(ref,'food provenance')
            require(ref in provenance,'unresolved food provenance')
            require(provenance[ref]['providerID']==fid[0],'namespace/provider mismatch')
            if fid[0]!='mealtracker.synthetic':require(provenance[ref]['sourceRecordID']==fid[1],'source record ID mismatch')
            profile(food['profile'],provenance,evidence,ref)
    return pack
