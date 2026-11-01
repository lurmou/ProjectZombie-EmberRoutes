-- TooltipAnchor is superseded by TooltipManager.
-- Kept as a backward-compatible proxy so existing callers transparently gain
-- owner registration, screen bounds clamping, and cascading cleanup.
return require 'EmberRoutesProbe/UI/TooltipManager'
