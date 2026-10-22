-- Pure, cancellable aggregation. No engine objects; every data visit consumes budget.
local Rollup={}
local methods={}
methods.__index=methods
function Rollup.new(ids,results,maxItems,maxTypes)
    return setmetatable({ids=ids,results=results,maxItems=maxItems,maxTypes=maxTypes,cursor=1,
        seen={},byType={},rows={},counts={loaded=0,unloaded=0,private=0,missing=0,limited=0,items=0,containers=#ids,
            totalCapacity=0,usedWeight=0,fullCount=0,fullContainers={}},
        state="MERGING",types=0,phase="container"},methods)
end
local function fail(self,reason) self.state="ERROR" self.reason=reason end
local function beginSort(self)
    self.phase="sort" self.sortWidth=1 self.left=1 self.buffer={}
end
function methods:step(budget)
    local spent=0
    while spent<budget and self.state=="MERGING" do
        if self.phase=="container" then
            local id=self.ids[self.cursor]
            if not id then beginSort(self)
            else
                local contribution=self.results[id]
                spent=spent+1 self.cursor=self.cursor+1
                if contribution.status=="LOADED" then
                    self.counts.loaded=self.counts.loaded+1
                    self.counts.items=self.counts.items+contribution.count
                    local cap=contribution.capacity or 0
                    local used=contribution.usedWeight or 0
                    self.counts.totalCapacity=(self.counts.totalCapacity or 0)+cap
                    self.counts.usedWeight=(self.counts.usedWeight or 0)+used
                    if cap>0 and used>=cap*0.9 then
                        self.counts.fullCount=(self.counts.fullCount or 0)+1
                        local fc=self.counts.fullContainers
                        if fc and #fc<8 then
                            fc[#fc+1]={name=contribution.customName or contribution.kind or "container",
                                x=contribution.x,y=contribution.y,z=contribution.z,capacity=cap,used=used}
                        end
                    end
                    if self.counts.items>self.maxItems then fail(self,"INVENTORY_SCAN_LIMIT")
                    else
                        self.currentId=id self.current=contribution self.phase="ids"
                        self.iterator,self.iterState,self.key=pairs(contribution.ids)
                    end
                elseif contribution.status=="CONTAINER_UNLOADED" then self.counts.unloaded=self.counts.unloaded+1
                elseif contribution.status=="CONTAINER_PRIVATE" then self.counts.private=self.counts.private+1
                elseif contribution.status=="INVENTORY_SCAN_LIMIT" then self.counts.limited=self.counts.limited+1
                else self.counts.missing=self.counts.missing+1 end
            end
        elseif self.phase=="ids" then
            local id=self.iterator(self.iterState,self.key)
            self.key=id
            if id==nil then
                self.phase="types" self.iterator,self.iterState,self.key=pairs(self.current.types)
            else
                spent=spent+1
                if self.seen[id] then fail(self,"ITEM_ID_DUPLICATED") else self.seen[id]=true end
            end
        elseif self.phase=="types" then
            local fullType,value=self.iterator(self.iterState,self.key)
            self.key=fullType
            if fullType==nil then self.phase="container" self.current=nil
            else
                spent=spent+1
                local group=self.byType[fullType]
                if not group then
                    self.types=self.types+1
                    if self.types>self.maxTypes then fail(self,"INVENTORY_SCAN_LIMIT") break end
                    group={fullType=fullType,node=value.node,count=0,sources={}}
                    self.byType[fullType]=group self.rows[#self.rows+1]=group
                end
                local c=self.current
                group.count=group.count+value.count
                group.sources[#group.sources+1]={id=self.currentId,count=value.count,x=c.x,y=c.y,z=c.z,
                    kind=c.kind,displayType=c.displayType,customName=c.customName}
            end
        else
            -- Bottom-up merge sort: each emitted reference is one budget unit.
            local n=#self.rows
            if self.sortWidth>=n then self.state="READY"
            elseif self.left>n then
                self.rows,self.buffer=self.buffer,self.rows
                self.sortWidth=self.sortWidth*2 self.left=1
            else
                if not self.merge then
                    self.merge={i=self.left,j=self.left+self.sortWidth,k=self.left,
                        middle=math.min(self.left+self.sortWidth-1,n),right=math.min(self.left+self.sortWidth*2-1,n)}
                end
                local m=self.merge
                if m.i<=m.middle and (m.j>m.right or self.rows[m.i].fullType<=self.rows[m.j].fullType) then
                    self.buffer[m.k]=self.rows[m.i] m.i=m.i+1
                else self.buffer[m.k]=self.rows[m.j] m.j=m.j+1 end
                m.k=m.k+1 spent=spent+1
                if m.k>m.right then self.merge=nil self.left=self.left+self.sortWidth*2 end
            end
        end
    end
    return spent,self.state,self.reason
end
return Rollup
