--- Общие средства проверок консольных команд.
---
--- Разбирает настоящий рок `argparse`: пакет — слой над ним, и двойник
--- рока проверял бы, что мы правильно разговариваем сами с собой. Отказы
--- и справка сверяются с тем, что рок отдаёт на самом деле, — так
--- закреплённый выпуск и проверяется.
---
--- Вывод в потоки процесса, аргументы процесса и выход проверяются
--- ребёнком: сценарий отдельным Tarantool с исходниками пакета. В процессе
--- проверок настоящий выход оборвал бы набор, а настоящий вывод смешался
--- бы с отчётом luatest.
---
--- Исходники читаются с диска, а не через `require`: у Tarantool свой
--- загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Зависимости
--- пакета — `argparse`, `tnt-process`, `tnt-debug`, `tnt-must`
--- и `tnt-external` — берутся из `.rocks` обычным `require`: проверяется
--- этот пакет, а не они. Ребёнок и узел берут их оттуда же.
---
--- Оснастка в `test/testing/` — загрузчик исходников, запись файла и узел
--- luatest — грузится так же и один раз на процесс: второй экземпляр
--- загрузчика не знал бы, что вытеснил первый, и не вернул бы вытесненное
--- на место.

local fio = require('fio')
local t = require('luatest')

--- Модули оснастки в порядке зависимостей.
local TESTING = {
    { name = 'tnt.testing.sources', path = 'test/testing/sources.lua' },
    { name = 'tnt.testing.files', path = 'test/testing/files.lua' },
    { name = 'tnt.testing.node', path = 'test/testing/node.lua' },
}

for _, module in ipairs(TESTING) do
    if package.loaded[module.name] == nil then
        local chunk, failure = loadfile(fio.abspath(module.path))

        if chunk == nil then
            error(('оснастка %s не читается: %s'):format(module.name, tostring(failure)))
        end

        package.loaded[module.name] = chunk()
    end
end

--- Оснастка проверок под теми именами, что зовёт помощник.
local testing = {
    load_sources = package.loaded['tnt.testing.sources'].load,
    module = package.loaded['tnt.testing.sources'].module,
    absolute = package.loaded['tnt.testing.sources'].absolute,
    write_file = package.loaded['tnt.testing.files'].write,
    start_node = package.loaded['tnt.testing.node'].start,
    stop_node = package.loaded['tnt.testing.node'].stop,
}

local helper = {}

--- Модули пакета в порядке зависимостей.
helper.MODULES = {
    { name = 'tnt.console.system', path = 'tnt/console/system.lua' },
    { name = 'tnt.console.phrases', path = 'tnt/console/phrases.lua' },
    { name = 'tnt.console.declaration', path = 'tnt/console/declaration.lua' },
    { name = 'tnt.console.parser', path = 'tnt/console/parser.lua' },
    { name = 'tnt.console.output', path = 'tnt/console/output.lua' },
    { name = 'tnt.console.app', path = 'tnt/console/app.lua' },
    { name = 'tnt.console.remote', path = 'tnt/console/remote.lua' },
    { name = 'tnt.console', path = 'tnt/console.lua' },
}

--- Фасад пакета из исходников.
---
--- Грузится один раз на процесс: состояния у пакета нет, кроме внешних
--- зависимостей, а их группа возвращает после каждой проверки.
helper.console = testing.load_sources(helper.MODULES, 'tnt.console')

--- Части той же загрузки, что и фасад.
helper.phrases = testing.module('tnt.console.phrases')
helper.output = testing.module('tnt.console.output')
helper.system = testing.module('tnt.console.system')
helper.remote = testing.module('tnt.console.remote')

--- Каталог сценариев-детей.
---@type string|nil
local sandbox

--- Группа проверок: после каждой — настоящие средства пакета и снесённый
--- каталог сценариев-детей.
---@param name string
---@return table
function helper.group(name)
    local g = t.group(name)

    g.after_each(function()
        helper.console._set_source(nil)

        if sandbox ~= nil then
            fio.rmtree(sandbox)
        end

        sandbox = nil
    end)

    return g
end

--- Кладёт сценарий-ребёнка: исходники пакета первыми строками, затем тело.
---
--- Исходники подставляются в `package.loaded` абсолютными путями: иначе
--- ребёнок взял бы установленную копию из `.rocks`, и проверка шла бы
--- против вчерашнего кода, а мутант в исходнике остался бы незамеченным.
---@param body string Текст сценария после подстановки исходников
---@return string path
function helper.script(body)
    sandbox = sandbox or fio.tempdir()

    local lines = {}

    for _, module in ipairs(testing.absolute(helper.MODULES)) do
        table.insert(lines, ('package.loaded[%q] = dofile(%q)'):format(module.name, module.path))
    end

    table.insert(lines, body)

    local path = fio.pathjoin(sandbox, 'console.lua')

    testing.write_file(path, table.concat(lines, '\n'))

    return path
end

--- Временный узел с исходниками пакета: настоящий `box` и iproto для
--- команды на узле. Проверка обязана остановить узел сама — `stop_node`.
---@param alias string Имя узла в артефактах прогона
---@return table server
function helper.start_node(alias)
    return testing.start_node({ alias = alias, modules = helper.MODULES })
end

--- Останавливает узел и убирает его каталог.
---@param server table
function helper.stop_node(server)
    testing.stop_node(server)
end

--- Вывод, который собирает строки обоих потоков.
---@return TntConsoleOutput out
---@return { stdout: string[], stderr: string[] } written
function helper.output_capture()
    local written = { stdout = {}, stderr = {} }
    local out = helper.output.new(function(text)
        table.insert(written.stdout, text)
    end, function(text)
        table.insert(written.stderr, text)
    end)

    return out, written
end

--- Текст броска и место, которое он обязан назвать.
---
--- Тело пишется так, что вызов стоит первой строкой после `function()`:
--- бросок обязан показать на эту строку файла проверок, а не на строку
--- внутри пакета.
---@param fn function
---@return string|nil err Текст броска без места; nil — функция не бросила
function helper.blamed(fn)
    local info = debug.getinfo(fn, 'S') --[[@as { short_src: string, linedefined: integer }]]
    local ok, err = pcall(fn)
    local place = ('%s:%d: '):format(info.short_src, info.linedefined + 1)

    if ok then
        return nil
    end

    local text = tostring(err)

    t.assert_equals(text:sub(1, #place), place, text)

    return text:sub(#place + 1)
end

--- Негодный аргумент — нарочно.
---
--- Анализатор типов о таком намерении знать не может и справедливо
--- ругается на каждую такую строку.
---@param value any
---@return any
function helper.wrong(value)
    return value
end

return helper
