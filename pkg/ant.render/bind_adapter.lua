local bgfx = require "bgfx"

if not bgfx.adapter then
    bgfx.adapter = true
    local math3d_adapter = import_package "ant.math.adapter"
    bgfx.set_transform = math3d_adapter.matrix(bgfx.set_transform, 1, 1)
    bgfx.set_view_transform = math3d_adapter.matrix(bgfx.set_view_transform, 2, 2)
    bgfx.set_uniform = math3d_adapter.variant(bgfx.set_uniform_matrix, bgfx.set_uniform_vector, 2)
    bgfx.set_uniform_command = math3d_adapter.variant(bgfx.set_uniform_matrix_command, bgfx.set_uniform_vector_command, 2)
    local idb = bgfx.instance_buffer_metatable()
    idb.pack = math3d_adapter.format(idb.pack, idb.format, 3)
    idb.__call = idb.pack
end
