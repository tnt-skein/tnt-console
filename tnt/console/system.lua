--- Внешние зависимости пакета: всё, чем он трогает процесс и сеть.
---
--- Одно гнездо на весь пакет: вывод, аргументы процесса, выход, путь
--- Tarantool и клиент iproto нужны разным модулям, и проверка, подменившая
--- их у одного, не должна молча оставить настоящие у соседа.
---
--- Подменяют их проверки там, где настоящее нужного не покажет: выход
--- процесса оборвал бы сам набор проверок, а вывод в настоящий stdout
--- смешался бы с отчётом luatest.

local external = require('tnt.external')

---@class TntConsoleSystem
---@field _set_source fun(replacement: table|nil) Подмена средств — для проверок; ставит её `external.install`
local Module = {}

--- Пишет в поток вывода процесса.
---@param text string
local function stdout(text)
    io.stdout:write(text)
end

--- Пишет в поток ошибок процесса.
---@param text string
local function stderr(text)
    io.stderr:write(text)
end

--- Аргументы командной строки процесса, без сценария и самого Tarantool.
---
--- Tarantool кладёт их в глобал `arg`: под номером 0 — сценарий, под -1 —
--- путь Tarantool, с первого — аргументы. Копия нужна потому, что `arg`
--- общий на процесс, и правка списка командой не должна доходить до него.
---@return string[]
local function arguments()
    local list = {}

    for at = 1, #arg do
        list[at] = arg[at]
    end

    return list
end

--- Клиент iproto, которым команда на узле зовёт функцию узла.
---
--- Берётся при первом вызове: сценарию без команд на узле он не нужен.
---@return table
local function net_box()
    return require('net.box')
end

--- Tarantool, которым запущен этот процесс.
---
--- Команда отдельным процессом идёт тем же Tarantool, что и узел: другой
--- выпуск по `PATH` читал бы тот же код по-другому. Путь лежит в `arg[-1]`;
--- без него — имя, и его найдёт по `PATH` запуск процесса.
---@return string
local function interpreter()
    return arg[-1] or 'tarantool'
end

---@class TntConsoleSource Средства пакета
---@field stdout fun(text: string) Запись в поток вывода
---@field stderr fun(text: string) Запись в поток ошибок
---@field arguments fun(): string[] Аргументы командной строки процесса
---@field exit fun(code: integer) Выход процесса с кодом
---@field interpreter fun(): string Путь Tarantool этого процесса
---@field net_box fun(): table Клиент iproto — модуль `net.box`

--- Действующие средства.
---@type fun(): TntConsoleSource
Module.current = external.install(Module, {
    stdout = stdout,
    stderr = stderr,
    arguments = arguments,
    exit = os.exit,
    interpreter = interpreter,
    net_box = net_box,
})

return Module
