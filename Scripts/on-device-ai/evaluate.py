#!/usr/bin/env python3
"""32 frozen synthetic cases (8/category), distinct from 8 tuning cases.
Uses the production Swift runtime (not CLI conversation/template defaults).
Automatic rubric only; it cannot replace human fitness relevance review.
"""
import argparse, json, pathlib, re, subprocess, statistics, platform, time
ROOT=pathlib.Path(__file__).resolve().parents[2]
CACHE=ROOT/'.local-ai-cache'
SYSTEM='Select useful facts and approved actions for a fitness report. Return only JSON with factIDs and actionIDs, each at most 3 unique IDs. Prioritize pain, limitations, poor recovery and missing evidence before routine positive facts. Match the report scope. Unknown is not zero; uncertain facts remain uncertain. Select only IDs from the supplied lists. Actions are already approved by code; do not create actions, numbers or advice. If no relevant item exists, return an empty array. /no_think'
def canonical(value):
    if isinstance(value,float) and value.is_integer(): return int(value)
    if isinstance(value,list): return [canonical(x) for x in value]
    if isinstance(value,dict): return {k:canonical(v) for k,v in value.items()}
    return value
def prompt(payload):
    return '<|im_start|>system\n'+SYSTEM+'\n<|im_end|>\n<|im_start|>user\n'+json.dumps(canonical(payload),sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n'
def grammar(payload):
    def array(name,ids):
        if not ids: return name+' ::= "[" ws "]"'
        values=' | '.join(json.dumps(json.dumps(i)) for i in ids)
        return f'{name}-id ::= {values}\n{name} ::= "[" ws ({name}-id (ws "," ws {name}-id (ws "," ws {name}-id)?)?)? ws "]"'
    return 'root ::= "{" ws "\\\"factIDs\\\"" ws ":" ws facts ws "," ws "\\\"actionIDs\\\"" ws ":" ws actions ws "}" ws\nws ::= [ \\t\\n\\r]*\n'+array('facts',[x['id'] for x in payload['facts']])+'\n'+array('actions',[x['id'] for x in payload['actions']])+'\n'
def project(case, maximum_facts=20):
    """Mirror production's bounded selection, with equal-time manual synthetic facts.
    The production golden XCTest checks prompt/payload/grammar for a common fixture.
    """
    facts=case['sourceFacts'];candidates=sorted(case['sourceActions'],key=lambda x:x['id'])
    if case['scope']=='trend': candidates=[x for x in candidates if x['action']=='reviewNutrition']
    reasons=set(x for a in candidates for x in a['facts'])
    chosen=sorted([x for x in facts if x['id'] in reasons],key=lambda x:x['id'])
    if len(chosen)>maximum_facts: return None
    priorities={'today':['recommendation.availableToday','recovery.feeling'],
      'trend':['weight.smoothed','weight.weeklyChangePercent','diet.completeDays'],
      'recovery':['recovery.feeling','recovery.sleepFeeling','recovery.readiness'],
      'weekly':['diet.completeDays','weight.weeklyChangePercent','recovery.feeling']}[case['scope']]
    if case['scope']=='today' and not any(x['metric']=='recovery.feeling' and x['value'] is not None for x in facts): priorities+=['recommendation.feeling.tired']
    selected=sorted(facts,key=lambda x:(x['id'] not in reasons,x['id']))
    preferred=[]
    for metric in priorities:
        group=[x for x in selected if x['metric']==metric]
        group.sort(key=lambda x:(x['value'] is None,x['value'] if metric=='recovery.readiness' and x['value'] is not None else 0,x['id']))
        if group: preferred.append(group[0])
    belongs=lambda x: case['scope']!='trend' or x['metric'].startswith(('weight.','diet.','energy.','recommendation.goal.'))
    highlights=[x for x in (preferred+[x for x in selected if x not in preferred])[:3] if belongs(x)]
    selected=[x for x in selected if belongs(x)]
    summaries=[]
    for metric in sorted(set(x['metric'] for x in selected)):
        group=sorted([x for x in selected if x['metric']==metric],key=lambda x:(x['value'] if metric=='recovery.readiness' and x['value'] is not None else 0,x['id']))
        summaries.append(group[0])
    for fact in highlights+sorted(summaries,key=lambda x:x['id']):
        if fact not in chosen and len(chosen)<maximum_facts:chosen.append(fact)
    aliases={x['id']:f'f{i}' for i,x in enumerate(chosen)}
    rows=[dict(x,id=aliases[x['id']]) for x in chosen]
    actions=[dict(id=f'a{i}',action=x['action'],facts=[aliases[f] for f in x['facts']]) for i,x in enumerate(candidates)]
    payload=dict(scope=case['scope'],facts=rows,actions=actions,missing=case['missing'])
    return payload,aliases,{x['id']:f'a{i}' for i,x in enumerate(candidates)}

def fixture(identifier,category,scope,rows,actions,required=(),required_actions=(),missing=()):
    facts=[dict(id=f'source-f{i:02}',metric=m,value=v,unit=u,quality=q) for i,(m,v,u,q) in enumerate(rows)]
    acts=[dict(id=f'source-a{i:02}',action=a,facts=[facts[j]['id'] for j in ids]) for i,(a,ids) in enumerate(actions)]
    return dict(id=identifier,category=category,scope=scope,sourceFacts=facts,sourceActions=acts,
        missing=list(missing),requiredSourceFacts=[facts[i]['id'] for i in required],requiredSourceActions=[acts[i]['id'] for i in required_actions])

def cases(split='evaluation'):
    result=[]
    for category in ['normal','sparse','conflict','boundary']:
      for i in range(8 if split=='evaluation' else 2):
        k=i+(0 if split=='evaluation' else 21);scope=['today','trend','recovery','weekly'][i%4]
        if category=='normal':
            if scope=='today':
                rows=[('recommendation.availableToday',1,'count',[]),('recovery.feeling',2,'none',[]),('recommendation.trainingDaysPerWeek',3+k%3,'count',[])]
                actions=[('keepPlan',[0,1,2])]
            elif scope=='trend':
                rows=[('weight.smoothed',70+k/10,'kilograms',[]),('weight.weeklyChangePercent',-0.2-k/100,'percentPerWeek',[]),('diet.completeDays',14,'count',[])]
                actions=[('reviewNutrition',[1,2])]
            elif scope=='recovery':
                rows=[('recovery.feeling',2,'none',[]),('recovery.sleepFeeling',2,'none',[]),('recovery.readiness',80+k,'score',[])]
                actions=[('keepPlan',[0,1,2])]
            else:
                rows=[('diet.completeDays',12+k%3,'count',[]),('weight.weeklyChangePercent',0.1+k/100,'percentPerWeek',[]),('recovery.feeling',2,'none',[])]
                actions=[('reviewNutrition',[0,1])]
            required=[];req_actions=[];missing=[]
        elif category=='sparse':
            rows=[('recovery.feeling',None,'none',['missing']),('diet.completeDays',0,'count',[])] if i%2 else []
            actions=[];required=[];req_actions=[];missing=['sleep','restingHeartRate','heartRateVariability']
        elif category=='conflict':
            # Painful muscles never receive a keep/reduce plan candidate. Only code-approved rest is offered.
            scope=['today','recovery','weekly','recovery'][i%4]
            rows=[('recovery.quads.pain',1,'none',[]),('recovery.readiness',20+k%8,'score',[]),('recommendation.recentWorkingSets',18+k,'count',[]),('recovery.feeling',2,'none',[])]
            actions=[('rest',[0,1,2])];required=[0];req_actions=[0];missing=[]
        else:
            # These values/flags/IDs pass the product's input vocabulary; no invalid injected user text.
            rows=[('recovery.feeling',None,'none',['missing']),('weight.weeklyChangePercent',1e12 if i%3==0 else -0.001,'percentPerWeek',['requiresReview','sourceConflict'])] if i%2 else []
            actions=[];required=[];req_actions=[];missing=['sleep']
        result.append(fixture(f'{split}-{category}-{i}',category,scope,rows,actions,required,req_actions,missing))
    return result

def stress_cases():
    result=[]
    for i,n in enumerate([16,18,19,20,20,20,21,24]):
        # The long metric shape is emitted for alternate plans by TrainingRecommendationRules.
        common=[('recommendation.selectedPlan',1,'count',[]),('recommendation.goal.maintain',1,'count',[]),('recommendation.trainingDaysPerWeek',3,'count',[]),('recommendation.availableToday',1,'count',[]),('recommendation.feeling.tired',0,'count',[]),('recommendation.painOrLimitation',0,'count',[]),('recommendation.systemic.ready',1,'count',[])]
        muscles=['chest','back','shoulders','biceps','triceps','forearms','core','glutes','quads','hamstrings','calves']
        compact=common+[(f'recommendation.readiness.{m}',33.333333333333336,'score',[]) for m in muscles]+[('recommendation.recentWorkingSets',24,'count',[])]
        rows=[]
        for j in range(n):
            metric=(f'recommendation.alternative.12345678-1234-1234-1234-{j:012d}.quads' if i>=3 else f'recommendation.readiness.muscle{j}')
            rows.append((metric,33.333333333333336,'score',['insufficientHistory','estimated'] if i>=4 else []) if i>=3 else compact[j])
        actions=[('swapTrainingDay',list(range(12 if i==3 else n))) for _ in range([3,3,3,3,6,12,3,3][i])]
        result.append(fixture(f'stress-{i}', 'stress','today',rows,actions))
    return result

def compile_runner():
    framework=ROOT/'Packages/TrainoteLlama/Artifacts/llama.xcframework/macos-arm64_x86_64'
    subprocess.run(['swiftc','-O','-F',str(framework),'-framework','llama','-Xlinker','-rpath','-Xlinker',str(framework),str(ROOT/'Trainote/Services/AIReports/LlamaReportRuntime.swift'),str(ROOT/'Scripts/on-device-ai/RuntimeSmoke.swift'),'-o',str(CACHE/'runtime-smoke')],check=True)
def infer_case(case,model,path):
    row=dict(model=model,case=case['id'],category=case['category'],valid=False,requiredFactsSelected=False,requiredActionsSelected=False,attempts=[])
    for budget in [20,12]:
        projection=project(case,budget)
        if projection is None:
            row['attempts'].append(dict(maximumFacts=budget,status='inputBudgetRejected',mandatoryFacts=len(set(x for a in case['sourceActions'] for x in a['facts']))))
            row.update(status='inputBudgetFallback' if budget==20 else 'contextBudgetFallback',reason='required candidate evidence does not fit fact budget')
            break
        payload,aliases,action_aliases=projection
        text=prompt(payload);gbnf=grammar(payload)
        attempt=dict(maximumFacts=budget,promptBytes=len(text.encode()),facts=len(payload['facts']),actions=len(payload['actions']))
        row.update(attempt)
        prompt_file=CACHE/(model+'-'+case['id']+f'-{budget}-prompt.txt');grammar_file=CACHE/(model+'-'+case['id']+f'-{budget}-grammar.gbnf')
        prompt_file.write_text(text);grammar_file.write_text(gbnf)
        tokenized=subprocess.run([str(CACHE/'llama-b11912/llama-tokenize'),'-m',str(path),'--stdin','--ids','--offline'],input=text,capture_output=True,text=True,check=True)
        attempt['promptTokens']=len(json.loads(tokenized.stdout));row['promptTokens']=attempt['promptTokens']
        start=time.monotonic()
        run=subprocess.run([str(CACHE/'runtime-smoke'),str(path),str(prompt_file),str(grammar_file)],capture_output=True,text=True,timeout=120)
        attempt['processWallSeconds']=time.monotonic()-start
        (CACHE/f"{model}-{case['id']}-{budget}.log").write_text(run.stderr)
        try:
            envelope=json.loads(run.stdout);value=json.loads(envelope['output'])
            valid=set(value)=={'factIDs','actionIDs'}
            for key,items in [('factIDs',payload['facts']),('actionIDs',payload['actions'])]:
                ids=value[key];valid=valid and isinstance(ids,list) and len(ids)<=3 and len(set(ids))==len(ids) and set(ids)<=set(x['id'] for x in items)
            required={aliases[x] for x in case['requiredSourceFacts']};required_actions={action_aliases[x] for x in case['requiredSourceActions']}
            row.update(status='generated' if valid else 'invalidOutputFallback',output=value,seconds=envelope['seconds'],valid=bool(valid),requiredFactsSelected=required<=set(value['factIDs']),requiredActionsSelected=required_actions<=set(value['actionIDs']))
            row['selectedMetrics']=[x['metric'] for x in payload['facts'] if x['id'] in value['factIDs']]
            row['scopeWarnings']=[x for x in row['selectedMetrics'] if payload['scope']=='trend' and x.startswith('recovery.')]
            row['selectedActions']=[x['action'] for x in payload['actions'] if x['id'] in value['actionIDs']]
            attempt.update(status=row['status'],seconds=envelope['seconds'])
            row['attempts'].append(attempt)
            break
        except Exception as error:
            context=attempt['promptTokens']+256>2048 and 'inputTooLong' in run.stderr
            status='contextBudgetRejected' if context else 'runtimeFailure'
            attempt.update(status=status,error=run.stderr.splitlines()[-1] if run.stderr else str(error),runtimeExit=run.returncode)
            row['attempts'].append(attempt)
            if context and budget==20: continue
            row.update(status='contextBudgetFallback' if context else 'runtimeFailure',error=attempt['error'],runtimeExit=run.returncode)
            break
    row['retried']=len(row['attempts'])>1
    return row

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--limit',type=int,default=32);parser.add_argument('--models',nargs='+',default=['q4','q8']);parser.add_argument('--stress',action='store_true');args=parser.parse_args()
    CACHE.mkdir(exist_ok=True)
    production=(ROOT/'Trainote/Services/AIReports/OnDeviceReportGenerator.swift').read_text()
    if SYSTEM not in production: raise RuntimeError('Production prompt changed; update evaluation before use')
    if 'static let maximumFacts = 20' not in production or 'maximumFacts: 12' not in production or 'filter(belongsToScope)' not in production: raise RuntimeError('Production projection/retry changed; update evaluation')
    compile_runner()
    fixtures=stress_cases() if args.stress else cases()
    contracts=(ROOT/'Trainote/Services/Analysis/Contracts/AnalysisValues.swift').read_text()
    def enum_values(name):
        body=re.search(r'enum '+name+r'[^\{]*\{([^}]+)\}',contracts).group(1)
        return set(re.sub(r'\bcase\b',',',body).replace('\n','').replace(' ','').split(',')) - {''}
    for case in fixtures:
        assert case['scope'] in enum_values('ReportType')
        for fact in case['sourceFacts']:
            assert fact['unit'] in enum_values('MetricUnit')
            assert set(fact['quality']) <= enum_values('DataQualityFlag')
            assert re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}',fact['metric'])
        assert all(x['action'] in enum_values('RecommendationAction') for x in case['sourceActions'])
    filename='stress-cases.json' if args.stress else 'evaluation-cases.json'
    (ROOT/'Scripts/on-device-ai'/filename).write_text(json.dumps(fixtures,indent=2,ensure_ascii=False)+'\n')
    (ROOT/'Scripts/on-device-ai/tuning-cases.json').write_text(json.dumps(cases('tuning'),indent=2,ensure_ascii=False)+'\n')
    results=[]
    for model in args.models:
      path=ROOT/'Models/qwen3-0.6b-q4_k_m.gguf' if model=='q4' else CACHE/'qwen3-0.6b-q8_0.gguf'
      for case in fixtures[:args.limit]:
        row=infer_case(case,model,path)
        results.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
        output='stress-results.json' if args.stress else 'evaluation-results.json'
        (CACHE/output).write_text(json.dumps(dict(platform=platform.platform(),productionPrompt='on-device-selection-v1',factBudget=20,retryFactBudget=12,trendOptionalPrefixes=['weight.','diet.','energy.','recommendation.goal.'],results=results),indent=2,ensure_ascii=False)+'\n')
    for model in args.models:
        rows=[x for x in results if x['model']==model];times=[x['seconds'] for x in rows if 'seconds' in x]
        print(model,'valid',sum(x['valid'] for x in rows),'/',len(rows),'statuses',{s:sum(x['status']==s for x in rows) for s in set(x['status'] for x in rows)},'median seconds',statistics.median(times) if times else None,flush=True)
if __name__=='__main__':main()
