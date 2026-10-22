local Filter=require "EmberRoutesProbe/StorageFilter"
local Policy={}
function Policy.source(role,settings,filter,item)
    if role=="INPUT" and settings.intake then return "INTAKE" end
    if role=="STORAGE" and settings.tidy and not Filter.matches(filter,item) then return "TIDY" end
end
function Policy.specificity(filter,description,item)
    local exact=filter.types[description.fullType]
    if exact~=nil then return exact and 1000 or nil end
    local node=Filter.classify(description,item)
    while node do
        local value=filter.groups[node]
        if value~=nil then return value and Filter.nodes[node].depth+1 or nil end
        node=Filter.nodes[node] and Filter.nodes[node].parent
    end
end
function Policy.better(candidate,best)
    if not best then return true end
    if candidate.specificity~=best.specificity then return candidate.specificity>best.specificity end
    if candidate.distance~=best.distance then return candidate.distance<best.distance end
    return candidate.id<best.id
end
function Policy.index()
    local index={buckets={}}
    function index:add(target)
        for _,field in ipairs({"types","groups"}) do
            for id,allowed in pairs(target.filter[field]) do
                if allowed then
                    local key=field..":"..id local bucket=self.buckets[key] or {}
                    bucket[#bucket+1]=target self.buckets[key]=bucket
                end
            end
        end
    end
    function index:cursor(item)
        local description=Filter.describe(item)
        local keys={"types:"..description.fullType}
        local node=Filter.classify(description,item)
        while node do keys[#keys+1]="groups:"..node node=Filter.nodes[node] and Filter.nodes[node].parent end
        local cursor={key=1,position=1,seen={},description=description}
        function cursor:step()
            local key=keys[self.key]
            if not key then return nil,true end
            local bucket=index.buckets[key] or {}
            local target=bucket[self.position]
            if not target then self.key=self.key+1 self.position=1 return nil,false end
            self.position=self.position+1
            if self.seen[target.id] then return nil,false end
            self.seen[target.id]=true return target,false
        end
        return cursor
    end
    return index
end
return Policy
