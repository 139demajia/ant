local constant = {}; constant.__index = constant
local math3d = require "math3d"
-- matrix
constant.mat_identity = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
}

-- quaternion
constant.quat_identity = {0, 0, 0, 1}

-- color
constant.RED    = {1, 0, 0, 1}
constant.GREEN  = {0, 1, 0, 1}
constant.BLUE   = {0, 0, 1, 1}
constant.BLACK  = {0, 0, 0, 1}
constant.WHITE  = {1, 1, 1, 1}
constant.YELLOW = {1, 1, 0, 1}
constant.YELLOW_HALF = {0.5, 0.5, 0, 1}
constant.GRAY_HALF = {0.5, 0.5, 0.5, 1}
constant.GRAY   = {0.8, 0.8, 0.8, 1}
constant.DEFAULT_INTENSITY = 12000

function constant.COLOR(c, intensity)
    intensity = intensity or constant.DEFAULT_INTENSITY
    return {
        c[1] * intensity,
        c[2] * intensity,
        c[3] * intensity,
        c[4],
    }
end

-- value
constant.T_ZERO   = {0, 0, 0, 0}
constant.T_ZERO_PT= {0, 0, 0, 1}

constant.T_ONE    = {1, 1, 1, 0}
constant.T_ONE_PT = {1, 1, 1, 1}

constant.T_XAXIS = {1, 0, 0, 0}
constant.T_NXAXIS = {-1, 0, 0, 0}

constant.T_YAXIS = {0, 1, 0, 0}
constant.T_NYAXIS = {0, -1, 0, 0}

constant.T_ZAXIS = {0, 0, 1, 0}
constant.T_NZAXIS = {0, 0, -1, 0}

constant.W_AXIS = {0, 0, 0, 1}

constant.ZERO    = math3d.ref(math3d.vector(constant.T_ZERO))
constant.ZERO_PT = math3d.ref(math3d.vector(constant.T_ZERO_PT))

constant.ONE    = math3d.ref(math3d.vector(constant.T_ONE))
constant.ONE_PT = math3d.ref(math3d.vector(constant.T_ONE_PT))

constant.XAXIS   = math3d.ref(math3d.vector(constant.T_XAXIS))
constant.NXAXIS  = math3d.ref(math3d.vector(constant.T_NXAXIS))

constant.YAXIS   = math3d.ref(math3d.vector(constant.T_YAXIS))
constant.NYAXIS  = math3d.ref(math3d.vector(constant.T_NYAXIS))

constant.ZAXIS   = math3d.ref(math3d.vector(constant.T_ZAXIS))
constant.NZAXIS  = math3d.ref(math3d.vector(constant.T_NZAXIS))

constant.T_IDENTITY_MAT = constant.mat_identity
constant.IDENTITY_MAT = math3d.ref(math3d.matrix(constant.mat_identity))

constant.T_IDENTITY_QUAT = constant.quat_identity
constant.IDENTITY_QUAT= math3d.ref(math3d.quaternion(constant.quat_identity))

constant.R2L_MAT = math3d.ref(math3d.matrix{s={1.0, 1.0, -1.0}})

return constant