local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local md={}
local actor={getModData=function() return md end}
local P=require 'EmberRoutesProbe/Settlement/SquadPreferences'
local p=P.new(actor)
check(md.EmberRoutesSquadHUD==nil and p.writable,'opening preferences never writes defaults')
check(p:setPosition(800,600,1000,800),'store normalized dock position')
local q=P.new(actor) local x,y=q:position(300,200,500,400)
check(x==200 and y==200,'restored position clamps to a smaller screen')
check(q:setScale('scale',1.4) and q:setScale('buttonScale',0.85),'independent supported scale choices')
check(not q:setScale('scale',7) and not q:setScale('unknown',1),'invalid scales never admitted')
local rows={{id='a',slot=2},{id='b',slot=0},{id='c',slot=1}}
check(q:reorder(rows,'a',3),'reorder visible stable IDs')
check(q:ordered(rows)[3].id=='a' and rows[1].id=='a' and rows[1].slot==2,'reorder neither mutates source rows nor formation slots')
check(P.new(actor):ordered(rows)[3].id=='a','display order restores')
local reduced=q:ordered({rows[1],rows[3]})
check(#reduced==2 and reduced[1].id=='c' and reduced[2].id=='a','missing members pruned only from display projection')
check(not q:reorder(rows,'missing',1),'absent IDs cannot be inserted')
check(q:setCallsign('a','  Scout<>\n  ') and q.value.callsigns.a=='Scout','aliases strip control and tooltip markup')
check(q:setCallsign('b','侦察员') and P.new(actor).value.callsigns.b=='侦察员','Chinese callsign survives preferences restore')
check(not q:setCallsign('b',string.rep('x',97)),'bounded alias payload')
check(q:resetLayout() and #q.value.order==0 and q.value.scale==1 and q.value.callsigns.a=='Scout','reset layout retains callsigns')
check(q:setCallsign('a','') and q.value.callsigns.a==nil,'empty callsign clears only the alias')
local foreign={format=77,precious='retained'} md.EmberRoutesSquadHUD=foreign
local unsupported=P.new(actor)
check(not unsupported.writable and not unsupported:setScale('scale',1.2),'unknown format explicitly read-only')
check(md.EmberRoutesSquadHUD==foreign and foreign.precious=='retained','unsupported preferences preserved without migration or reset')
md.EmberRoutesSquadHUD={format=1,scale=1,buttonScale=1,order={'a','a'},callsigns={}}
check(not P.new(actor).writable,'duplicate saved order rejected without rewriting')
print('PASS '..checks..' cosmetic preferences checks; native save/disk NOT RUN')
