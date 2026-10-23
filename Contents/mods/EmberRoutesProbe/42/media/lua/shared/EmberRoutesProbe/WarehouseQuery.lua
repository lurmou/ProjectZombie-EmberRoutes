local Filter=require "EmberRoutesProbe/StorageFilter"
local Query={PAGE_SIZE=60,SORTS={"default","nameAsc","nameDesc","quantityDesc","quantityAsc"}}
local methods={}
methods.__index=methods
function Query.root(id)
    while Filter.nodes[id] and Filter.nodes[id].parent do id=Filter.nodes[id].parent end
    return id
end
local function compare(mode,a,b)
    local ap=(a.pinned==true)
    local bp=(b.pinned==true)
    if ap~=bp then return ap end
    if mode=="quantityAsc" or mode=="quantityDesc" then
        local ak=not a.pending and type(a.count)=="number"
        local bk=not b.pending and type(b.count)=="number"
        if ak~=bk then return ak end -- Unknown is neither zero nor available stock.
        if ak and a.count~=b.count then
            if mode=="quantityAsc" then return a.count<b.count end
            return a.count>b.count
        end
    elseif a.label~=b.label then
        if mode=="nameDesc" then return a.label>b.label end
        return a.label<b.label
    end
    return a.fullType<b.fullType
end
function Query.new() return setmetatable({},methods) end
-- Installed Kahlua table.sort uses recursive quicksort and can overflow on
-- ordered 2048-type inputs. Bottom-up merge sort has bounded stack/work here.
local function sortRows(rows,mode)
    local size,width,buffer=#rows,1,{}
    while width<size do
        for first=1,size,width*2 do
            local middle,last=math.min(first+width-1,size),math.min(first+width*2-1,size)
            local left,right=first,middle+1
            for output=first,last do
                if left<=middle and (right>last or not compare(mode,rows[right],rows[left])) then
                    buffer[output]=rows[left] left=left+1
                else buffer[output]=rows[right] right=right+1 end
            end
        end
        rows,buffer=buffer,rows width=width*2
    end
    return rows
end
-- Pure, per-view cache. No engine calls; cached rows are never mutated.
function methods:page(rows,search,category,page,sort,anchor)
    search=string.lower(search or "")
    sort=sort or "default"
    if self.rows~=rows or self.search~=search or self.category~=category or self.sort~=sort then
        local matching={}
        for _,row in ipairs(rows) do
            if (not category or Query.root(row.node)==category)
                    and (search=="" or row.searchKey:find(search,1,true)) then matching[#matching+1]=row end
        end
        if sort~="default" then
            matching=sortRows(matching,sort)
        else
            local pinnedList,normalList={},{}
            for _,row in ipairs(matching) do
                if row.pinned then pinnedList[#pinnedList+1]=row else normalList[#normalList+1]=row end
            end
            if #pinnedList>0 then
                matching={}
                for _,row in ipairs(pinnedList) do matching[#matching+1]=row end
                for _,row in ipairs(normalList) do matching[#matching+1]=row end
            end
        end
        self.rows,self.search,self.category,self.sort=rows,search,category,sort
        self.matching,self.positions=matching,{}
        for i,row in ipairs(matching) do self.positions[row.fullType]=i end
    end
    local pages=math.max(1,math.ceil(#self.matching/Query.PAGE_SIZE))
    if anchor and self.positions[anchor] then page=math.ceil(self.positions[anchor]/Query.PAGE_SIZE) end
    page=math.max(1,math.min(page or 1,pages))
    local result={}
    for i=(page-1)*Query.PAGE_SIZE+1,math.min(page*Query.PAGE_SIZE,#self.matching) do result[#result+1]=self.matching[i] end
    return result,page,pages,#self.matching
end
-- Compatibility for one-shot consumers; interactive views own a Query.new().
function Query.page(rows,search,category,page,sort,anchor)
    return Query.new():page(rows,search,category,page,sort,anchor)
end
return Query
