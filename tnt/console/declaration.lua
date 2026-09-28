--- Объявление команды: проверка описания и приведение его к одному виду.
---
--- Объявление — таблица данных, а не цепочка вызовов рока: по данным
--- разбор собирается заново на каждый вызов, и одно и то же объявление
--- служит и командной строке, и вызову из кода (`call`). Всё, что в нём
--- неверно, — ошибка программиста, и о ней говорится при объявлении,
--- а не тогда, когда оператор впервые наберёт команду.
---
--- Проверки здесь не бросают, а отдают текст отказа: бросает один
--- `command` приложения, и место в броске — всегда строка объявления.

local explain = require('tnt.must').explain

local Module = {}

--- Имя команды: буквы, цифры, двоеточие для разделов (`cache:clear`),
--- подчёркивание и дефис.
Module.COMMAND_NAME = '^[a-z][a-z0-9:_-]*$'

--- Имя аргумента — оно же поле входа обработчика.
Module.ARGUMENT_NAME = '^[a-z][a-z0-9_]*$'

--- Имя ключа — как его набирают, без дефисов впереди: `dry-run` для
--- `--dry-run`. В поле входа дефис становится подчёркиванием: `dry_run`.
Module.OPTION_NAME = '^[a-z][a-z0-9-]*$'

--- Короткий ключ — одна буква: `f` для `-f`.
Module.SHORT_NAME = '^%a$'

--- Роды значения; по умолчанию — строка.
Module.TYPES = { 'string', 'number', 'integer' }

--- Описание команды.
local COMMAND = {
    description = 'not_empty',
    arguments = { '?array_of', 'table' },
    options = { '?array_of', 'table' },
    handler = 'callable',
}

--- Описание аргумента.
local ARGUMENT = {
    name = 'string',
    description = 'not_empty',
    optional = '?boolean',
    many = '?boolean',
    default = '?number|string',
    type = { '?one_of', Module.TYPES },
    choices = { '?array_of', 'string' },
}

--- Описание ключа.
local OPTION = {
    name = 'string',
    short = '?string',
    description = 'not_empty',
    flag = '?boolean',
    required = '?boolean',
    many = '?boolean',
    default = '?number|string',
    type = { '?one_of', Module.TYPES },
    choices = { '?array_of', 'string' },
}

---@class TntConsoleElement Аргумент либо ключ команды после проверки
---@field name string Имя, как его объявили
---@field key string Поле входа обработчика
---@field label string Как его называют отказы: `аргумент «file»`, `ключ «--timeout»`
---@field description string Что это
---@field optional boolean|nil Аргумент может не прийти
---@field short string|nil Буква короткого ключа
---@field flag boolean|nil Ключ без значения
---@field required boolean|nil Ключ обязателен
---@field many boolean|nil Значений список
---@field default string|number|nil Значение, когда не пришло, как его объявили
---@field fallback any Умолчание, приведённое к роду элемента
---@field type string|nil Род значения: string, number либо integer
---@field choices string[]|nil Допустимые значения

---@class TntConsoleCommand Команда после проверки
---@field name string Имя команды
---@field description string Что делает команда
---@field arguments TntConsoleElement[] Аргументы по порядку
---@field options TntConsoleElement[] Ключи по порядку
---@field handler fun(input: table, out: TntConsoleOutput): any Обработчик

--- Чего у флага быть не может: значения у него нет, есть лишь «пришёл».
local FLAG_EXCLUDES = { 'type', 'default', 'choices', 'many', 'required' }

--- Число из текста командной строки.
---@param text string
---@return number|nil
local function finite(text)
    local number = tonumber(text)

    -- `tonumber` читает и `nan`, и `inf`, и `1e400`: ни того, ни другого
    -- оператор не имеет в виду, набирая число. NaN не равен себе.
    if number == nil or number ~= number or math.abs(number) == math.huge then
        return nil
    end

    return number
end

--- Разборщики значений по роду: текст → значение либо `nil`.
local READERS = {
    number = finite,
    integer = function(text)
        local number = finite(text)

        if number ~= nil and number % 1 == 0 then
            return number
        end

        return nil
    end,
}

--- Как род значения зовётся в отказе.
local NOUNS = { number = 'число', integer = 'целое число' }

--- Приводит значение из командной строки к роду элемента.
---
--- Функция отдаётся року для разбора; отказ он показывает как есть,
--- поэтому текст здесь уже весь: кто, каким должен быть и что пришло.
---@param element TntConsoleElement
---@return (fun(text: string): any, string|nil)|nil
function Module.reader(element)
    local read = READERS[element.type]

    if read == nil then
        return nil
    end

    return function(text)
        local value = read(text)

        if value == nil then
            return nil, ('%s — %s, а не «%s»'):format(element.label, NOUNS[element.type], text)
        end

        return value
    end
end

--- Умолчание тем же родом, что значение из командной строки.
---
--- Умолчание проходит те же проверки, что набранное значение, — иначе
--- отказ получил бы оператор, не набравший ничего, — и приходит
--- обработчику тем же родом: у строкового элемента умолчание `5` — `'5'`.
---@param element TntConsoleElement
---@return any value
---@return string|nil complaint
local function fallback(element)
    local text = tostring(element.default)

    if element.choices ~= nil then
        local complaint = explain.kind(text, 'значение', 'one_of', element.choices)

        if complaint ~= nil then
            return nil, complaint
        end
    end

    local read = Module.reader(element)

    if read == nil then
        return text
    end

    return read(text)
end

--- Проверяет общее у аргумента и ключа и занимает поле входа.
---@param element TntConsoleElement
---@param where string Как элемент зовётся в отказе объявления
---@param taken table<string, boolean> Занятые поля входа
---@return string|nil complaint
local function check_element(element, where, taken)
    if taken[element.key] then
        return ('%s: поле «%s» уже занято'):format(where, element.key)
    end

    taken[element.key] = true

    if element.default ~= nil then
        if element.many then
            return ('%s: у списка значений умолчания не бывает'):format(where)
        end

        local value, complaint = fallback(element)

        if complaint ~= nil then
            return ('%s: умолчание не годится: %s'):format(where, complaint)
        end

        element.fallback = value
    end

    return nil
end

--- Проверяет аргумент.
---@param spec table
---@param where string
---@param taken table<string, boolean>
---@param previous TntConsoleElement|nil Аргумент перед ним
---@return TntConsoleElement|nil element
---@return string|nil complaint
local function argument(spec, where, taken, previous)
    local complaint = explain.options(spec, where, ARGUMENT)
        or explain.kind(spec.name, where .. '.name', 'matches', Module.ARGUMENT_NAME)

    if complaint ~= nil then
        return nil, complaint
    end

    -- Место значения в командной строке решает его номер: после списка
    -- значения не останется никому, а обязательное после необязательного
    -- забрало бы то, что оператор набирал для первого.
    if previous ~= nil and previous.many then
        return nil,
            ('%s: после списка значений аргументов не бывает'):format(where)
    end

    if previous ~= nil and previous.optional and not spec.optional then
        return nil,
            ('%s: обязательный аргумент не ставится после необязательного'):format(
                where
            )
    end

    if spec.default ~= nil and not spec.optional then
        return nil,
            ('%s: умолчание бывает только у необязательного аргумента'):format(
                where
            )
    end

    local element = table.copy(spec) --[[@as TntConsoleElement]]

    element.key = spec.name
    element.label = ('аргумент «%s»'):format(spec.name)

    return element, check_element(element, where, taken)
end

--- Проверяет ключ.
---@param spec table
---@param where string
---@param taken table<string, boolean>
---@param letters table<string, boolean> Занятые буквы коротких ключей
---@return TntConsoleElement|nil element
---@return string|nil complaint
local function option(spec, where, taken, letters)
    local complaint = explain.options(spec, where, OPTION)
        or explain.kind(spec.name, where .. '.name', 'matches', Module.OPTION_NAME)
        or explain.kind(spec.short, where .. '.short', '?matches', Module.SHORT_NAME)

    if complaint ~= nil then
        return nil, complaint
    end

    if spec.flag then
        for _, key in ipairs(FLAG_EXCLUDES) do
            if spec[key] ~= nil then
                return nil,
                    ('%s: флаг — ключ без значения, и %s ему не нужен'):format(
                        where,
                        key
                    )
            end
        end
    end

    if spec.required and spec.default ~= nil then
        return nil, ('%s: обязательному ключу умолчание не нужно'):format(where)
    end

    if spec.short ~= nil then
        if letters[spec.short] then
            return nil, ('%s: буква «%s» уже занята'):format(where, spec.short)
        end

        letters[spec.short] = true
    end

    local element = table.copy(spec) --[[@as TntConsoleElement]]

    element.key = (spec.name:gsub('-', '_'))
    element.label = ('ключ «--%s»'):format(spec.name)

    return element, check_element(element, where, taken)
end

--- Проверяет объявление команды и приводит его к одному виду.
---
--- Справка занимает ключ `--help` и букву `h` у каждой команды, поэтому
--- поле `help` и буква `h` заняты с самого начала.
---@param commands table<string, TntConsoleCommand> Уже объявленные команды
---@param name any Имя команды
---@param spec any Описание команды
---@return TntConsoleCommand|nil command
---@return string|nil complaint
function Module.command(commands, name, spec)
    local complaint = explain.kind(name, 'имя команды', 'matches', Module.COMMAND_NAME)
        or explain.options(spec, ('команда %s'):format(name), COMMAND)

    if complaint ~= nil then
        return nil, complaint
    end

    if commands[name] ~= nil then
        return nil, ('команда %s уже объявлена'):format(name)
    end

    local command =
        { name = name, description = spec.description, handler = spec.handler, arguments = {}, options = {} }
    local taken = { help = true }
    local letters = { h = true }

    for at, given in ipairs(spec.arguments or {}) do
        local previous = command.arguments[at - 1]
        local where = ('команда %s: аргументы[%d]'):format(name, at)
        local element, refusal = argument(given, where, taken, previous)

        if refusal ~= nil then
            return nil, refusal
        end

        command.arguments[at] = element
    end

    for at, given in ipairs(spec.options or {}) do
        local element, refusal = option(given, ('команда %s: ключи[%d]'):format(name, at), taken, letters)

        if refusal ~= nil then
            return nil, refusal
        end

        command.options[at] = element
    end

    return command
end

return Module
