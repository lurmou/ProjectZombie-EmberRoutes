-- Process-local domain metadata. Definitions live in BuiltinJobContracts;
-- this module never loads a client module or owns business state.
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
local R={}
local domains,providers,categories={},{},{}
local sealed=false
function R.register(kind,contract,meta)
    assert(not sealed,'DOMAIN_REGISTRY_SEALED')
    assert(type(kind)=='string' and kind~='' and not domains[kind],'DOMAIN_INVALID_OR_DUPLICATE')
    meta=meta or {}
    assert(type(meta)=='table','DOMAIN_METADATA_INVALID')
    for key in pairs(meta) do assert(key=='providers' or key=='retirement','DOMAIN_METADATA_INVALID') end
    if meta.retirement then assert(type(meta.retirement)=='string' and string.match(meta.retirement,'^EmberRoutesProbe/[%w_/]+$'),'RETIREMENT_MODULE_INVALID') end
    if meta.providers then assert(type(meta.providers)=='table','PROVIDERS_INVALID') end
    local size=0
    for key in pairs(meta.providers or {}) do
        assert(type(key)=='number' and key==math.floor(key) and key>0,'PROVIDERS_INVALID')
        size=size+1
    end
    for i=1,size do assert(meta.providers[i]~=nil,'PROVIDERS_INVALID') end
    local pending,pendingCategories={},{}
    for _,p in ipairs(meta.providers or {}) do
        assert(type(p)=='table','PROVIDER_METADATA_INVALID')
        for key in pairs(p) do assert(key=='order' or key=='category' or key=='module','PROVIDER_METADATA_INVALID') end
        assert(type(p.order)=='number' and p.order==math.floor(p.order) and p.order>0 and not providers[p.order] and not pending[p.order],'PROVIDER_ORDER_INVALID')
        assert(type(p.category)=='string' and p.category~='' and not categories[p.category] and not pendingCategories[p.category],'PROVIDER_CATEGORY_INVALID')
        assert(type(p.module)=='string' and string.match(p.module,'^EmberRoutesProbe/[%w_/]+$'),'PROVIDER_MODULE_INVALID')
        pendingCategories[p.category]=true
        pending[p.order]={category=p.category,providerType=contract and kind or nil,module=p.module}
    end
    if contract then assert(Contracts.register(kind,contract)) end
    for order,p in pairs(pending) do providers[order]=p categories[p.category]=true end
    domains[kind]={retirement=meta.retirement}
end
function R.providerEntries()
    local count=0 for _ in pairs(providers) do count=count+1 end
    local copy={}
    for i=1,count do
        local e=assert(providers[i],'PROVIDER_ORDER_GAP')
        copy[i]={category=e.category,providerType=e.providerType,module=e.module}
    end
    return copy
end
function R.seal()
    assert(not sealed,'DOMAIN_REGISTRY_SEALED')
    R.providerEntries() -- Reject gaps before any client loader can consume paths.
    sealed=true
end
function R.retirementModule(kind)
    local domain=domains[kind]
    return domain and domain.retirement or nil
end
return R
