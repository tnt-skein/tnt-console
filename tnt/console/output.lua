--- Вывод команды: строки в поток вывода и в поток ошибок, таблица
--- и показ значения.
---
--- Куда уходит вывод, решает тот, кто завёл вывод: из командной строки —
--- в потоки процесса, из кода (`call`) — в строки, которые вызов отдаст.
--- Обработчик команды об этом не знает, и одна команда без правки служит
--- обоим.
---
--- Поток ошибок — для того, что человек должен увидеть, даже когда вывод
--- уходит в файл или в разбор другой программой: отказ, предупреждение.
--- То, что команда отвечает, — в поток вывода.

local dbg = require('tnt.debug')
local must = require('tnt.must')
local utf8 = require('utf8')

local Module = {}

---@class TntConsoleOutput Вывод команды
---@field private _stdout fun(text: string)
---@field private _stderr fun(text: string)
local Output = {}

Output.__index = Output

--- Строка из образца: с аргументами — через `format`, без них — как есть.
---
--- Без аргументов текст не проходит через `format`: знак процента в нём —
--- буква, а не начало подстановки, и строка из данных не ломает вывод.
---@param text string|nil
---@param ... any
---@return string
local function compose(text, ...)
    local caller = must.at(3)

    caller.optional.string(text, 'строка')

    if select('#', ...) > 0 then
        return caller.string(text, 'образец строки'):format(...)
    end

    return text or ''
end

--- Строка в поток вывода.
---
---     out:line('готово')
---     out:line('файлов: %d, испорченных: %d', #files, #broken)
---     out:line()                       -- пустая строка
---@param text string|nil Строка либо образец `string.format`
---@param ... any Подстановки образца
function Output:line(text, ...)
    self._stdout(compose(text, ...) .. '\n')
end

--- Строка в поток ошибок.
---@param text string|nil Строка либо образец `string.format`
---@param ... any Подстановки образца
function Output:error(text, ...)
    self._stderr(compose(text, ...) .. '\n')
end

--- Ширина текста в знаках.
---
--- `string.format('%-10s')` отмеряет байты, а буква кириллицы — два байта:
--- столбец с русскими словами уезжает. Здесь счёт по знакам UTF-8, а текст
--- не в UTF-8 меряется байтами — ширина у него всё равно не угадывается.
---@param text string
---@return integer
local function width(text)
    return utf8.len(text) or #text
end

--- Строка таблицы: ячейки дополнены пробелами до ширины столбца.
---
--- Хвостовые пробелы срезаются: последний столбец дополнять не к чему,
--- а пробелы в конце строки мешают разбору вывода другой программой.
---@param cells string[]
---@param widths table<integer, integer>
---@return string
local function row_line(cells, widths)
    local parts = {}

    for column, text in ipairs(cells) do
        parts[column] = text .. (' '):rep(widths[column] - width(text))
    end

    return (table.concat(parts, '  '):match('^(.-)%s*$')) --[[@as string]]
end

--- Таблица в поток вывода: столбцы выровнены по знакам, а не по байтам.
---
---     out:table({ 'файл', 'записей' }, {
---         { '00000000000000000000.xlog', 12 },
---         { '00000000000000000012.xlog', '' },
---     })
---     --> файл                       записей
---     --> -------------------------  -------
---     --> 00000000000000000000.xlog  12
---     --> 00000000000000000012.xlog
---
--- Шапка необязательна: без неё — только строки. Ячейка проходит
--- `tostring`; строка таблицы — список, и кончается он на первой
--- пустоте, поэтому пустую ячейку пишут пустой строкой.
---@param headers string[]|nil Шапка
---@param rows any[][] Строки таблицы: списки ячеек
function Output:table(headers, rows)
    local caller = must.at(2)

    caller.optional.array_of(headers, 'шапка', 'string')
    caller.array_of(rows, 'строки', 'table')

    local lines = { headers }
    ---@type table<integer, integer>
    local widths = {}

    for _, values in ipairs(rows) do
        local cells = {}

        for column, value in ipairs(values) do
            cells[column] = tostring(value)
        end

        table.insert(lines, cells)
    end

    for _, cells in ipairs(lines) do
        for column, text in ipairs(cells) do
            widths[column] = math.max(widths[column] or -math.huge, width(text))
        end
    end

    -- Черта под шапкой — во всю ширину столбца: ячейка бывает шире
    -- своего заголовка.
    if headers ~= nil then
        local rules = {}

        for column in ipairs(headers) do
            rules[column] = ('-'):rep(widths[column])
        end

        table.insert(lines, 2, rules)
    end

    for _, cells in ipairs(lines) do
        self:line(row_line(cells, widths))
    end
end

--- Показ значения человеку в поток вывода.
---
--- Показ — `tnt-debug`: ключи в постоянном порядке, род значения виден,
--- тайны скрыты, функция и кольцо не роняют вывод, как роняют
--- `yaml.encode` и `json.encode`.
---@param value any
---@param options TntDebugDescribeOptions|nil Настройки показа `describe`
function Output:describe(value, options)
    -- Бросает `describe` только на негодных настройках, и место у броска —
    -- кадр, который его позвал. Через `pcall` этот кадр — сам `pcall`,
    -- и места в тексте нет: его ставит бросок ниже, строкой вызывающего.
    local ok, text = pcall(dbg.describe, value, options)

    if not ok then
        error(text, 2)
    end

    self:line(text)
end

--- Новый вывод.
---@param stdout fun(text: string) Куда писать вывод
---@param stderr fun(text: string) Куда писать ошибки
---@return TntConsoleOutput
function Module.new(stdout, stderr)
    return setmetatable({ _stdout = stdout, _stderr = stderr }, Output)
end

return Module
