-- PZ Kahlua strings are UTF-16 Java strings; desktop Lua uses UTF-8 bytes.
-- Do not use UTF-8 byte patterns against translated Kahlua strings.
local Text={}
local unicodeStrings=#"\228\187\147"==1
local function nextCharacter(value,index)
    local code=value:byte(index)
    local length=1
    if unicodeStrings then
        if code>=55296 and code<=56319 then length=2 end
    elseif code>=240 then length=4
    elseif code>=224 then length=3
    elseif code>=192 then length=2 end
    return value:sub(index,index+length-1),index+length
end
function Text.wrap(value,width,font)
    local lines,line={},""
    local manager=getTextManager()
    local index=1
    while index<=#value do
        local char
        char,index=nextCharacter(value,index)
        if char=="\n" then
            lines[#lines+1]=line line=""
        elseif char~="\r" then
            local candidate=line..char
            if line~="" and manager:MeasureStringX(font,candidate)>math.max(1,width) then
                lines[#lines+1]=line line=char
            else line=candidate end
        end
    end
    if line~="" or #lines==0 then lines[#lines+1]=line end
    return lines
end
function Text.wrapLimited(value,width,font,maxLines)
    local lines=Text.wrap(value,width,font)
    if #lines<=maxLines then return lines end
    while #lines>maxLines do table.remove(lines) end
    local manager=getTextManager()
    local suffix="..."
    while #suffix>0 and manager:MeasureStringX(font,suffix)>width do suffix=suffix:sub(1,-2) end
    local clipped,index="",1
    local last=lines[maxLines]
    while index<=#last do
        local char
        char,index=nextCharacter(last,index)
        if manager:MeasureStringX(font,clipped..char..suffix)>width then break end
        clipped=clipped..char
    end
    lines[maxLines]=clipped..suffix
    return lines
end
return Text
