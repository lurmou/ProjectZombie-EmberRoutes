-- Engine-independent batch policy. Native action effects are verified separately.
local Batch = {}
Batch.__index = Batch

function Batch.new(steps, emit)
    return setmetatable({ steps = steps, emit = emit, index = 0, state = "RUNNING", records = {} }, Batch)
end

function Batch:record(state, detail)
    local entry = { name = self.steps[self.index].name, state = state, detail = detail or "" }
    self.records[#self.records + 1] = entry
    self.emit(entry.name .. " " .. state .. " " .. entry.detail)
end

function Batch:cancel(reason)
    if self.state ~= "RUNNING" then return end
    self.state = "CANCELLED"
    self.reason = reason
    self.emit("BATCH CANCELLED " .. reason)
    if self.current then self.current.cancel() end
end

function Batch:tick(now)
    if self.state ~= "RUNNING" then return end
    if not self.current then
        self.index = self.index + 1
        local step = self.steps[self.index]
        if not step then
            self.state = "PASSED"
            self.emit("BATCH PASSED cases=" .. #self.records)
            return
        end
        self.startedAt = now
        -- Store before start so errors during native queue insertion remain cancellable.
        self.current = step
        local state, detail = step.start()
        if state == "FAILED" then
            self.state, self.reason = "FAILED", detail
            self:record("FAILED", detail)
            self.current.cancel()
            return
        end
        self.emit(step.name .. " STARTED")
    end
    if now - self.startedAt >= 60000 then
        self.state = "FAILED"
        self:record("FAILED", "TIMEOUT no engine completion")
        self.current.cancel()
        return
    end
    local state, detail = self.current.poll(now)
    if state == "WAIT" then return end
    self:record(state, detail)
    if state == "PASSED" then self.current = nil
    else
        self.state = "FAILED"
        self.current.cancel()
    end
end

return Batch
