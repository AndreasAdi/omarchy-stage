-- Parked windows keep the primary window's full size, so their previews keep
-- the same aspect ratio.
for workspace = 1, 30 do
  hl.workspace_rule({ workspace = "special:stage-" .. workspace, layout = "monocle" })
end
