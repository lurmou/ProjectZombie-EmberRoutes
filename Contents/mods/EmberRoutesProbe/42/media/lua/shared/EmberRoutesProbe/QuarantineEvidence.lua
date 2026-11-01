-- Quarantine diagnostic facts only. Not a Job/Cooking serializer or an authority.
local E={MAX_DEPTH=16,MAX_NODES=8192,MAX_TABLE_ENTRIES=2048,MAX_ENTRIES=8192,
    MAX_STRING_LENGTH=16384,MAX_TOTAL_STRING_LENGTH=65536,MAX_ERRORS=32}

local function finite(v) return v==v and math.abs(v)<math.huge end
local function token(t)
    -- Live and released Claims tokens keep this protocol shape. Evidence must
    -- name their scalar identities rather than embed the runtime object.
    return rawget(t,'taskId')~=nil and type(rawget(t,'resources'))=='table'
	and (rawget(t,'claimId')~=nil or rawget(t,'generation')~=nil)
	or rawget(t,'kind')=='SYSTEM_QUARANTINE'
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
return E
