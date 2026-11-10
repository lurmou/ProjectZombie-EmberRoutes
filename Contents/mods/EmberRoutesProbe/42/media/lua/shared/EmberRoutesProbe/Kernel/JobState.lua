-- Single authority for the JobStore job state vocabulary.
-- Callers ask isTerminal(state); they never compare a job state string
-- themselves and never read the tables below. Adding a state touches this
-- file only: extend STATES, and TERMINAL when the new state ends a job.
-- Order, record and receipt states are separate machines and stay out.
local JobState={}
local STATES={PREPARING=true,RUNNING=true,STOPPING=true,SUSPENDED=true,SETTLING=true,
    DONE=true,CANCELLED=true,RECONCILE_REQUIRED=true}
local TERMINAL={DONE=true,CANCELLED=true}
-- Any value outside the vocabulary is not terminal: an unknown or missing
-- state must never be mistaken for a finished job.
function JobState.isTerminal(state) return type(state)=='string' and TERMINAL[state]==true end
function JobState.isValid(state) return type(state)=='string' and STATES[state]==true end
return JobState
