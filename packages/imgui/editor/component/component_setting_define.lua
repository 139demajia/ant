local define = {}

define.DefaultOpen = {
    defaultValue = false,
    type = "boolean",
}

define.DisplayName = {
    defaultValue = "",
    type = "string",
}

define.HideHeader = {
    defaultValue = false,
    type = "boolean",
}

define.ArrayStyle = {
    defaultValue = 1,
    type = "enum",
    enumValue = {"index","group"},
}

define.ArrayAsVector = {
    defaultValue = false,
    type = "boolean",
}

define.ArrayChangeSize = {
    defaultValue = 0,
    type = "int",
}

define.IndexFormat = {
    defaultValue = "",
    type = "string",
}

define.RealDragSpeed ={
    defaultValue = 1.0,
    type = "float",
}

return define