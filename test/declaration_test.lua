local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.console.declaration')

local console = helper.console

--- Обработчик, которому нечего делать.
local function nothing() end

--- Бросок объявления команды с таким описанием; место — строка проверки.
---@param name any Имя команды
---@param spec any Описание
---@return string|nil
local function refused(name, spec)
    local app = console.new({ name = 'app' })

    return helper.blamed(function()
        app:command(name, spec)
    end)
end

--- Описание команды с такими аргументами и ключами.
---@param arguments table|nil
---@param options table|nil
---@return table
local function spec(arguments, options)
    return { description = 'команда', arguments = arguments, options = options, handler = nothing }
end

g.test_command_names = function()
    local app = console.new({ name = 'app' })

    for _, name in ipairs({ 'probe', 'cache:clear', 'make-seed', 'db_2', 'a' }) do
        app:command(name, spec())
    end

    t.assert_equals(#app.commands, 5)

    for _, name in ipairs({ 'Probe', '9a', ':a', '', 'a b', 'a.b' }) do
        t.assert_equals(
            refused(name, spec()),
            ('имя команды — строка по образцу ^[a-z][a-z0-9:_-]*$, а не «%s»'):format(
                name
            )
        )
    end

    t.assert_equals(
        refused(helper.wrong(7), spec()),
        'имя команды — строка по образцу ^[a-z][a-z0-9:_-]*$, а не число'
    )
end

g.test_command_spec = function()
    t.assert_equals(
        refused('probe', helper.wrong('x')),
        'команда probe — таблица, а не строка'
    )
    t.assert_equals(
        refused('probe', { description = 'x', handler = nothing, argument = {} }),
        'команда probe: ключа «argument» нет, есть arguments, description, handler, options'
    )
    t.assert_equals(
        refused('probe', { handler = nothing }),
        'команда probe.description — непустая строка, а не nil'
    )
    t.assert_equals(
        refused('probe', { description = 'x', handler = 'run' }),
        'команда probe.handler — функция или вызываемая таблица, а не строка'
    )
    t.assert_equals(
        refused('probe', spec({ 'dir' })),
        'команда probe.arguments[1] — таблица, а не строка'
    )
    t.assert_equals(
        refused('probe', spec(nil, { 'x' })),
        'команда probe.options[1] — таблица, а не строка'
    )
end

g.test_duplicate_command = function()
    local app = console.new({ name = 'app' })

    app:command('probe', spec())

    t.assert_equals(
        helper.blamed(function()
            app:command('probe', spec())
        end),
        'команда probe уже объявлена'
    )
    t.assert_equals(#app.commands, 1)
end

g.test_argument_spec = function()
    t.assert_equals(
        refused('probe', spec({ { name = 'dir', description = 'каталог', optinal = true } })),
        'команда probe: аргументы[1]: ключа «optinal» нет, есть choices, default, description, many, name, '
            .. 'optional, type'
    )
    t.assert_equals(
        refused('probe', spec({ { name = 'dir' } })),
        'команда probe: аргументы[1].description — непустая строка, а не nil'
    )
    t.assert_equals(
        refused('probe', spec({ { name = 'dir', description = 'x', type = 'bool' } })),
        'команда probe: аргументы[1].type — одно из «string», «number», «integer», а не «bool»'
    )

    for _, name in ipairs({ 'Dir', 'dry-run', '_x', '1a' }) do
        t.assert_equals(
            refused('probe', spec({ { name = name, description = 'x' } })),
            ('команда probe: аргументы[1].name — строка по образцу ^[a-z][a-z0-9_]*$, а не «%s»'):format(
                name
            )
        )
    end
end

g.test_option_spec = function()
    t.assert_equals(
        refused('probe', spec(nil, { { name = 'x', description = 'x', flags = true } })),
        'команда probe: ключи[1]: ключа «flags» нет, есть choices, default, description, flag, many, name, '
            .. 'required, short, type'
    )

    for _, name in ipairs({ 'Force', 'dry_run', '-x', '2x' }) do
        t.assert_equals(
            refused('probe', spec(nil, { { name = name, description = 'x' } })),
            ('команда probe: ключи[1].name — строка по образцу ^[a-z][a-z0-9-]*$, а не «%s»'):format(
                name
            )
        )
    end

    for _, short in ipairs({ 'ab', '1', '' }) do
        t.assert_equals(
            refused('probe', spec(nil, { { name = 'x', short = short, description = 'x' } })),
            ('команда probe: ключи[1].short — строка по образцу ^%%a$, а не «%s»'):format(
                short
            )
        )
    end
end

g.test_names_accepted = function()
    local app = console.new({ name = 'app' })

    app:command(
        'probe',
        spec({ { name = 'dir_2', description = 'x' } }, {
            { name = 'dry-run-2', description = 'x', flag = true },
            { name = 'x', short = 'X', description = 'x' },
            { name = 'y', short = 'y', description = 'x' },
        })
    )

    t.assert_equals(#app.commands[1].options, 3)
end

g.test_fields_are_unique = function()
    t.assert_equals(
        refused('probe', spec({ { name = 'dir', description = 'x' }, { name = 'dir', description = 'y' } })),
        'команда probe: аргументы[2]: поле «dir» уже занято'
    )
    local underscore = { { name = 'dry_run', description = 'x' } }

    t.assert_equals(
        refused('probe', spec(underscore, { { name = 'dry-run', description = 'y' } })),
        'команда probe: ключи[1]: поле «dry_run» уже занято'
    )
    t.assert_equals(
        refused('probe', spec(nil, { { name = 'help', description = 'x' } })),
        'команда probe: ключи[1]: поле «help» уже занято'
    )
    t.assert_equals(
        refused('probe', spec({ { name = 'help', description = 'x' } })),
        'команда probe: аргументы[1]: поле «help» уже занято'
    )
end

g.test_letters_are_unique = function()
    t.assert_equals(
        refused('probe', spec(nil, { { name = 'host', short = 'h', description = 'x' } })),
        'команда probe: ключи[1]: буква «h» уже занята'
    )
    t.assert_equals(
        refused(
            'probe',
            spec(nil, {
                { name = 'force', short = 'f', description = 'x', flag = true },
                { name = 'format', short = 'f', description = 'y' },
            })
        ),
        'команда probe: ключи[2]: буква «f» уже занята'
    )
end

g.test_flag_has_no_value = function()
    local extras = {
        type = 'number',
        default = 'x',
        choices = { 'a' },
        many = false,
        required = true,
    }

    for key, value in pairs(extras) do
        ---@type table<string, any>
        local option = { name = 'force', description = 'x', flag = true }

        option[key] = value

        t.assert_equals(
            refused('probe', spec(nil, { option })),
            ('команда probe: ключи[1]: флаг — ключ без значения, и %s ему не нужен'):format(
                key
            )
        )
    end
end

g.test_required_option_has_no_default = function()
    t.assert_equals(
        refused('probe', spec(nil, { { name = 'node', description = 'x', required = true, default = 'a' } })),
        'команда probe: ключи[1]: обязательному ключу умолчание не нужно'
    )
end

g.test_list_has_no_default = function()
    t.assert_equals(
        refused('probe', spec({ { name = 'rest', description = 'x', optional = true, many = true, default = 'a' } })),
        'команда probe: аргументы[1]: у списка значений умолчания не бывает'
    )
    t.assert_equals(
        refused('probe', spec(nil, { { name = 'node', description = 'x', many = true, default = 'a' } })),
        'команда probe: ключи[1]: у списка значений умолчания не бывает'
    )
end

g.test_argument_default_needs_optional = function()
    t.assert_equals(
        refused('probe', spec({ { name = 'dir', description = 'x', default = '.' } })),
        'команда probe: аргументы[1]: умолчание бывает только у необязательного аргумента'
    )
end

g.test_argument_order = function()
    t.assert_equals(
        refused(
            'probe',
            spec({ { name = 'rest', description = 'x', many = true }, { name = 'dir', description = 'y' } })
        ),
        'команда probe: аргументы[2]: после списка значений аргументов не бывает'
    )
    t.assert_equals(
        refused(
            'probe',
            spec({
                { name = 'rest', description = 'x', optional = true, many = true },
                { name = 'dir', description = 'y', optional = true },
            })
        ),
        'команда probe: аргументы[2]: после списка значений аргументов не бывает'
    )
    t.assert_equals(
        refused(
            'probe',
            spec({
                { name = 'file', description = 'x', optional = true },
                { name = 'dir', description = 'y' },
            })
        ),
        'команда probe: аргументы[2]: обязательный аргумент не ставится после необязательного'
    )

    local app = console.new({ name = 'app' })

    app:command(
        'probe',
        spec({
            { name = 'dir', description = 'x' },
            { name = 'file', description = 'y', optional = true },
            { name = 'token', description = 'z', optional = true },
            { name = 'rest', description = 'w', optional = true, many = true },
        })
    )

    t.assert_equals(#app.commands[1].arguments, 4)
end

g.test_default_passes_value_checks = function()
    t.assert_equals(
        refused(
            'probe',
            spec(nil, { { name = 'format', description = 'x', choices = { 'json', 'text' }, default = 'xml' } })
        ),
        'команда probe: ключи[1]: умолчание не годится: значение — одно из «json», «text», а не «xml»'
    )
    t.assert_equals(
        refused('probe', spec(nil, { { name = 'timeout', description = 'x', type = 'number', default = 'soon' } })),
        'команда probe: ключи[1]: умолчание не годится: ключ «--timeout» — число, а не «soon»'
    )
    t.assert_equals(
        refused(
            'probe',
            spec({ { name = 'count', description = 'x', optional = true, type = 'integer', default = 1.5 } })
        ),
        'команда probe: аргументы[1]: умолчание не годится: аргумент «count» — целое число, а не «1.5»'
    )
end

g.test_default_takes_kind_of_value = function()
    local seen = {}
    local app = console.new({ name = 'app' })

    app:command('probe', {
        description = 'x',
        arguments = {
            { name = 'count', description = 'x', optional = true, type = 'integer', default = '3' },
            { name = 'label', description = 'x', optional = true, default = 7 },
        },
        options = {
            { name = 'format', description = 'x', choices = { '1', '2' }, default = 2, type = 'integer' },
        },
        handler = function(input)
            seen = input
        end,
    })
    app:call({ 'probe' })

    t.assert_equals(seen, { count = 3, label = '7', format = 2 })
end
