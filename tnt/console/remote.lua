--- Команда на узле: командную строку выполняет функция узла по iproto,
--- а вывод и код выхода повторяются здесь — в потоках и коде этого
--- процесса.
---
---     -- на узле: функция для lua_call
---     rawset(_G, 'app_command', function(argv)
---         return app:reply(argv)
---     end)
---
---     -- у оператора: console.lua
---     console.remote({ uri = '127.0.0.1:3301', user = 'operator', password = secret,
---         call = 'app_command' }):main()
---
--- Командам, которым нужен живой узел — его спейсы, его контейнер
--- со службами, — консоль узла не годится: ответ она заворачивает в YAML,
--- а отказ и бросок кончаются кодом 0, и сценарий не отличит удачу
--- от отказа. Вызов по iproto отдаёт итог таблицей, и код выхода здесь —
--- тот, которым команда кончилась на узле. Учётке оператора хватает права
--- на одну функцию (`lua_call`), права на `eval` для всего ей не нужно.
---
--- Код 69 — узел не ответил: нет связи, нет права на функцию, функции нет,
--- срок вышел. Это «служба недоступна» по `sysexits.h`: команда до узла
--- не дошла либо её ответа не дождались, и сценарий отличает это
--- от отказа самой команды. Ответ не того вида — поломка, код 70: функция
--- узла отвечает не итогом команды, и это чинят в коде, а не повтором.

local must = require('tnt.must')
local uri = require('uri')

local app = require('tnt.console.app')
local system = require('tnt.console.system')

local Module = {}

--- Узел не ответил.
Module.UNAVAILABLE = 69

--- Срок соединения и срок ответа, секунды, если не назван свой.
Module.TIMEOUT = 60

--- Вид ответа узла: итог `app:reply`.
local REPLY = { code = 'integer', stdout = 'string', stderr = 'string' }

---@class TntConsoleRemoteOptions
---@field uri string Адрес iproto узла
---@field call string Имя функции узла, которая выполняет командную строку
---@field user string|nil Учётка; без неё — гость
---@field password string|nil Пароль учётки
---@field timeout number|nil Срок соединения и срок ответа, секунды

---@class TntConsoleRemote Команда на узле
---@field uri string Адрес iproto узла
---@field call string Имя функции узла
---@field user string|nil Учётка
---@field timeout number Срок соединения и срок ответа, секунды
---@field private _connect fun(net_box: table): table Соединение с узлом
local Remote = {}

Remote.__index = Remote

--- Адрес узла для текста: без пароля, даже если его вписали в адрес.
---
--- Адрес, который не разбирается, показывается как есть: пароль в нём
--- не отличить от остального, а `net.box` откажет ему и без соединения.
---@param address string
---@return string
local function shown(address)
    local parsed = uri.parse(address)

    return parsed ~= nil and uri.format(parsed) or address
end

--- Итог команды от узла либо причина, по которой его нет.
---
--- Отказ соединения `net.box` не бросает, а помечает соединение, и первый
--- же вызов на нём бросает ту же причину: проверять соединение отдельно
--- незачем.
---@param remote TntConsoleRemote
---@param argv string[]
---@return any reply Что вернула функция узла
---@return string|nil reason Почему ответа нет
local function exchange(remote, argv)
    local opened, connection = pcall(remote._connect, system.current().net_box())

    if not opened then
        return nil, tostring(connection)
    end

    local called, reply = pcall(connection.call, connection, remote.call, { argv }, { timeout = remote.timeout })

    connection:close()

    if not called then
        return nil, tostring(reply)
    end

    return reply, nil
end

--- Выполняет командную строку на узле: вывод — в потоки процесса.
---@param argv string[] Аргументы: имя команды, её аргументы и ключи
---@return integer code Код выхода
function Remote:run(argv)
    must.at(2).array_of(argv, 'аргументы', 'string')

    local source = system.current()
    local reply, reason = exchange(self, argv)

    if reason ~= nil then
        source.stderr(('нет ответа узла %s: %s\n'):format(shown(self.uri), reason))

        return Module.UNAVAILABLE
    end

    local complaint = must.explain.options(reply, 'ответ узла', REPLY)
        or must.explain.kind(reply.code, 'ответ узла.code', 'between', app.OK, app.MAX_CODE)

    if complaint ~= nil then
        source.stderr(
            ('узел %s ответил не итогом команды: %s\n'):format(shown(self.uri), complaint)
        )

        return app.BROKEN
    end

    source.stdout(reply.stdout)
    source.stderr(reply.stderr)

    return reply.code
end

--- Точка входа сценария: выполняет на узле командную строку процесса
--- и кончает процесс её кодом.
function Remote:main()
    local source = system.current()

    source.exit(self:run(source.arguments()))
end

--- Новая команда на узле. Настройки проверяет фасад.
---
--- Пароль живёт в замыкании соединения, а не полем: команду, показанную
--- в консоли или обойдённую `pairs`, видно без него.
---@param options TntConsoleRemoteOptions
---@return TntConsoleRemote
function Module.new(options)
    local timeout = options.timeout or Module.TIMEOUT
    local user = options.user
    local password = options.password
    local address = options.uri

    return setmetatable({
        uri = address,
        call = options.call,
        user = user,
        timeout = timeout,
        _connect = function(net_box)
            return net_box.connect(address, { user = user, password = password, connect_timeout = timeout })
        end,
    }, Remote)
end

return Module
