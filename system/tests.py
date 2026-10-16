"""Offline acceptance tests. Each test receives a disposable synthetic repository."""
import contextlib,copy,datetime as dt,io,json,os,shutil,sys,tempfile,unittest,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local/python'))
sys.path.insert(0,str(ROOT/'system'))
from lupa.lua54 import LuaRuntime
import host

class Studio:
    def __init__(self):
        self.temp=tempfile.TemporaryDirectory(prefix='collective-test-');self.root=Path(self.temp.name)
        for name in ['system','members','culture','shared','words','memory']:
            shutil.copytree(ROOT/name,self.root/name,ignore=shutil.ignore_patterns('__pycache__'))
        for name in ['config.lua','toolchain.lock','AGENTS.md']:shutil.copy2(ROOT/name,self.root/name)
        # Production data and live configuration must never influence offline fixtures.
        (self.root/'memory/sequence.txt').write_text('0\n')
        (self.root/'memory/catalogue.jsonl').write_text('')
        (self.root/'memory/exhibition.json').write_text('{"works":[]}\n')
        (self.root/'works').mkdir();self.calls=[];self.clock=0
        for name in ['ACCEPTANCE_PASSED','SANDBOX_PASSED','TOOLCHAIN_PASSED']:
            p=self.root/'.local'/name;p.parent.mkdir(exist_ok=True);p.write_text('mock test readiness')
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        def bridge(raw):
            a=json.loads(raw);self.calls.append(a)
            try:
                argv=a.get('argv',[])
                if a['op']=='exec' and '--model' in argv and argv[0]!='__missing_council_executable__':
                    raise RuntimeError('Offline harness blocks real model executables')
                return json.dumps({'ok':True,'value':host.dispatch(a)})
            except Exception as e:return json.dumps({'ok':False,'error':str(e)})
        self.lua.globals().HOST=bridge
        self.eval("F=require('system.fs'); J=require('system.json'); S=require('system.state'); E=require('system.engine'); C=require('system.clock'); c=dofile('config.lua'); c.live_ai=false; c.live_ready=false; c.publication.git_commit=false")
    def eval(self,code):
        previous=Path.cwd();oldroot=host.ROOT;os.chdir(self.root);host.ROOT=self.root
        try:return self.lua.execute(code)
        finally:os.chdir(previous);host.ROOT=oldroot
    def value(self,expression):return json.loads(self.eval('return J.encode('+expression+')'))
    def day(self,date):
        self.eval(f"clock=C.date(c,'{date}'); s=S.prepare(c,clock)")
    def beat(self):return self.value('E.advance(c,clock,true)')
    def finish(self,limit=30):
        for _ in range(limit):
            s=self.beat()
            if s['state']in ['COMPLETE','WAITING_FOR_HUMAN','NEEDS_ATTENTION','RESCUE_PENDING','PAUSED_BUDGET']:return s
        raise AssertionError('Did not terminate: '+str(s))
    def events(self):
        p=self.root/'.local/logs/model-usage.jsonl'
        return [json.loads(x)for x in p.read_text().splitlines()]if p.exists()else []
    def close(self):
        for p in self.root.rglob('*'):
            if p.is_file():p.chmod(0o666)
        self.temp.cleanup()

class Acceptance(unittest.TestCase):
    def setUp(self):self.t=Studio()
    def tearDown(self):self.t.close()
    def test_complete_and_rest(self):
        t=self.t;t.day('2027-01-04');s=t.finish();self.assertEqual(s['state'],'COMPLETE');self.assertEqual(len(t.events()),2)
        for _ in range(20):self.assertEqual(t.beat()['state'],'COMPLETE')
        self.assertEqual(len(t.events()),2)
    def test_overlapping_heartbeats(self):
        t=self.t
        self.assertTrue(t.eval("token=F.call{op='lock',path='.local/locks/heartbeat',timeout=21600,pid=F.call{op='pid'}};return token"))
        self.assertIsNone(t.eval("return F.call{op='lock',path='.local/locks/heartbeat',timeout=21600,pid=F.call{op='pid'}}"))
        result=t.value("require('system.lock').with(c,function() error('must not execute') end)")
        self.assertEqual(result['state'],'LOCKED')
    def test_stale_lock(self):
        t=self.t
        t.eval("F.mkdir('.local/locks/heartbeat');F.save('.local/locks/heartbeat/owner.json',{pid=2147483647,timestamp=1,token='old'})")
        self.assertTrue(t.eval("return F.call{op='lock',path='.local/locks/heartbeat',timeout=21600,pid=F.call{op='pid'}}"))
    def test_crash_after_build_receipt(self):
        t=self.t;t.day('2027-01-04')
        for _ in range(4):t.beat()
        self.assertEqual(t.value('S.get().state'),'VERIFY');self.assertEqual(len(t.events()),2)
        t.eval("s=S.get();s.state='BUILD';S.save(s)")
        self.assertEqual(t.beat()['state'],'VERIFY');self.assertEqual(len(t.events()),2)
    def test_uncertain_stage_never_repeats(self):
        t=self.t;t.day('2027-01-04');t.beat()
        t.eval("F.save('.local/runs/2027-01-04/ideate/stage.requested.json',{invocation_id='uncertain'})")
        self.assertEqual(t.beat()['state'],'NEEDS_ATTENTION');self.assertEqual(len(t.events()),0)
    def test_wednesday_is_autonomous_member(self):
        t=self.t;t.day('2027-01-06');s=t.finish()
        self.assertEqual(t.value('C.members[3]'),'morrow')
        self.assertEqual(s['member'],'morrow');self.assertEqual(s['state'],'COMPLETE')
        self.assertEqual(len(t.events()),2)
    def test_creative_metadata_rejects_wrong_member_and_vocabulary(self):
        t=self.t;t.day('2027-01-04')
        t.eval("p=F.load('system/fixtures/valid-proposal.json');p.member_move='questionnaire';p.agency='teleport'")
        errors=t.value("require('system.creative').validate(p,'vellum',true)")
        self.assertIn('Invalid member_move for vellum',errors)
        self.assertIn('Invalid creative metadata: agency',errors)
        schema=t.value("require('system.creative').schema('morrow')")
        self.assertIn('questionnaire',schema['properties']['member_move']['enum'])
        self.assertNotIn('split',schema['properties']['member_move']['enum'])

    def test_creative_metadata_publication_and_tamper(self):
        t=self.t;t.day('2027-01-06');self.assertEqual(t.finish()['state'],'COMPLETE')
        record=t.value("F.lines('memory/catalogue.jsonl')[1]")
        self.assertEqual(record['member_move'],'diagnosis')
        self.assertEqual(record['creative_form'],'static-artefact')
        self.assertEqual(record['metadata_version'],1)
        t.eval("m=F.load('.local/workspaces/0001/artifact/manifest.json');m.agency='answer';F.save('.local/workspaces/0001/artifact/manifest.json',m)")
        report=t.value("require('system.verify').run(c,'.local/workspaces/0001/artifact',S.get())")
        self.assertFalse(report['ok']);self.assertIn('Accepted creative metadata changed: agency',report['errors'])

    def test_creative_history_window_and_member_history(self):
        t=self.t
        t.eval("records={};for i=1,20 do records[i]={id=i,member=i%2==0 and 'morrow' or 'moss',form='defold-2d',creative_form='test-questionnaire',member_move='diagnosis',source_domain='interface',sensory_mode='visual',dimensionality='2d',temporal_mode='stateful',agency='answer',randomness='none'}end;records[20].source_domain=nil")
        summary=t.value("require('system.creative').summary(records,'morrow')")
        self.assertEqual(summary['window'],14)
        self.assertEqual(summary['counts']['source_domain'],{'interface':13,'unknown':1})
        self.assertEqual(len(summary['member_forms']),3);self.assertEqual(len(summary['member_moves']),5)
        self.assertEqual(summary['member_moves'],['diagnosis']*5)
        text=t.value("require('system.creative').context(records,'morrow')")
        self.assertEqual(text,t.value("require('system.creative').context(records,'morrow')"))
        self.assertIn('Repetition is allowed',text)

    def test_creative_legacy_and_partial_metadata(self):
        t=self.t
        self.assertEqual(t.value("require('system.creative').validate({member='sable'},'sable',false)"),[])
        self.assertTrue(t.value("require('system.creative').validate({member_move='measure'},'pica',false)"))
        summary=t.value("require('system.creative').summary({{member='sable',form='defold-2d'}},'sable')")
        self.assertEqual(summary['counts']['creative_form'],{'unknown':1})
        self.assertEqual(summary['member_moves'],['unknown'])

    def test_creative_context_keeps_words_and_move_freedom(self):
        t=self.t;t.day('2027-01-06')
        prompt=t.value("require('system.context').ideate(c,S.get())")
        self.assertIn('Weekly words (optional):',prompt)
        self.assertIn('RECENT COLLECTIVE SHAPE',prompt)
        self.assertIn('behavioural_inference',prompt)
        self.assertIn('Choose the project first',prompt)

    def test_quota_denial_stops_gateway(self):
        t=self.t;t.day('2027-01-04');t.beat();t.eval("c.live_ai=true;c.live_ready=true;s=S.get();s.mode='live';S.save(s);c.budget.rolling_7d.luna_high_soft=0")
        self.assertEqual(t.beat()['state'],'PAUSED_BUDGET');self.assertEqual(len(t.events()),0)
        self.assertFalse(any(a.get('argv',[''])[0]=='codex'for a in t.calls))
    def test_duplicate_retry_once(self):
        t=self.t;t.eval("p=F.load('system/fixtures/valid-proposal.json');p.id=99;p.summary=p.premise;p.member='moss';p.date='2027-01-01';F.append('memory/catalogue.jsonl',p)")
        t.day('2027-01-04');t.eval("s=S.get();s.scenario='duplicate';S.save(s)")
        s=t.finish();self.assertEqual(s['retry'],1);self.assertEqual(s['state'],'COMPLETE');self.assertEqual(len(t.events()),3)
    def test_second_duplicate_stops(self):
        t=self.t;t.eval("p=F.load('system/fixtures/valid-proposal.json');p.id=99;p.summary=p.premise;p.member='moss';p.date='2027-01-01';F.append('memory/catalogue.jsonl',p)")
        t.day('2027-01-04');t.eval("s=S.get();s.proposal=p;s.retry=1;s.state='PROPOSAL_GATE';S.save(s)")
        self.assertEqual(t.beat()['state'],'NEEDS_ATTENTION')
    def test_one_repair(self):
        t=self.t;t.day('2027-01-04');t.eval("s=S.get();s.scenario='broken';S.save(s)")
        s=t.finish();self.assertEqual(s['state'],'COMPLETE');self.assertEqual(s['repairs'],1);self.assertEqual(len(t.events()),3)
    def test_repeated_repair_blocked_and_no_publication(self):
        t=self.t;t.day('2027-01-04');t.eval("s=S.get();s.scenario='repair-fails';S.save(s)")
        s=t.finish();self.assertEqual(s['state'],'RESCUE_PENDING');self.assertEqual(s['repairs'],1)
        for _ in range(20):t.beat()
        self.assertEqual(len(t.events()),3);self.assertEqual(list((t.root/'works').iterdir()),[])
    def test_publication_retry_exactly_once(self):
        t=self.t;t.day('2027-01-04');t.finish()
        for _ in range(3):t.eval("s=S.get();s.state='PUBLISH';S.save(s)");self.assertEqual(t.beat()['state'],'COMPLETE')
        self.assertEqual(len(t.value("F.lines('memory/catalogue.jsonl')")),1)
        self.assertEqual(t.value("F.load('memory/exhibition.json').works"),[1])
        self.assertEqual(len(list((t.root/'works').iterdir())),1)
    def test_readme_deterministic(self):
        t=self.t;t.day('2027-01-04');t.finish();a=(t.root/'README.md').read_bytes()
        t.eval("require('system.publish').readme(c)");self.assertEqual(a,(t.root/'README.md').read_bytes())
    def test_missed_date_not_backfilled(self):
        t=self.t;t.day('2027-01-04');t.finish();t.eval("clock=C.date(c,'2027-01-08')");t.beat()
        self.assertEqual(t.value('S.get().date'),'2027-01-08');self.assertFalse((t.root/'.local/runs/2027-01-05').exists())
    def test_pause_blocks_inference(self):
        t=self.t;t.day('2027-01-04');t.beat();t.eval("F.write('.local/PAUSE','pause')")
        for _ in range(5):self.assertEqual(t.beat()['state'],'PAUSED')
        self.assertEqual(t.events(),[])
    def test_dry_run(self):
        t=self.t;t.day('2027-01-04');t.beat()
        v=t.value("require('system.codex').invoke(c,S.get(),'ideate',clock,E.prompt(c,S.get(),'ideate'),true,false)")
        self.assertEqual(v['model'],'gpt-6-luna');self.assertIn('--sandbox',v['command']);self.assertEqual(t.events(),[])
    def test_automatic_astra_disabled(self):
        t=self.t;t.day('2027-01-04')
        self.assertFalse(t.eval("return require('system.budget').authorize(c,S.get(),'astra_low',clock,false)")[0])
    def test_builder_cwd_and_sandbox(self):
        t=self.t;t.day('2027-01-04');t.finish()
        request=json.loads((t.root/'.local/runs/2027-01-04/static_build/stage.requested.json').read_text())
        argv=request['command'];self.assertEqual(argv[argv.index('--sandbox')+1],'workspace-write')
        self.assertTrue(argv[argv.index('--cd')+1].endswith('/.local/workspaces/0001'))
        self.assertNotIn('--add-dir',argv);self.assertIn('--ignore-user-config',argv)
    def test_fixed_week_words(self):
        t=self.t;t.eval("a=require('system.words').get('2027-W01');b=require('system.words').get('2027-W01')")
        self.assertEqual(t.value('a'),t.value('b'));self.assertEqual(len(t.value('a.words')),3)
    def test_london_dst_and_iso_year(self):
        t=self.t
        self.assertEqual(t.value("C.now(c,1792884600)")['date'],'2026-10-25')
        self.assertEqual(t.value("C.date(c,'2027-01-01')")['week'],'2026-W53')
    def test_budget_reservation_and_cooldown(self):
        t=self.t;t.day('2027-01-04')
        t.eval("c.live_ai=true;c.live_ready=true;s=S.get();s.mode='live';c.budget.rolling_7d.luna_high_soft=4")
        self.assertFalse(t.eval("return require('system.budget').authorize(c,s,'simple_repair',clock,false)")[0])
        t.eval("c.budget.rolling_7d.luna_high_soft=10;F.append('.local/logs/model-usage.jsonl',{timestamp=clock.timestamp-60,mode='live',alias='luna',effort='high'})")
        self.assertEqual(t.value("require('system.budget').view(c,clock.timestamp).five_hour"),1)
        self.assertEqual(t.eval("return require('system.budget').authorize(c,s,'ideate',clock,false)")[1],'Cooldown')
    def test_allocation_crash_does_not_reuse(self):
        t=self.t;t.day('2027-01-04');t.eval("F.write('memory/sequence.txt','0')")
        t.day('2027-01-04');self.assertEqual(t.value('S.get().id'),1);self.assertEqual(t.value("tonumber(F.read('memory/sequence.txt'))"),1)
    def test_manifest_network_and_links(self):
        t=self.t;t.day('2027-01-04');t.finish()
        p=t.root/'.local/workspaces/0001/artifact/work.txt';p.write_text('https://remote.example/image')
        r=t.value("require('system.verify').run(c,'.local/workspaces/0001/artifact',S.get())")
        self.assertFalse(r['ok'])
    def test_json_strict(self):
        for text in ['{"a":1,"a":2}','[1,]','01','1.','{"x":"\\ud800"}']:
            self.assertFalse(self.t.eval('return pcall(J.decode,'+json.dumps(text)+')')[0])
        self.assertEqual(self.t.value('J.decode("[true,false,null,1.25]")'),[True,False,None,1.25])
    def test_synthetic_week(self):
        t=self.t;results=[]
        for date in ['2027-01-04','2027-01-05','2027-01-06','2027-01-07','2027-01-08','2027-01-09','2027-01-10']:
            t.day(date)
            if date=='2027-01-07':t.eval("s=S.get();s.scenario='broken';S.save(s)")
            results.append(t.finish()['state'])
        self.assertEqual(results,['COMPLETE']*7)
        self.assertEqual(len(t.events()),15);self.assertEqual(len(t.value("F.lines('memory/catalogue.jsonl')")),7)
    def test_human_submission_no_inference(self):
        t=self.t;t.day('2027-01-06')
        t.eval("s=S.get();s.member='human';require('system.workspace').prepare(c,s);p=F.load('system/fixtures/valid-proposal.json');s.proposal=p;m=require('system.workspace').manifest(c,s);for _,k in ipairs(require('system.creative').fields)do m[k]=nil end;m.metadata_version=nil;m.member='human';F.save('.local/workspaces/0001/artifact/manifest.json',m);F.write('.local/workspaces/0001/artifact/work.txt','Human fixture.');s.proposal=nil;s.decision={exhibit=false,retire_id=J.null,curation_note='Human choice'};S.transition(s,'VERIFY')")
        self.assertEqual(t.finish()['state'],'COMPLETE');self.assertEqual(t.events(),[])
        self.assertEqual(t.value("F.load('memory/exhibition.json').works"),[])
    def test_immutable_after_verification(self):
        t=self.t;t.day('2027-01-04')
        for _ in range(5):t.beat()
        self.assertEqual(t.value('S.get().state'),'PUBLISH')
        t.eval("F.write('.local/workspaces/0001/artifact/work.txt','changed after verification')")
        self.assertEqual(t.beat()['state'],'PUBLISH');self.assertEqual(list((t.root/'works').iterdir()),[])
    def test_exhibition_full_and_retirement(self):
        t=self.t;t.eval('c.exhibition.maximum=1');t.day('2027-01-04');t.finish();t.day('2027-01-05');t.finish()
        self.assertEqual(t.value("F.load('memory/exhibition.json').works"),[2]);self.assertEqual(len(list((t.root/'works').iterdir())),2)
    def test_git_publication_once(self):
        t=self.t
        t.eval("assert(F.exec({'git','init'},'.',20).exit_code==0);F.exec({'git','config','user.name','Fixture'},'.',20);F.exec({'git','config','user.email','fixture@example.invalid'},'.',20);F.write('.gitignore','.local/\\n');F.exec({'git','add','.'},'.',20);assert(F.exec({'git','commit','-m','fixture foundation'},'.',20).exit_code==0);c.publication.git_commit=true")
        t.day('2027-01-04');self.assertEqual(t.finish()['state'],'COMPLETE')
        t.eval("s=S.get();s.state='PUBLISH';S.save(s)");self.assertEqual(t.beat()['state'],'COMPLETE')
        self.assertEqual(t.value("F.exec({'git','rev-list','--count','HEAD'},'.',20).stdout").strip(),'2')
    def test_active_lock_never_reclaimed(self):
        t=self.t;t.eval("F.mkdir('.local/locks/heartbeat');F.save('.local/locks/heartbeat/owner.json',{pid=F.call{op='pid'},timestamp=1,token='active'})")
        self.assertIsNone(t.eval("return F.call{op='lock',path='.local/locks/heartbeat',timeout=1}"))
    def test_explicit_historical_recovery(self):
        t=self.t;t.day('2027-01-04');t.eval("s=S.get();s.recovery=true;S.save(s);clock=C.date(c,'2027-01-08')")
        self.assertEqual(t.finish()['date'],'2027-01-04')
    def test_bad_curation_has_no_public_side_effects(self):
        t=self.t;t.day('2027-01-04')
        for _ in range(5):t.beat()
        before=(t.root/'memory/catalogue.jsonl').read_bytes()
        exhibition=(t.root/'memory/exhibition.json').read_bytes()
        t.eval("s=S.get();s.decision.retire_id=999;S.save(s)")
        self.assertEqual(t.beat()['state'],'PUBLISH')
        self.assertEqual(list((t.root/'works').iterdir()),[])
        self.assertEqual((t.root/'memory/catalogue.jsonl').read_bytes(),before)
        self.assertEqual((t.root/'memory/exhibition.json').read_bytes(),exhibition)
    def test_preview_and_pause_work_while_heartbeat_locked(self):
        t=self.t;t.day('2027-01-04');t.finish()
        t.eval("token=F.call{op='lock',path='.local/locks/heartbeat',timeout=21600,pid=F.call{op='pid'}}")
        launcher='import runpy,sys;sys.path.insert(0,sys.argv[1]);sys.argv=sys.argv[2:];runpy.run_path(sys.argv[0],run_name="__main__")'
        def cli(*args):
            return subprocess.run([sys.executable,'-c',launcher,str(ROOT/'.local/python'),str(t.root/'system/run.py'),*args],capture_output=True,text=True,timeout=30)
        # Exercise the generated builder helper through a separate Lua process.
        result=cli('preview',str(t.root/'.local/workspaces/0001/artifact'))
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue(json.loads(result.stdout)['ok'])
        status=cli('status');self.assertIn('COLLECTIVE STATUS',status.stdout)
        paused=cli('pause');self.assertEqual(paused.returncode,0,paused.stderr)
        self.assertTrue((t.root/'.local/PAUSE').exists())
        invalid=cli('preview',str(t.root/'works'))
        self.assertNotEqual(invalid.returncode,0)
    def test_missing_bob_is_a_verification_failure(self):
        t=self.t;t.day('2027-01-04');t.finish()
        t.eval("m=F.load('.local/workspaces/0001/artifact/manifest.json');m.form='defold-2d';m.entry='game.project';F.save('.local/workspaces/0001/artifact/manifest.json',m);F.write('.local/workspaces/0001/artifact/game.project','[project]\\ntitle = Fixture\\n')")
        report=t.value("require('system.verify').run(c,'.local/workspaces/0001/artifact')")
        self.assertFalse(report['ok']);self.assertIn('Pinned Bob not installed',' '.join(report['errors']))
    def test_missing_executable_does_not_charge_model_usage(self):
        t=self.t;t.day('2027-01-04');t.beat()
        t.eval("c.live_ai=true;c.live_ready=true;c.process.codex='__missing_council_executable__';s=S.get();s.mode='live';S.save(s)")
        state=t.beat();self.assertEqual(state['state'],'NEEDS_ATTENTION')
        event=t.events()[0];self.assertEqual(event['outcome'],'not_started')
        self.assertEqual(t.value("require('system.budget').view(c,clock.timestamp).rolling_7d.luna_high"),0)
        process=t.value("F.load('.local/runs/2027-01-04/ideate/process.json')")
        self.assertFalse(process['started']);self.assertEqual(process['exit_code'],127)
    def test_offline_harness_blocks_live_executables(self):
        result=self.t.eval("return pcall(F.exec,{'codex','exec','--model','gpt-6-luna'},'.',10,'')")
        self.assertFalse(result[0]);self.assertIn('Offline harness blocks',result[1])
    def test_windows_gateway_preserves_sandbox_with_ignored_config(self):
        if os.name!='nt':self.skipTest('Windows only')
        t=self.t;t.day('2027-01-04')
        command=t.value("require('system.codex').command(c,S.get(),'defold_build','workspace','receipt')")
        self.assertIn('--ignore-user-config',command)
        self.assertIn('windows.sandbox="mxc"',command)
        self.assertEqual(command[command.index('--sandbox')+1],'workspace-write')
        self.assertNotIn('allow_login_shell=false',command)
    def test_reset_build_uses_new_receipts_and_preserves_ideation(self):
        t=self.t;t.day('2027-01-04');t.finish()
        t.eval("s=S.get();s.build_attempt=1")
        self.assertTrue(t.value("require('system.codex').paths(s,'defold_build')").endswith('defold_build-attempt-1'))
        self.assertTrue(t.value("require('system.codex').paths(s,'simple_repair')").endswith('simple_repair-attempt-1'))
        self.assertTrue(t.value("require('system.codex').paths(s,'ideate')").endswith('/ideate'))
    def test_failed_preflight_cannot_spend_a_model_call(self):
        t=self.t;t.day('2027-01-04')
        for _ in range(3):t.beat()
        t.eval("c.live_ai=true;c.live_ready=true;s=S.get();s.mode='live';S.save(s);require('system.process').preflight=function()return false,'policy blocked'end")
        self.assertEqual(t.beat()['state'],'NEEDS_ATTENTION')
        self.assertTrue(all(event['mode']=='mock'for event in t.events()))
        self.assertFalse((t.root/'.local/runs/2027-01-04/static_build/stage.requested.json').exists())
    def test_child_environment_keeps_runtime_paths_and_drops_secrets(self):
        previous=os.environ.get('COUNCIL_TEST_SECRET');os.environ['COUNCIL_TEST_SECRET']='must-not-reach-child'
        try:
            argv=self.t.lua.table_from([sys.executable,'-c','import os,json;print(json.dumps({"secret":os.getenv("COUNCIL_TEST_SECRET"),"path":bool(os.getenv("PATH")),"systemroot":bool(os.getenv("SystemRoot"))}))'])
            self.t.lua.globals().test_argv=argv
            result=self.t.value("F.exec(test_argv,'.',20)")
            values=json.loads(result['stdout']);self.assertIsNone(values['secret']);self.assertTrue(values['path'])
            if os.name=='nt':self.assertTrue(values['systemroot'])
        finally:
            if previous is None:os.environ.pop('COUNCIL_TEST_SECRET',None)
            else:os.environ['COUNCIL_TEST_SECRET']=previous

if __name__=='__main__':
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(Acceptance)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    report={'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'live_model_calls':0,'ok':result.wasSuccessful()}
    (ROOT/'docs').mkdir(exist_ok=True)
    (ROOT/'docs/acceptance-results.json').write_text(json.dumps(report,indent=2)+'\n')
    if result.wasSuccessful():
        (ROOT/'.local').mkdir(exist_ok=True);(ROOT/'.local/ACCEPTANCE_PASSED').write_text(json.dumps(report))
    sys.exit(not result.wasSuccessful())
