local imgui         = require "imgui_wrap"
local widget        = imgui.widget
local flags         = imgui.flags
local windows       = imgui.windows 
local util          = imgui.util
local cursor        = imgui.cursor
local enum          = imgui.enum
local IO            = imgui.IO
local mult_widget   = require "controls.mult_widget"

local ColumnsID = "PropertyValueColunms"

local cur_tbl = nil

local function BeginProperty(tbl)
    assert(not cur_tbl,"Program Error")
    cur_tbl = tbl
    cur_tbl.column2_last_change = cur_tbl.column2_last_change or false
    cur_tbl.column2_cur_change = false
end

local function EndProperty()
    cur_tbl.column2_last_change = cur_tbl.column2_cur_change
    cur_tbl = nil
end

local function BeginColunms()
    cursor.Columns(2,ColumnsID,true)
    windows.PushStyleColor(enum.StyleCol.Separator,1,1,1,0.01)
    if cur_tbl.column2_last_change then
        cursor.SetColumnOffset(2,cur_tbl.offset_2)
    end
end

local function EndColunms()
    if (not cur_tbl.column2_last_change) and (not cur_tbl.column2_cur_change) then
        local new_offset = cursor.GetColumnOffset(2)
        cur_tbl.column2_cur_change = cur_tbl.offset_2 and (new_offset ~= cur_tbl.offset_2)
        cur_tbl.offset_2 = new_offset
        cur_tbl.dirty = true
    end
    cursor.Columns(1)
    windows.PopStyleColor()
end


local function real(ui_cache,name,value,cfg)
    local vt = ui_cache[name]
    if not vt then
        local speed = cfg.RealDragSpeed or 1.0
        vt = {value,speed=speed}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = widget.DragFloat("###"..name,vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,vt[1],active
end

local function mult_real(ui_cache,name,values,cfg)
    local vt = ui_cache[name]
    if not vt then
        local speed = cfg.RealDragSpeed or 1.0
        vt = {speed=speed}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change,val = mult_widget.DragFloat("###"..name,values,vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,val,active
end

local function boolean(ui_cache,name,value)
    local vt = ui_cache[name]
    if not vt then
        vt = {value}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = widget.Checkbox("###"..name, vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,vt[1],active
end

local function mult_boolean(ui_cache,name,values)
    local vt = ui_cache[name]
    if not vt then
        vt = {}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change,value = mult_widget.Checkbox("###"..name,values,vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,value,active
end

local function tag(ui_cache,name,value)
    local vt = ui_cache[name]
    if not vt then
        vt = {value}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = widget.Checkbox("###"..name, vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,vt[1] or nil,active
end

local function mult_tag(ui_cache,name,values)
    local vt = ui_cache[name]
    if not vt then
        vt = {}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change,value = mult_widget.Checkbox("###"..name,values,vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,value or nil,active
end

local String = string
local function string(ui_cache,name,value)
    local vt = ui_cache[name]
    if not vt then
        vt = {text=value}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = widget.InputText("###"..name, vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,tostring(vt.text),active
end

local function mult_string(ui_cache,name,values)
    widget.Text(String.format("Component %s:To Be Implemented",name))
    return false
end

local function int(ui_cache,name,value)
    local vt = ui_cache[name]
    if not vt then
        vt = {value}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = widget.DragInt("###"..name,vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,vt[1],active
end

local function mult_int(ui_cache,name,values)
    local vt = ui_cache[name]
    if not vt then
        vt = {}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = mult_widget.DragInt("###"..name,values,vt)
    local active = util.IsItemActive()
    EndColunms()
    return change,vt[1],active
end

local function _fix_size(origin,num)
    local new = {}
    for i = 1,num do
        new[i] = origin[i]
    end
    return new
end

local function _fill_size(new,origin,num)
    --todo:may should not use origin
    for i = 1,num do
        origin[i] = new[i]
    end
    return origin
end

local function vector(ui_cache,name,value,cfg)
    local vt = ui_cache[name]
    if not vt then
        local speed = cfg.RealDragSpeed or 1.0
        if cfg.ArrayChangeSize >0 then
            vt = _fix_size(value,cfg.ArrayChangeSize)
            vt.speed = speed
        else
            vt = {value[1],value[2],value[3],value[4],speed=speed}
        end
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn() 
    cursor.SetNextItemWidth(-1)
    local change = widget.DragFloat("###DragFloat"..name,vt)
    local active = util.IsItemActive()
    EndColunms()
    if change then
        if cfg.ArrayChangeSize > 0 then
            value = _fill_size(vt,value,cfg.ArrayChangeSize)
            return change,value,active
        else
            return change,{vt[1],vt[2],vt[3],vt[4]},active
        end

    else
        return change,nil,active
    end
end

local function mult_vector(ui_cache,name,values,cfg)
    local vt = ui_cache[name]
    if not vt then
        local speed = cfg.RealDragSpeed or 1.0
        vt = {speed=speed}
        ui_cache[name] = vt
    end
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    local change = mult_widget.DragVector("###DragFloat"..name,values,vt,cfg.ArrayChangeSize)
    local active = util.IsItemActive()
    EndColunms()
    return change,values,active
end

local function matrix(ui_cache,name,value)
    local vt = ui_cache[name]
    if not vt then
        vt = {{},{},{},{}}
        ui_cache[name] = vt
        for i = 1,16 do
            vt[i//4+1][i%4] = value[i]
        end
    end
    BeginColunms()
    cursor.NextColumn()
    local change = false
    local active = false
    if widget.TreeNode(name) then
        for i = 1,4 do
            local this_vt = vt[i]
            if widget.DragFloat("###"..tostring(i),vt[i]) then
                change = true
                local start = i*4-4
                for j = 1,4 do
                    value[start+j] = this_vt[j]
                end
            end
            active = active or util.IsItemActive()
        end
        widget.TreePop()
    end
    EndColunms()
    return change,value,active
end

local function mult_matrix(ui_cache,name,values)
    widget.Text(String.format("Component %s:to be implemented",name))
    return false
end

local function entityid(ui_cache,name,value)
    --todo:use button to jump
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    widget.Button(value)
    if util.IsItemHovered() then
        widget.SetTooltip("Jump to entity\nTo be implement...")
    end
    EndColunms()
    return false,value
end

local function mult_entityid(ui_cache,name,values)
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    cursor.SetNextItemWidth(-1)
    widget.Text("--")
    EndColunms()
    return false
end

local function primtype(ui_cache,name,value)
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    widget.Text(dump_a({value}))
    EndColunms()
    return false,value
end

local function mult_primtype(ui_cache,name,values)
    BeginColunms()
    widget.Text(name)
    cursor.NextColumn()
    widget.Text(dump_a({values}))
    EndColunms()
    return false
end

--Vector这种由多个元素组成的，多选编辑器的时候，只会改变其中某一项
--所以需要返回一个数组,比如修改了y值，需要返回{{x1,y,z1},{x2,y,z2},{x3,y,z3},...}数组
--其余单个值的，只需要返回一个value
local WillReturnList = {
    vector = true,
    uniformdata = true,
    matrix = true,
}


local factory =  {
    single={
        real = real,
        boolean = boolean,
        tag = tag,
        string = string,
        int = int,
        vector = vector,
        uniformdata = vector,
        matrix = matrix,
        -- color = color,
        entityid = entityid,
        primtype = primtype,
    },
    mult = {
        real = mult_real,
        boolean = mult_boolean,
        tag = mult_tag,
        string = mult_string,
        int = mult_int,
        vector = mult_vector,
        uniformdata = mult_vector,
        matrix = mult_matrix,
        -- color = mult_color,
        entityid = mult_entityid,
        primtype = mult_primtype,
    },
    BeginProperty = BeginProperty,
    EndProperty = EndProperty,
    WillReturnList = WillReturnList,
}

factory.CombineFactory = function(other)
    for _,typ in ipairs({"single","mult","WillReturnList"}) do
        local widgets = factory[typ]
        local other_widgets = other[typ]
        if other_widgets then
            for n,wid in pairs(other_widgets) do
                widgets[n] = wid
            end
        end
    end 
end

return factory
