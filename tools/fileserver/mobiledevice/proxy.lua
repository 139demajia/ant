package.path = table.concat({
	"tools/fileserver/?.lua",
    "tools/fileserver/?/?.lua"
}, ";")
dofile "engine/editor/init_cpath.lua"

local network = require 'network'
local usbmuxd = require 'mobiledevice.usbmuxd'

local function LOG(...)
    print('[iOS proxy]', ...)
end

local eventfd
local devices = {}

local closed = {}
local function is_closed(fd)
    if closed[fd] then
        closed[fd] = nil
        return true
    end
    return false
end

local function update_fd(fd)
    if fd._status == "CLOSED" then
        closed[fd] = true
    end
end


local function connect_server()
    local fd = assert(network.connect('127.0.0.1', 2018))
    fd.update = update_fd
    return fd
end

local function connect_usbmuxd()
    local fd = assert(network.connect(usbmuxd.get_address()))
    fd.update = update_fd
    return fd
end

local function init()
    eventfd = connect_usbmuxd()
    local a, b = usbmuxd.create_listen_package()
    network.send(eventfd, a)
    network.send(eventfd, b)
end

local function update_event()
    while true do
        local event = usbmuxd.recv(eventfd)
        if not event then
            return
        end
        if event.MessageType == 'Result' then
            assert(event.Number == 0, event.Number)
        elseif event.MessageType == 'Attached' then
            LOG('device add', event.Properties.SerialNumber)
            local info = {}
            devices[event.DeviceID] = info
            info.id = event.DeviceID
            info.sn = event.Properties.SerialNumber
            info.status = 'idle'
        elseif event.MessageType == 'Detached' then
            LOG('device del', devices[event.DeviceID].sn)
            devices[event.DeviceID].status = 'closed'
        elseif event.MessageType == 'Paired' then
            LOG('device paired', devices[event.DeviceID].sn)
        else
            error('Unknown message: ' .. event.MessageType)
        end
    end
end

local function try_connect(device)
    local id = device.id
    device.cfd = connect_usbmuxd()
    local a, b = usbmuxd.create_connect_package(id, 2018)
    network.send(device.cfd, a)
    network.send(device.cfd, b)
end

local function update_devices()
    local delete = {}
    for id, device in pairs(devices) do
        if device.status == 'idle' then
            try_connect(device)
            device.status = 'wait'
        elseif device.status == 'wait' then
            if is_closed(device.cfd) then
                try_connect(device)
                return
            end
            local msg = usbmuxd.recv(device.cfd)
            if msg then
                assert(msg.MessageType == 'Result')
                if msg.Number == 0 then
                    LOG('connected')
                    device.status = 'connected'
                elseif msg.Number == 3 then
                    network.close(device.cfd)
                    try_connect(device)
                else
                    error('Unknown result: ' .. msg.Number)
                end
            end
        elseif device.status == 'connected' then
            device.sfd = connect_server()
            device.status = 'ok'
        elseif device.status == 'ok' then
            if is_closed(device.cfd) then
                LOG('reconnect device')
                network.close(device.sfd)
                try_connect(device)
                device.status = 'wait'
                goto continue
            end
            if is_closed(device.sfd) then
                LOG('reconnect server')
                network.close(device.cfd)
                try_connect(device)
                device.status = 'wait'
                goto continue
            end
            local function proxy(from, to)
                from = from._read
                for i = 1, #from do
                    network.send(to, from[i])
                    from[i] = nil
                end
            end
            proxy(device.cfd, device.sfd)
            proxy(device.sfd, device.cfd)
        elseif device.status == 'closed' then
            if device.sfd then
                LOG('disconnect server')
                network.close(device.sfd)
            end
            if device.cfd then
                LOG('disconnect device')
                network.close(device.cfd)
            end
            delete[id] = true
        end
        ::continue::
    end
    for id in pairs(delete) do
        devices[id] = nil
    end
end

local function update()
    update_event()
    update_devices()
end

return {
    init = init,
    update = update,
}
