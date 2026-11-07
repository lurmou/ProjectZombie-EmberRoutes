-- Pure display projection of detached personnel details.
local Theme=require 'EmberRoutesProbe/UI/Theme'
local P={}
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end
function P.rows(value,mode,page)
    local rows={}
    if not value then return (mode=='skills' or mode=='knowledge') and {{text=text('detailsUnknown')}} or {} end

    if mode=='skills' then
        for _,skill in ipairs(value.skills or {}) do
            rows[#rows+1]={text=text('skillLevel',skill.name,skill.level),fraction=skill.level/10}
            if skill.multiplier and skill.multiplier>1 then rows[#rows+1]={text=text('xpMultiplier',skill.multiplier)} end
        end
        return rows
    elseif mode=='knowledge' then
        local count=value.knownCount
        rows[#rows+1]={text=count and text('knownCount',count) or text('detailsUnknown')}
        local start=((page or 1)-1)*32+1
        for i=start,math.min(start+31,#(value.knowledge or {})) do rows[#rows+1]={text=value.knowledge[i]} end
        rows[#rows+1]={text=text('knowledgePage',page or 1,math.max(1,math.ceil(#(value.knowledge or {})/32)))}
        return rows
    end

    if #(value.tools or {})>0 then
        rows[#rows+1]={text=getText('IGUI_EmberRoutesProbe_Monitor_personnelTools',#value.tools),color=Theme.accent}
        for _,asset in ipairs(value.tools) do
            rows[#rows+1]={isAssetRow=true,fullType=asset.fullType,
                name=asset.fullType and getItemNameFromFullType(asset.fullType) or asset.displayName,
                status=asset.custodyState,statusText=asset.statusText,count=1}
            if asset.exceptional then rows[#rows+1]={text=asset.reasonText,color=Theme.status.ERROR} end
        end
    end
    -- Mental warning only if severe
    if value.mood and (value.mood.UNHAPPINESS or 0)>=80 and (value.mood.STRESS or 0)>=0.8 then
        rows[#rows+1]={text=text('mentalWarning'),color=Theme.status.ERROR}
    end

    -- Study / Self-care progress if actively occurring
    local study=value.study
    if study and study.step~='IDLE' then
        rows[#rows+1]={text=text('studyState',text('study_'..study.step)),color=Theme.accent}
        if study.book then rows[#rows+1]={text=text('studyBook',getItemNameFromFullType and getItemNameFromFullType(study.book) or study.book),fullType=study.book} end
        if study.pages and study.total and study.total>0 then
            rows[#rows+1]={text=text('studyPages',study.pages,study.total),fraction=study.pages/study.total,compact=true,meterLabel=study.pages..'/'..study.total}
        end
    end

    if #rows==0 and (mode=='skills' or mode=='knowledge') then rows[1]={text=text('detailsUnknown')} end
    return rows
end

return P
