-- Quarantine diagnostic facts only. Not a Job/Cooking serializer or an authority.
local E={MAX_DEPTH=16,MAX_NODES=8192,MAX_TABLE_ENTRIES=2048,MAX_ENTRIES=8192,MAX_EVENTS=64,
    MAX_STRING_LENGTH=16384,MAX_TOTAL_STRING_LENGTH=65536,MAX_ERRORS=32}

local function finite(v) return v==v and math.abs(v)<math.huge end
local function token(t)
    -- Live and released Claims tokens keep this protocol shape. Evidence must
    -- name their scalar identities rather than embed the runtime object.
    return rawget(t,'taskId')~=nil and type(rawget(t,'resources'))=='table'
	and (rawget(t,'claimId')~=nil or rawget(t,'generation')~=nil)
	or rawget(t,'kind')=='SYSTEM_QUARANTINE' and rawget(t,'ownerId')=='SYSTEM_QUARANTINE'
	and rawget(t,'taskId')=='SYSTEM_QUARANTINE' and type(rawget(t,'resource'))=='string'
end
local function location(path,key)
    local kind=type(key)
    if kind=='string' then return string.sub(path..'.'..string.sub(key,1,64),1,512) end
    if kind=='number' then return string.sub(path..'['..tostring(key)..']',1,512) end
    return string.sub(path..'['..kind..']',1,512)
end

-- Returns a partial detached fact tree plus bounded, serializable diagnostics.
-- String lengths use the target Lua runtime's # operator, like existing fact bounds.
-- No exception/handle is stored and no metamethod is invoked. String and finite
-- number keys match the installed Kahlua table codec; boolean keys do not.
function E.snapshot(value,previousReport)
    local report={format=1,complete=true,errors={},omittedErrors=0,nodes=0,entries=0,stringLength=0}
    local ancestors={}
    local exhausted=false
    local function reject(path,reason)
	report.complete=false
	if #report.errors<E.MAX_ERRORS then
	    report.errors[#report.errors+1]={path=path,reason=reason}
	else report.omittedErrors=report.omittedErrors+1 end
    end
    local function stringFact(v,path)
	if #v>E.MAX_STRING_LENGTH then reject(path,'STRING_LENGTH_LIMIT') return false end
	if report.stringLength+#v>E.MAX_TOTAL_STRING_LENGTH then reject(path,'TOTAL_STRING_LENGTH_LIMIT') return false end
	report.stringLength=report.stringLength+#v
	return true
    end
    local function copy(v,path,depth)
	report.nodes=report.nodes+1
	if report.nodes>E.MAX_NODES then reject(path,'NODE_LIMIT') exhausted=true return nil end
	if depth>E.MAX_DEPTH then reject(path,'DEPTH_LIMIT') return nil end
	local kind=type(v)
	if kind=='nil' or kind=='boolean' then return v end
	if kind=='string' then if stringFact(v,path) then return v end return nil end
	if kind=='number' then
	    if finite(v) then return v end
	    reject(path,'NONFINITE_NUMBER') return nil
	end
	if kind~='table' then reject(path,'INVALID_TYPE:'..kind) return nil end
	if getmetatable(v)~=nil then reject(path,'METATABLE') return nil end
	if token(v) then reject(path,'RUNTIME_TOKEN') return nil end
	if ancestors[v] then reject(path,'CYCLE') return nil end
	ancestors[v]=true
	local result,count={},0
	for key,item in pairs(v) do
	    if exhausted then break end
	    count=count+1
	    if count>E.MAX_TABLE_ENTRIES then reject(path,'TABLE_ENTRY_LIMIT') break end
	    report.entries=report.entries+1
	    if report.entries>E.MAX_ENTRIES then reject(path,'ENTRY_LIMIT') exhausted=true break end
	    local childPath=location(path,key)
	    local keyKind=type(key)
	    local validKey=keyKind=='string' or keyKind=='number' and finite(key)
	    if not validKey then reject(childPath,'INVALID_KEY')
	    elseif keyKind~='string' or stringFact(key,childPath) then
		result[key]=copy(item,childPath,depth+1)
	    end
	end
	ancestors[v]=nil
	return result
    end
    local facts=copy(value,'$',0)
    -- A second snapshot must never turn a previously incomplete partial tree
    -- into complete evidence just because its unsafe nodes have been removed.
    if previousReport~=nil then
	local previous,valid=E.snapshot(previousReport)
	if not valid.complete or type(previous)~='table' or previous.format~=1
	    or type(previous.complete)~='boolean' then
	    reject('$report','INVALID_REPORT')
	elseif not previous.complete then
	    report.complete=false
	    report.recordedIncomplete=true
	    if #report.errors==0 and type(previous.errors)=='table' then
		for i=1,math.min(#previous.errors,E.MAX_ERRORS) do report.errors[i]=previous.errors[i] end
		report.omittedErrors=previous.omittedErrors or 0
	    end
	end
    end
    return facts,report
end
local function eventReport() return {format=1,complete=true,errors={},omittedErrors=0} end
local function eventError(report,path,reason)
    report.complete=false
    if #report.errors<E.MAX_ERRORS then
	report.errors[#report.errors+1]={path=string.sub(path,1,512),reason=reason}
    else report.omittedErrors=math.min(9007199254740991,report.omittedErrors+1) end
end
local function include(report,part,path)
    if part.complete then return end
    report.complete=false
    for _,err in ipairs(part.errors or {}) do
	if type(err)=='table' and type(err.path)=='string' and type(err.reason)=='string' then
	    eventError(report,path..err.path,err.reason)
	else eventError(report,path,'INVALID_REPORT') end
    end
    if type(part.omittedErrors)=='number' and finite(part.omittedErrors) and part.omittedErrors>0 then
	report.omittedErrors=math.min(9007199254740991,report.omittedErrors+part.omittedErrors)
    end
end
local eventFields={{'evidence','report'},{'interruptedEvidence','interruptedReport'},{'pendingEvidence','pendingReport'}}

-- The event envelope is fixed-depth metadata. EACH payload gets the original
-- snapshot budgets, so adding legal events never reduces its legal depth.
function E.snapshotEvents(history)
    local book={format=1,events={},incomplete=false,omittedEvents=0}
    local report=eventReport()
    if history==nil then return book,report end
    if type(history)~='table' or getmetatable(history)~=nil or history.format~=1
	or type(history.events)~='table' or getmetatable(history.events)~=nil then
	eventError(report,'$events','EVENT_HISTORY_INVALID') book.incomplete=true return book,report
    end
    local omitted=history.omittedEvents
    if type(omitted)~='number' or not finite(omitted) or omitted<0 or omitted~=math.floor(omitted)
	or type(history.incomplete)~='boolean' then
	eventError(report,'$events','EVENT_HISTORY_INVALID')
    else book.omittedEvents=omitted end
    local size,count=#history.events,0
    for key in pairs(history.events) do
	count=count+1
	if count>E.MAX_EVENTS then eventError(report,'$events','EVENT_HISTORY_LIMIT') break end
	if type(key)~='number' or key~=math.floor(key) or key<1 or key>size or key>E.MAX_EVENTS then
	    eventError(report,'$events','EVENT_HISTORY_INVALID')
	end
    end
    if count~=size or size>E.MAX_EVENTS then eventError(report,'$events','EVENT_HISTORY_INVALID') end
    for i=1,math.min(size,E.MAX_EVENTS) do
	local source=history.events[i]
	if type(source)~='table' or getmetatable(source)~=nil then
	    eventError(report,'$events['..i..']','EVENT_INVALID')
	else
	    local entry={}
	    for _,pair in ipairs(eventFields) do
		local field,meta=pair[1],pair[2]
		if field=='evidence' or source[field]~=nil or source[meta]~=nil then
		    local facts,details=E.snapshot(source[field],source[meta])
		    if field=='evidence' and source[meta]==nil then eventError(details,'$report','INVALID_REPORT') end
		    entry[field],entry[meta]=facts,details
		    include(report,details,'$events['..i..'].'..field)
		end
	    end
	    book.events[#book.events+1]=entry
	end
    end
    if book.omittedEvents>0 then eventError(report,'$events','EVENT_HISTORY_LIMIT') end
    if history.incomplete and report.complete then eventError(report,'$events','PRIOR_EVIDENCE_INCOMPLETE') end
    book.incomplete=not report.complete
    return book,report
end
function E.appendEvent(history,value,previousReport)
    local book,report=E.snapshotEvents(history)
    local facts,details=E.snapshot(value,previousReport)
    include(report,details,'$events['..(#book.events+1)..'].evidence')
    if #book.events<E.MAX_EVENTS then
	book.events[#book.events+1]={evidence=facts,report=details}
    else
	book.omittedEvents=math.min(9007199254740991,book.omittedEvents+1)
	eventError(report,'$events','EVENT_HISTORY_LIMIT')
    end
    book.incomplete=not report.complete
    return book,report,facts
end

-- Readers must not run one generic depth budget over the event envelope and
-- its payloads. Header facts and each evidence payload remain detached/bounded.
function E.snapshotRecord(record)
    if type(record)~='table' or getmetatable(record)~=nil then return E.snapshot(record) end
    local payloads={evidence=true,resolvingEvidence=true,interruptedEvidence=true,evidenceEvents=true}
    local header,count={},0
    for key,value in pairs(record) do
	count=count+1 if count>E.MAX_TABLE_ENTRIES then break end
	if not payloads[key] then header[key]=value end
    end
    local view,report=E.snapshot(header)
    if count>E.MAX_TABLE_ENTRIES then eventError(report,'$record','TABLE_ENTRY_LIMIT') end
    for _,field in ipairs({'evidence','resolvingEvidence','interruptedEvidence'}) do
	if record[field]~=nil or record[field..'Report']~=nil then
	    local facts,details=E.snapshot(record[field],record[field..'Report'])
	    view[field]=facts include(report,details,'$record.'..field)
	end
    end
    if record.evidenceEvents~=nil then
	local book,details=E.snapshotEvents(record.evidenceEvents)
	view.evidenceEvents=book include(report,details,'$record.evidenceEvents')
    end
    return view,report
end
return E
