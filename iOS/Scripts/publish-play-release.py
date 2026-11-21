"""Publish only the newly authorized joint quality prerelease after CI gates.
Run with an explicit local manifest; credentials never enter argv or files.
"""
import argparse,hashlib,importlib.util,json,os,subprocess,urllib.error,urllib.parse,urllib.request,zipfile,plistlib,sys
from pathlib import Path
# Use Windows' verified certificate-chain builder (including trusted intermediates).
# No certificate or hostname verification is disabled.
if sys.platform == 'win32':
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.build/validation-tools'))
    import truststore
    truststore.inject_into_ssl()
parser=argparse.ArgumentParser();parser.add_argument('manifest');parser.add_argument('--validate-only',action='store_true');args=parser.parse_args()
m=json.loads(Path(args.manifest).read_text(encoding='utf-8'))
repo='Aljjulanda/GameLingo';base='/repos/'+repo
assert m['tag']=='ios-v0.4.0-preview.1'
assert m['validation_profile']=='play-preview-1'
assert len(m['source_commit'])==40 and all(c in '0123456789abcdef' for c in m['source_commit'])
expected_names={'GameLingo-unsigned.ipa','GameLingo-TV-0.7.0-preview.1.apk','SHA256SUMS.txt','GameLingo-Play-Report-AR.md'}
assert {a['name'] for a in m['assets']}==expected_names and len(m['assets'])==4
payloads={}
for a in m['assets']:
    content=Path(a['path']).read_bytes();assert hashlib.sha256(content).hexdigest()==a['sha256'],a['name']
    payloads[a['name']]=content
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('validate_ipa',root/'iOS/Scripts/validate-ipa.py')
validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
ipa=next(Path(a['path']) for a in m['assets'] if a['name'].endswith('.ipa'));validator.validate(ipa)
with zipfile.ZipFile(ipa) as z:
    info=plistlib.loads(z.read('Payload/GameLingo.app/Info.plist'))
    assert (info['CFBundleShortVersionString'],str(info['CFBundleVersion']))==('0.4.0','10')
    assert not any('/PlugIns/' in n or '.xctest' in n for n in z.namelist())
apk=next(Path(a['path']) for a in m['assets'] if a['name'].endswith('.apk'))
tools=Path(m['android_build_tools']);java=Path(m['java'])
verified=subprocess.check_output([str(java),'-jar',str(tools/'lib/apksigner.jar'),'verify','--verbose','--print-certs',str(apk)],text=True)
assert 'Signer #1 certificate SHA-256 digest: 48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38' in verified
badging=subprocess.check_output([str(tools/'aapt.exe'),'dump','badging',str(apk)],text=True,encoding='utf-8')
assert "package: name='dev.gamelingo.tv' versionCode='11' versionName='0.7.0-preview.1'" in badging
with zipfile.ZipFile(apk) as archive:
    for entry in archive.namelist():
        assert not entry.lower().endswith(('.glpack','.sqlite','.gxt2','.jsonl','.keystore','.jks','.p12'))
        if entry.endswith('.dex'):
            dex=archive.read(entry)
            assert all(token not in dex for token in [b'BootstrapRunner',b'Robolectric',b'CanvasRunner',b'NetworkRunner'])

assert m['apk_signer_sha256']=='48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38'
apk_evidence=json.loads(Path(m['apk_verification']).read_text())
assert apk_evidence['sha256']==hashlib.sha256(payloads[apk.name]).hexdigest()
assert apk_evidence['tests']>=45 and apk_evidence['failures']==apk_evidence['errors']==apk_evidence['skips']==0
assert apk_evidence['android_tree']==subprocess.check_output(['git','rev-parse',m['source_commit']+':android-tv'],text=True).strip()
qr_evidence=json.loads(Path(m['tcl_qr_evidence']).read_text())
assert 'stream=PASS:' in qr_evidence['output'] and 'INSTRUMENTATION_CODE: 0' in qr_evidence['output']
assert qr_evidence['stable_production_preferences_equal']
env=os.environ.copy();env.update(GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
r=subprocess.run(['git','-c','credential.interactive=never','credential','fill'],input='protocol=https\nhost=github.com\nusername=Aljjulanda\n\n',capture_output=True,text=True,check=True,env=env,timeout=20)
f=dict(line.split('=',1) for line in r.stdout.splitlines() if '=' in line)
class Redirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,url):
        redirected=super().redirect_request(req,fp,code,msg,headers,url)
        if redirected is not None and urllib.parse.urlparse(url).hostname not in ('api.github.com','uploads.github.com'):redirected.remove_header('Authorization')
        return redirected
opener=urllib.request.build_opener(Redirect)
def request(url,method='GET',data=None,content_type='application/json',accept='application/vnd.github+json'):
    assert urllib.parse.urlparse(url).scheme=='https' and urllib.parse.urlparse(url).hostname in ('api.github.com','uploads.github.com')
    req=urllib.request.Request(url,method=method,data=data,headers={'Authorization':'Bearer '+f['password'],'Accept':accept,'Content-Type':content_type,'X-GitHub-Api-Version':'2022-11-28','User-Agent':'GameLingo-quality-delivery'})
    with opener.open(req,timeout=180) as response:return response.read()
def api(path,method='GET',data=None):
    assert path=='/user' or path.startswith(base+'/') or path==base
    return json.loads(request('https://api.github.com'+path,method,None if data is None else json.dumps(data,ensure_ascii=False).encode()))
assert api('/user')['login'].lower()=='aljjulanda'
run=api(base+'/actions/runs/'+str(m['run_id']))
assert run['status']=='completed' and run['conclusion']=='success'
assert run['head_sha']==m['source_commit'] and run['head_branch']=='codex/play-experience-preview'
assert run['path']=='.github/workflows/ios-build.yml'
jobs=api(base+'/actions/runs/'+str(m['run_id'])+'/jobs')['jobs']
job=next(j for j in jobs if j['name']=='ios');assert job['conclusion']=='success'
for name in ['Reproduce LAN listener binding and endpoint representation','Record approved preview scope and toolchain','Validate source and preserve existing platform implementations','Test portable Swift dialogue and protocol logic','Validate real RDR2 data with native SQLite without publishing localization','Compare bounded maintenance tracker with accepted baseline','Compare post-OCR behavior and latency with approved Release','Validate Apple project','Archive and package unsigned IPA','Approved preview native Argos SQLite import names corrections and WSS gates','Upload approved unsigned IPA after required gates pass']:
    assert next(s for s in job['steps'] if s['name']==name)['conclusion']=='success'
artifacts=api(base+'/actions/runs/'+str(m['run_id'])+'/artifacts')['artifacts']
artifact=next(a for a in artifacts if a['name']=='GameLingo-unsigned-IPA');assert not artifact['expired']
for name in ['Core and Apple integration tests','Native Files picker selection and sandbox import']:
    assert next(s for s in job['steps'] if s['name']==name)['conclusion']=='skipped'
# Bind released IPA and accepted results to API-digested artifacts from this exact run.
for artifact_name, manifest_key in [('GameLingo-unsigned-IPA','ipa_artifact_zip'),('GameLingo-iOS-validation','validation_artifact_zip')]:
    item=next(a for a in artifacts if a['name']==artifact_name)
    assert not item['expired'] and item.get('workflow_run',{}).get('head_sha',m['source_commit'])==m['source_commit']
    archive_path=Path(m[manifest_key]);assert item['digest']=='sha256:'+hashlib.sha256(archive_path.read_bytes()).hexdigest()
    with zipfile.ZipFile(archive_path) as archive:
        if artifact_name=='GameLingo-unsigned-IPA':
            assert archive.namelist()==['GameLingo-unsigned.ipa']
            assert archive.read('GameLingo-unsigned.ipa')==payloads['GameLingo-unsigned.ipa']
        else:
            def read_evidence(name):
                entries=[n for n in archive.namelist() if n.endswith('/'+name) or n==name]
                assert len(entries)==1,name
                return json.loads(archive.read(entries[0]))
            acceptance=read_evidence('preview-acceptance.json')
            environment=read_evidence('preview-environment.json')
            benchmark=read_evidence('quality-pipeline-benchmark.json')
            core_entries=[n for n in archive.namelist() if n.endswith('/core-tests.log') or n=='core-tests.log']
            assert len(core_entries)==1
            import re
            progress=[tuple(map(int,pair)) for pair in re.findall(r'\[(\d+)/(\d+)\] Testing LingoCoreTests[.]',archive.read(core_entries[0]).decode())]
            assert progress
            total=max(x[1] for x in progress)
            assert total>=174 and len(progress)==total and {x[0] for x in progress}==set(range(1,total+1))
            expected=json.loads(subprocess.check_output(['git','show',m['source_commit']+':iOS/Scripts/preview-tests.json'],text=True))
            assert acceptance['profile']==expected['profile']=='play-preview-1'
            assert set(acceptance['outcomes'])==set(expected['selected'])
            assert acceptance['selected']==len(expected['selected'])
            for identifier,outcome in acceptance['outcomes'].items():
                assert outcome=='passed' or (outcome=='skipped' and identifier in expected['allowed_skips'])
            assert acceptance['deferred']==expected['deferred']
            assert environment['source_commit']==m['source_commit'] and environment['profile']=='play-preview-1'
            assert environment['architecture']=='x86_64' and environment['runner']=='macos-15-intel'
            assert environment['xcode'].splitlines()[0]=='Xcode 16.4'
            assert benchmark['all_off_equivalent'] and benchmark['fixture_streams']==10
            assert benchmark['results']['current_off']['messages']==24
report=payloads['GameLingo-Play-Report-AR.md'].decode('utf-8')
assert m['source_commit'] in report and str(m['run_id']) in report
assert all(text in report for text in ['Vision','Files','النص المتدرج','مؤجل','لم تُختبر','0.4.0','0.7.0'])
assert not any(text in report for text in ['قيد الاستكمال','تُستكمل بعد','تحتاج التشغيل النهائي','TODO','TBD'])
checksums=dict(line.split('  ',1)[::-1] for line in payloads['SHA256SUMS.txt'].decode('utf-8').splitlines())
assert set(checksums)==expected_names-{'SHA256SUMS.txt'}
assert all(checksums[name]==hashlib.sha256(payloads[name]).hexdigest() for name in checksums)
assert Path(m['notes_path']).read_bytes()==payloads['GameLingo-Play-Report-AR.md']
assert job['labels']==['macos-15-intel']
if args.validate_only:
    print(json.dumps(dict(validated=True,run_id=m['run_id'],source_commit=m['source_commit'],profile=m['validation_profile'],assets=sorted(payloads))),flush=True)
    sys.exit(0)


# Reject modifying any published Release/tag, including the rollback baseline.
releases=api(base+'/releases?per_page=100')
release=next((r for r in releases if r['tag_name']==m['tag']),None)
if release is not None:assert release['draft'] and release['target_commitish']==m['source_commit']
else:
    try: api(base+'/git/ref/tags/'+urllib.parse.quote(m['tag'],safe=''))
    except urllib.error.HTTPError as error:
        if error.code!=404:raise
    else:raise RuntimeError('Ref already exists; refusing to repoint it')
    release=api(base+'/releases','POST',{'tag_name':m['tag'],'target_commitish':m['source_commit'],'name':m['title'],'body':Path(m['notes_path']).read_text(encoding='utf-8'),'draft':True,'prerelease':True})
print(json.dumps({'new_draft_release_id':release['id']}),flush=True)
release_id=release['id'];upload=release['upload_url'].split('{',1)[0]
assert upload=='https://uploads.github.com'+base+'/releases/'+str(release_id)+'/assets'
assets={a['name']:a for a in api(base+'/releases/'+str(release_id)+'/assets')}
assert not(set(assets)-expected_names)
for name,content in payloads.items():
    a=assets.get(name)
    if a is None:a=json.loads(request(upload+'?'+urllib.parse.urlencode({'name':name}),'POST',content,'application/octet-stream'))
    digest=hashlib.sha256(content).hexdigest()
    assert a['state']=='uploaded' and a['size']==len(content)
    if a.get('digest'):assert a['digest']=='sha256:'+digest
    downloaded=request('https://api.github.com'+base+'/releases/assets/'+str(a['id']),accept='application/octet-stream')
    assert hashlib.sha256(downloaded).hexdigest()==digest
    print(json.dumps({'verified_download':name,'bytes':len(content),'sha256':digest}),flush=True)
api(base+'/releases/'+str(release_id),'PATCH',{'draft':False,'make_latest':'false'})
verified=api(base+'/releases/tags/'+m['tag']);assert not verified['draft'] and verified['prerelease'] and verified['published_at']
assert {a['name'] for a in verified['assets']}==expected_names
tag_ref=api(base+'/git/ref/tags/'+urllib.parse.quote(m['tag'],safe=''))
assert tag_ref['object']['type']=='commit' and tag_ref['object']['sha']==m['source_commit']
result={'url':verified['html_url'],'tag':m['tag'],'published_at':verified['published_at'],'source_commit':m['source_commit'],'run_id':m['run_id'],'assets':[{'name':a['name'],'url':a['browser_download_url'],'size':a['size'],'digest':a.get('digest')} for a in verified['assets']]}
Path(args.manifest).with_name('published-play-release.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False),flush=True)
