--- Разбор командной строки роком `argparse` по объявленным командам.
---
--- Разбирает рок — своего разбора аргументов здесь нет. Пакет собирает
--- ему разбор из объявлений и забирает итог, закрывая три места, где рок
--- ведёт себя как самостоятельная программа, а не как часть приложения:
---
--- 1. **Справка и отказ завершают процесс.** Ключ `--help` рока печатает
---    справку и зовёт `os.exit(0)`, а `parse` на ошибке — `os.exit(1)`.
---    Команда, позванная из кода узла (`call`), уронила бы узел. Здесь
---    справка — свой ключ, который только отмечает, чья справка нужна,
---    а разбор идёт через `pparse`, отдающий отказ парой.
--- 2. **Слова по-английски** — переводит `tnt.console.phrases`.
--- 3. **Разбор общий на процесс.** Объект разбора рок заполняет на ходу,
---    и два файбера, разбирающие одним объектом, мешали бы друг другу.
---    Разбор собирается заново на каждый вызов: он дешёвый — таблица
---    на команду, — а объявления его не меняются.

local argparse = require('argparse') --[[@as fun(name: string, description: string|nil): any]]

local declaration = require('tnt.console.declaration')
local phrases = require('tnt.console.phrases')

local Module = {}

--- Поле итога рока, куда он кладёт имя выбранной команды.
---
--- Имена аргументов и ключей начинаются с буквы, и поле с подчёркиванием
--- впереди не совпадёт ни с одним из них.
local COMMAND = '_command'

--- Описание ключа справки.
local HELP = 'показать эту справку и выйти'

---@class TntConsoleOutcome Итог разбора
---@field help string|nil Справка, о которой попросили
---@field refusal string|nil Отказ разбора по-русски
---@field usage string|nil Строка вызова либо справка к отказу
---@field command TntConsoleCommand|nil Выбранная команда
---@field input table|nil Значения аргументов и ключей команды

--- Заводит ключ справки у разбора.
---
--- Действие ключа не бросает и не выходит: отмечает разбор и даёт
--- разбору идти дальше. Отказ, найденный после ключа, справку не
--- отменяет — оператор, набравший `--help`, просил справку, а не отказ.
---@param parser any Разбор рока: приложение либо команда
---@param asked table Куда отметить разбор, чью справку просили
---@return any flag
local function help_flag(parser, asked)
    return parser:flag('-h --help'):description(HELP):action(function()
        asked.parser = parser
    end)
end

--- Описание элемента для справки: со значением по умолчанию, если оно есть.
---
--- Своё, а не рока: рок дописывает умолчание по-английски.
---@param element TntConsoleElement
---@return string
local function note(element)
    if element.default == nil then
        return element.description
    end

    return ('%s (по умолчанию: %s)'):format(element.description, element.default)
end

--- Общее у аргумента и ключа: описание, допустимые значения и род.
---@param target any Элемент рока
---@param element TntConsoleElement
---@return any target
local function settle(target, element)
    target:description(note(element))

    if element.choices ~= nil then
        target:choices(element.choices)
    end

    local reader = declaration.reader(element)

    if reader ~= nil then
        target:convert(reader)
    end

    return target
end

--- Аргумент команды в разборе рока.
---@param command any Разбор команды
---@param element TntConsoleElement
---@return any
local function add_argument(command, element)
    local target = command:argument(element.name)

    if element.many then
        target:args(element.optional and '*' or '+')
    elseif element.optional then
        target:args('?')
    end

    return settle(target, element)
end

--- Ключ команды в разборе рока.
---
--- Флаг без ключа — `false`, а не пустота: обработчик проверяет
--- `input.force`, не вспоминая, что отсутствие — это `nil`.
---@param command any Разбор команды
---@param element TntConsoleElement
---@return any
local function add_option(command, element)
    local aliases = '--' .. element.name

    if element.short ~= nil then
        aliases = ('-%s %s'):format(element.short, aliases)
    end

    if element.flag then
        return command:flag(aliases):target(element.key):default(false):description(element.description)
    end

    local target = command:option(aliases):target(element.key)

    if element.many then
        target:count(element.required and '+' or '*')
    elseif element.required then
        target:count(1)
    end

    return settle(target, element)
end

--- Разбор одной команды.
---@param root any Разбор приложения
---@param command TntConsoleCommand
---@param asked table
---@return any
local function add_command(root, command, asked)
    -- Строка списка команд — первая строка описания: список читают
    -- глазами, и абзац под каждой командой его бы растянул.
    local summary = (command.description .. '\n'):match('^(.-)\n')
    local parser = root:command(command.name):add_help(false):summary(summary):description(command.description)
    local arguments = {}
    local options = { help_flag(parser, asked) }

    for _, element in ipairs(command.arguments) do
        table.insert(arguments, add_argument(parser, element))
    end

    for _, element in ipairs(command.options) do
        table.insert(options, add_option(parser, element))
    end

    -- Группы нужны ради подписей по-русски: подпись группы рок берёт
    -- у нас, а подписи своих — «Arguments», «Options» — у себя.
    parser:group('Аргументы', unpack(arguments))
    parser:group('Ключи', unpack(options))

    return parser
end

--- Кладёт значение элемента во вход: набранное либо умолчание.
---
--- Умолчание подставляется здесь, а не роком: необязательному аргументу
--- рок его не подставляет вовсе (дополняет значения только до их
--- наименьшего числа, а у необязательного оно ноль), а ключу подставил
--- бы. Одно место для обоих не даёт им разойтись.
---@param input table
---@param element TntConsoleElement
---@param parsed table Итог рока
local function put(input, element, parsed)
    local value = parsed[element.key]

    if value == nil then
        value = element.fallback
    end

    input[element.key] = value
end

--- Значения команды из итога рока: только объявленные поля.
---
--- Итог рока несёт и служебное — имя команды, отметку выбранной
--- команды её именем, — и обработчику оно ни к чему.
---@param command TntConsoleCommand
---@param parsed table
---@return table
local function collect(command, parsed)
    local input = {}

    for _, element in ipairs(command.arguments) do
        put(input, element, parsed)
    end

    for _, element in ipairs(command.options) do
        put(input, element, parsed)
    end

    return input
end

--- Разбирает командную строку.
---@param app TntConsoleApp
---@param argv string[]
---@return TntConsoleOutcome
function Module.parse(app, argv)
    local asked = {}
    local root = argparse(app.name, app.description)
        :add_help(false)
        :require_command(false)
        :command_target(COMMAND)
        :usage(('%s%s [-h] <команда> ...'):format(phrases.USAGE, app.name))
    local parsers = {}
    local commands = {}

    for _, command in ipairs(app.commands) do
        parsers[command.name] = add_command(root, command, asked)
        table.insert(commands, parsers[command.name])
    end

    root:group('Ключи', help_flag(root, asked))
    root:group('Команды', unpack(commands))

    local ok, parsed = root:pparse(argv)

    if asked.parser ~= nil then
        return { help = phrases.usage(asked.parser:get_help()) }
    end

    if not ok then
        -- Отказ показывается со строкой вызова той команды, которую
        -- набрали: у приложения ключей нет, кроме справки, и первое
        -- слово строки — имя команды.
        local where = parsers[argv[1]] or root

        return { refusal = phrases.refusal(parsed), usage = phrases.usage(where:get_usage()) }
    end

    local command = app.named[parsed[COMMAND]]

    if command == nil then
        return { refusal = 'не названа команда', usage = phrases.usage(root:get_help()) }
    end

    return { command = command, input = collect(command, parsed) }
end

return Module
