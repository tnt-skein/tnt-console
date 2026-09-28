--- Приложение командной строки: объявленные команды и их запуск.
---
--- Команда запускается одинаково из командной строки (`run`, `main`)
--- и из кода (`call`): тот же разбор, тот же обработчик, тот же код
--- выхода. Разница только в том, куда уходит вывод, — в потоки процесса
--- либо в строки итога вызова.
---
--- Код выхода говорит, чем кончилось, и разводит то, с чем вызывающий
--- поступает по-разному: отказ — «так бывает», поломка — «чини код».
---
--- * `OK`, 0 — команда сделала своё;
--- * `FAILURE`, 1 — отказ: обработчик вернул `nil, err` либо `false`;
--- * `USAGE`, 2 — команду набрали неверно: нет такой, не хватает
---   аргумента, незнакомый ключ, — до обработчика дело не дошло;
--- * `BROKEN`, 70 — обработчик бросил: ошибка программиста.
---
--- Два — код неверного вызова у утилит оболочки, и сценарий, звавший
--- команду, отличает его от отказа самой команды. Семьдесят — «внутренняя
--- ошибка программы» по `sysexits.h`: обработчик сам таким кодом
--- не отвечает, и поломку не спутать с его ответом.

local failure = require('tnt.process.failure')
local must = require('tnt.must')

local declaration = require('tnt.console.declaration')
local output = require('tnt.console.output')
local parser = require('tnt.console.parser')
local system = require('tnt.console.system')

local Module = {}

--- Команда сделала своё.
Module.OK = 0

--- Отказ: обработчик вернул `nil, err` либо `false`.
Module.FAILURE = 1

--- Команду набрали неверно.
Module.USAGE = 2

--- Обработчик бросил.
Module.BROKEN = 70

--- Наибольший код выхода: больше процесс не передаст, и 256 дошёл бы нулём.
Module.MAX_CODE = 255

---@class TntConsoleApp Приложение командной строки
---@field name string Имя в строке вызова
---@field description string|nil Что это за приложение — в справке
---@field commands TntConsoleCommand[] Команды по порядку объявления
---@field named table<string, TntConsoleCommand> Команды по имени
local App = {}

App.__index = App

---@class TntConsoleResult Команда кончилась кодом 0
---@field code integer Код выхода — 0
---@field stdout string Вывод целиком
---@field stderr string Поток ошибок целиком

---@class TntConsoleReply Итог команды при любом коде
---@field code integer Код выхода
---@field stdout string Вывод целиком
---@field stderr string Поток ошибок целиком

--- Стек броска обработчика: без него поломку пришлось бы искать по одному
--- тексту, а место броска — в чужом файле.
---
--- Стек начинается кадром за перехватчиком: у ошибки исполнения это
--- строка, где она случилась, у `error` — сам `error` и строка под ним.
--- Вызов не хвостовой нарочно: LuaJIT снимает кадр хвостового вызова,
--- и уровень 2 отсчитывался бы уже от бросившей строки, пропуская её.
---@param err any
---@return string
local function traceback(err)
    local text = debug.traceback(tostring(err), 2)

    return text
end

--- Код выхода по тому, что вернул обработчик.
---
--- Ничего, `nil` без причины, `true` и прочие значения — удача. Число —
--- сам код выхода: у команды, которая проверяет, «нашла» — тоже ответ.
--- `nil` либо `false` с причиной — отказ, и причина уходит в поток ошибок.
---@param command TntConsoleCommand
---@param out TntConsoleOutput
---@param ok boolean Обработчик не бросил
---@param first any Первое, что он вернул, либо текст броска
---@param second any Второе, что он вернул
---@return integer
local function finish(command, out, ok, first, second)
    if not ok then
        out:error('команда %s сломалась: %s', command.name, first)

        return Module.BROKEN
    end

    if type(first) == 'number' then
        local complaint = must.explain.kind(first, 'код выхода', 'integer')
            or must.explain.kind(first, 'код выхода', 'between', Module.OK, Module.MAX_CODE)

        if complaint ~= nil then
            out:error('команда %s сломалась: %s', command.name, complaint)

            return Module.BROKEN
        end

        return first --[[@as integer]]
    end

    if not first and second ~= nil then
        out:error(tostring(second))

        return Module.FAILURE
    end

    if first == false then
        return Module.FAILURE
    end

    return Module.OK
end

--- Разбирает командную строку и выполняет команду.
---@param app TntConsoleApp
---@param argv string[]
---@param out TntConsoleOutput
---@return integer
local function dispatch(app, argv, out)
    local outcome = parser.parse(app, argv)

    if outcome.help ~= nil then
        out:line(outcome.help)

        return Module.OK
    end

    if outcome.refusal ~= nil then
        out:error('%s\n\nОшибка: %s', outcome.usage, outcome.refusal)

        return Module.USAGE
    end

    local command = outcome.command --[[@as TntConsoleCommand]]
    local input = outcome.input --[[@as table]]

    return finish(command, out, xpcall(command.handler, traceback, input, out))
end

--- Выполняет командную строку, собирая вывод в строки итога.
---@param app TntConsoleApp
---@param argv string[]
---@return TntConsoleReply
local function captured(app, argv)
    local stdout = {}
    local stderr = {}
    local out = output.new(function(text)
        table.insert(stdout, text)
    end, function(text)
        table.insert(stderr, text)
    end)
    local code = dispatch(app, argv, out)

    return { code = code, stdout = table.concat(stdout), stderr = table.concat(stderr) }
end

--- Объявляет команду.
---
---     app:command('cache:clear', {
---         description = 'Забыть всё в кэше',
---         arguments = { { name = 'store', description = 'хранилище', optional = true } },
---         options = { { name = 'force', short = 'f', flag = true, description = 'не спрашивать' } },
---         handler = function(input, out)
---             out:line('забыто: %s', input.store or 'всё')
---         end,
---     })
---
--- Негодное объявление — бросок на строке объявления.
---@param name string Имя команды: `cache:clear`
---@param spec table Описание: `description`, `arguments`, `options`, `handler`
---@return TntConsoleApp self
function App:command(name, spec)
    local command, complaint = declaration.command(self.named, name, spec)

    if command == nil then
        error(complaint, 2)
    end

    self.named[name] = command
    table.insert(self.commands, command)

    return self
end

--- Выполняет командную строку: вывод — в потоки процесса.
---@param argv string[] Аргументы: имя команды, её аргументы и ключи
---@return integer code Код выхода
function App:run(argv)
    must.at(2).array_of(argv, 'аргументы', 'string')

    local source = system.current()

    return dispatch(self, argv, output.new(source.stdout, source.stderr))
end

--- Выполняет командную строку из кода: вывод собирается в итог.
---
--- Удача — код 0 с выводом и потоком ошибок. Всякий другой код — отказ
--- парой, тот же, что у команды отдельным процессом (`execute`): род
--- `exit`, код, вывод и поток ошибок в полях.
---@param argv string[] Аргументы: имя команды, её аргументы и ключи
---@return TntConsoleResult|nil result
---@return TntProcessFailure|nil err
function App:call(argv)
    must.at(2).array_of(argv, 'аргументы', 'string')

    local fields = captured(self, argv)

    if fields.code ~= Module.OK then
        return nil,
            failure.new(
                failure.EXIT,
                self.name,
                ('вызов %s кончился с кодом %d'):format(self.name, fields.code),
                fields
            )
    end

    return fields --[[@as TntConsoleResult]]
end

--- Выполняет командную строку из кода: итог одной таблицей при любом коде.
---
--- Это тело функции узла, которую зовёт `console.remote` по iproto.
--- Отказ `call` там не годится: iproto донесёт его поля, но метатаблицу
--- потеряет, а сценарию на той стороне нужен один вид ответа — код,
--- вывод и поток ошибок, — чтобы повторить их у себя.
---
---     rawset(_G, 'app_command', function(argv)
---         return app:reply(argv)
---     end)
---@param argv string[] Аргументы: имя команды, её аргументы и ключи
---@return TntConsoleReply
function App:reply(argv)
    must.at(2).array_of(argv, 'аргументы', 'string')

    return captured(self, argv)
end

--- Точка входа сценария: разбирает аргументы процесса, выполняет команду
--- и кончает процесс её кодом.
---
---     -- console.lua
---     require('app.console'):main()
---
--- Выход — явный: команда, поднявшая узел (`box.cfg`) либо файбер,
--- иначе оставила бы процесс жить после себя.
function App:main()
    local source = system.current()

    source.exit(self:run(source.arguments()))
end

--- Новое приложение.
---@param name string Имя в строке вызова
---@param description string|nil Что это за приложение
---@return TntConsoleApp
function Module.new(name, description)
    return setmetatable({ name = name, description = description, commands = {}, named = {} }, App)
end

return Module
