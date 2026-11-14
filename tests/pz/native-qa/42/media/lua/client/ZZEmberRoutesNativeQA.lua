if EmberRoutesQaJava then
    local Session=require 'EmberRoutesQA/Session'
    Events.OnMainMenuEnter.Add(Session.onMenu)
    Events.OnGameStart.Add(Session.onGameStart)
    Events.OnTick.Add(Session.tick)
    Events.OnResolutionChange.Add(Session.resize)
end
