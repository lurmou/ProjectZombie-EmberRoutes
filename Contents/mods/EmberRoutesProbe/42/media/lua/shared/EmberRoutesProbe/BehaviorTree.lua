-- Immutable definitions; each execution owns its own cursor and leaf state.
local Tree={}
local results={Success=true,Failure=true,Running=true}
function Tree.validate(root)
    local visiting,n={},0
    local function visit(node,depth)
        if type(node)~='table' or visiting[node] or depth>8 then return false end
        n=n+1 if n>128 then return false end
        visiting[node]=true
        local kind=node.kind
        if kind=='Action' or kind=='Condition' then
            if type(node.run)~='function' then return false end
        elseif kind=='Sequence' or kind=='Fallback' or kind=='Subtree' then
            if type(node.children)~='table' or #node.children==0 or kind=='Subtree' and #node.children~=1 then return false end
            for _,child in ipairs(node.children) do if not visit(child,depth+1) then return false end end
        else return false end
        return true -- Reusing one node in two positions would alias its cursor.
    end
    return visit(root,1)
end
function Tree.new(root)
    if not Tree.validate(root) then return nil,'TREE_INVALID' end
    return {root=root,memory={},state='Running'}
end
function Tree.tick(tree,context,budget)
    if tree.state~='Running' then return tree.state end
    if tree.stopping then return 'Running' end
    local function run(node)
        if budget.nodes<=0 then return 'Running' end
        budget.nodes=budget.nodes-1
        local m=tree.memory[node] or {index=1}
        tree.memory[node]=m
        if m.result then return m.result end
        if node.kind=='Action' or node.kind=='Condition' then
            local value=node.run(context,m)
            if not results[value] then error('TREE_RESULT_INVALID') end
            if value=='Running' or context.cleanupPending or context.effects=='UNKNOWN' then tree.active=node end
            if value~='Running' then m.result=value end
            return value
        end
        while m.index<=#node.children do
            local value=run(node.children[m.index])
            if value=='Running' then return value end
            -- A leaf explicitly retains its cleanup before any next branch.
            if context.effects=='UNKNOWN' or context.cleanupPending then return 'Running' end
            if node.kind=='Fallback' and value=='Success' then return value end
            if node.kind~='Fallback' and value=='Failure' then return value end
            m.index=m.index+1
        end
        return node.kind=='Fallback' and 'Failure' or 'Success'
    end
    tree.state=run(tree.root) return tree.state
end
function Tree.halt(tree,context)
    tree.stopping=true
    local node=tree.active
    local m=node and tree.memory[node]
    if node and node.halt and not m.halted then
        if node.halt(context,m)~=true then return false end
        m.halted=true
    end
    if context.cleanupPending or context.effects=='UNKNOWN' then return false end
    tree.state='Failure' return true
end
return Tree
