local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.console.app')

local console = helper.console

--- Строка вызова команды `probe` приложения ниже — так, как её пишет рок.
local PROBE_USAGE = table.concat({
    'Вызов: recovery.lua probe [-h] [-t <timeout>] [--dry-run]',
    '       [--node <node>] [--format {json,text}] [-l <limit>] <directory>',
    '       [<file>] [<rest>] ...',
}, '\n')

--- Справка приложения ниже.
local ROOT_HELP = table.concat({
    'Вызов: recovery.lua [-h] <команда> ...',
    '',
    'Разбор журналов узла',
    '',
    'Ключи:',
    '   -h, --help            показать эту справку и выйти',
    '',
    'Команды:',
    '   probe                 Прочитать записи файла',
    '   noop                  Ничего не делать',
}, '\n')

--- Приложение с командой на все виды аргументов и ключей.
---
--- Обработчик отдаёт вход тем, что ему велели вернуть, и кладёт его
--- в `seen`: проверка смотрит, что дошло до обработчика.
---@param answer function Что вернуть: зовётся с входом и выводом
---@return TntConsoleApp app
---@return table seen
local function build(answer)
    local seen = {}
    local app = console.new({ name = 'recovery.lua', description = 'Разбор журналов узла' })

    app:command('probe', {
        description = 'Прочитать записи файла\nи назвать последний счётчик',
        arguments = {
            { name = 'directory', description = 'каталог журналов' },
            { name = 'file', description = 'имя файла', optional = true, default = 'last.xlog' },
            { name = 'rest', description = 'прочее', optional = true, many = true },
        },
        options = {
            { name = 'timeout', short = 't', description = 'срок, с', type = 'number', default = 5 },
            { name = 'dry-run', description = 'ничего не трогать', flag = true },
            { name = 'node', description = 'узел', many = true },
            { name = 'format', description = 'вид', choices = { 'json', 'text' }, default = 'text' },
            { name = 'limit', short = 'l', description = 'предел', type = 'integer' },
        },
        handler = function(input, out)
            seen.input = input

            return answer(input, out)
        end,
    })
    app:command('noop', {
        description = 'Ничего не делать',
        handler = function() end,
    })

    return app, seen
end

--- Вызов из кода: код, вывод и поток ошибок одной таблицей.
---@param app TntConsoleApp
---@param argv string[]
---@return { code: integer, stdout: string, stderr: string }
local function outcome(app, argv)
    local result, err = app:call(argv)
    local value = (result or err) --[[@as { code: integer, stdout: string, stderr: string }]]

    return { code = value.code, stdout = value.stdout, stderr = value.stderr }
end

--- Отказ разбора команды `probe`: строка вызова и сам отказ.
---@param refusal string
---@return table
local function probe_refusal(refusal)
    return { code = 2, stdout = '', stderr = PROBE_USAGE .. '\n\nОшибка: ' .. refusal .. '\n' }
end

g.test_root_help = function()
    local app = build(function() end)

    t.assert_equals(outcome(app, { '--help' }), { code = 0, stdout = ROOT_HELP .. '\n', stderr = '' })
    t.assert_equals(outcome(app, { '-h' }).stdout, ROOT_HELP .. '\n')
end

g.test_command_help = function()
    local app = build(function() end)
    local help = table.concat({
        PROBE_USAGE,
        '',
        'Прочитать записи файла',
        'и назвать последний счётчик',
        '',
        'Аргументы:',
        '   directory             каталог журналов',
        '   file                  имя файла (по умолчанию: last.xlog)',
        '   rest                  прочее',
        '',
        'Ключи:',
        '   -h, --help            показать эту справку и выйти',
        '          -t <timeout>,  срок, с (по умолчанию: 5)',
        '   --timeout <timeout>',
        '   --dry-run             ничего не трогать',
        '   --node <node>         узел',
        '   --format {json,text}  вид (по умолчанию: text)',
        '        -l <limit>,      предел',
        '   --limit <limit>',
    }, '\n')

    t.assert_equals(outcome(app, { 'probe', '--help' }), { code = 0, stdout = help .. '\n', stderr = '' })
end

g.test_help_wins_over_later_refusal = function()
    local app = build(function() end)

    -- Справку просили раньше, чем нашёлся отказ: оператор хотел справку.
    t.assert_equals(outcome(app, { 'probe', '-h', '--bad' }).code, 0)
    t.assert_equals(outcome(app, { 'probe', '--bad', '-h' }), probe_refusal('ключа «--bad» нет'))
end

g.test_help_of_command_without_elements = function()
    local app = build(function() end)
    local help = table.concat({
        'Вызов: recovery.lua noop [-h]',
        '',
        'Ничего не делать',
        '',
        'Ключи:',
        '   -h, --help            показать эту справку и выйти',
    }, '\n')

    t.assert_equals(outcome(app, { 'noop', '-h' }).stdout, help .. '\n')
end

g.test_no_command = function()
    local app = build(function() end)

    t.assert_equals(outcome(app, {}), {
        code = 2,
        stdout = '',
        stderr = ROOT_HELP .. '\n\nОшибка: не названа команда\n',
    })
end

g.test_root_refusals_show_root_usage = function()
    local app = build(function() end)
    local usage = 'Вызов: recovery.lua [-h] <команда> ...\n\nОшибка: '

    t.assert_equals(
        outcome(app, { 'prob' }).stderr,
        usage .. 'команды «prob» нет\nможет быть, «probe»?\n'
    )
    t.assert_equals(outcome(app, { 'x' }).stderr, usage .. 'команды «x» нет\n')
    t.assert_equals(outcome(app, { '-v' }).stderr, usage .. 'ключа «-v» нет\nможет быть, «-h»?\n')
end

g.test_argument_refusals = function()
    local app = build(function() end)

    t.assert_equals(outcome(app, { 'probe' }), probe_refusal('не хватает аргумента «directory»'))
    t.assert_equals(
        outcome(app, { 'probe', '-x', 'd' }),
        probe_refusal('ключа «-x» нет\nможет быть, одно из: «-h», «-l», «-t»?')
    )
    t.assert_equals(
        outcome(app, { 'probe', 'd', '--timeout' }),
        probe_refusal('ключу «--timeout» нужно значение')
    )
    t.assert_equals(
        outcome(app, { 'probe', 'd', '--dry-run=1' }),
        probe_refusal('ключ «--dry-run» значения не берёт')
    )
    t.assert_equals(
        outcome(app, { 'probe', 'd', '--format', 'xml' }),
        probe_refusal('ключ «--format» — одно из «json», «text»')
    )
end

g.test_value_kind_refusals = function()
    local app = build(function() end)

    t.assert_equals(
        outcome(app, { 'probe', 'd', '-t', 'abc' }),
        probe_refusal('ключ «--timeout» — число, а не «abc»')
    )
    t.assert_equals(outcome(app, { 'probe', 'd', '-t', 'nan' }).code, 2)
    t.assert_equals(outcome(app, { 'probe', 'd', '-t', 'inf' }).code, 2)
    t.assert_equals(outcome(app, { 'probe', 'd', '-t', '-1e400' }).code, 2)
    t.assert_equals(
        outcome(app, { 'probe', 'd', '-l', '1.5' }),
        probe_refusal('ключ «--limit» — целое число, а не «1.5»')
    )
    t.assert_equals(outcome(app, { 'probe', 'd', '-l', 'x' }).code, 2)
end

g.test_argument_choices_and_count = function()
    local app = console.new({ name = 'app' })

    app:command('set', {
        description = 'Задать уровень',
        arguments = { { name = 'level', description = 'уровень', choices = { 'info', 'debug' } } },
        options = { { name = 'node', description = 'узел', required = true } },
        handler = function() end,
    })
    app:command('tag', {
        description = 'Пометить',
        arguments = { { name = 'names', description = 'метки', many = true } },
        options = { { name = 'by', description = 'кто', required = true, many = true } },
        handler = function() end,
    })

    local usage = 'Вызов: app set [-h] --node <node> {info,debug}\n\nОшибка: '

    t.assert_equals(
        outcome(app, { 'set', 'warn' }).stderr,
        usage .. 'аргумент «level» — одно из «info», «debug»\n'
    )
    t.assert_equals(outcome(app, { 'set', 'info' }).stderr, usage .. 'не хватает ключа «--node»\n')
    t.assert_equals(
        outcome(app, { 'set', 'info', 'x', '--node', 'a' }).stderr,
        usage .. 'лишний аргумент\n'
    )
    t.assert_equals(outcome(app, { 'set', 'info', '--node', 'a' }).code, 0)
    t.assert_equals(
        outcome(app, { 'tag', '--by', 'a' }).stderr,
        'Вызов: app tag [-h] --by <by> <names> [<names>] ...\n\nОшибка: не хватает аргумента «names»\n'
    )
    t.assert_equals(outcome(app, { 'tag', 'x' }).code, 2)
end

g.test_input_with_defaults = function()
    local app, seen = build(function() end)

    t.assert_equals(outcome(app, { 'probe', 'data' }).code, 0)
    t.assert_equals(seen.input, {
        directory = 'data',
        file = 'last.xlog',
        rest = {},
        timeout = 5,
        dry_run = false,
        node = {},
        format = 'text',
    })
end

g.test_input_given = function()
    local app, seen = build(function() end)

    outcome(app, {
        'probe',
        '-t',
        '0.5',
        '--dry-run',
        '--node',
        'a',
        '--node',
        'b',
        '--format',
        'json',
        '-l',
        '3',
        'data',
        'one.xlog',
        'x',
        'y',
    })

    t.assert_equals(seen.input, {
        directory = 'data',
        file = 'one.xlog',
        rest = { 'x', 'y' },
        timeout = 0.5,
        dry_run = true,
        node = { 'a', 'b' },
        format = 'json',
        limit = 3,
    })
end

g.test_input_after_separator = function()
    local app, seen = build(function() end)

    -- После `--` ключей нет: значение со знаком минус — аргумент.
    outcome(app, { 'probe', '--', '-5', '--help' })

    t.assert_equals({ seen.input.directory, seen.input.file }, { '-5', '--help' })
end

g.test_handler_results = function()
    local cases = {
        { function() end, { code = 0, stdout = '', stderr = '' } },
        {
            function()
                return true, 'лишнее'
            end,
            { code = 0, stdout = '', stderr = '' },
        },
        {
            function()
                return nil
            end,
            { code = 0, stdout = '', stderr = '' },
        },
        {
            function()
                return nil, 'не вышло'
            end,
            { code = 1, stdout = '', stderr = 'не вышло\n' },
        },
        {
            function()
                return false
            end,
            { code = 1, stdout = '', stderr = '' },
        },
        {
            function()
                return false, { 'причина' }
            end,
            { code = 1, stdout = '', stderr = 'table: ' },
        },
        {
            function()
                return 0
            end,
            { code = 0, stdout = '', stderr = '' },
        },
        {
            function()
                return 3
            end,
            { code = 3, stdout = '', stderr = '' },
        },
        {
            function()
                return 255
            end,
            { code = 255, stdout = '', stderr = '' },
        },
    }

    for at, case in ipairs(cases) do
        local app = build(case[1])
        local got = outcome(app, { 'probe', 'd' })

        got.stderr = got.stderr:gsub('0x%x+\n$', '')
        t.assert_equals(got, case[2], ('случай %d'):format(at))
    end
end

g.test_output_goes_to_result = function()
    local app = build(function(input, out)
        out:line('каталог: %s', input.directory)
        out:error('внимание')
    end)

    t.assert_equals(
        app:call({ 'probe', 'd' }),
        { code = 0, stdout = 'каталог: d\n', stderr = 'внимание\n' }
    )
end

g.test_wrong_code_is_broken = function()
    local cases = {
        { 256, 'код выхода — число от 0 до 255, а не 256' },
        { -1, 'код выхода — число от 0 до 255, а не -1' },
        { 1.5, 'код выхода — целое число, а не 1.5' },
    }

    for _, case in ipairs(cases) do
        local app = build(function()
            return case[1]
        end)

        t.assert_equals(outcome(app, { 'probe', 'd' }), {
            code = 70,
            stdout = '',
            stderr = ('команда probe сломалась: %s\n'):format(case[2]),
        })
    end
end

g.test_throw_is_broken_with_stack = function()
    local app = build(function(_, out)
        out:line('начали')
        error('поломка обработчика')
    end)
    local got = outcome(app, { 'probe', 'd' })

    t.assert_equals({ got.code, got.stdout }, { 70, 'начали\n' })
    -- Стек начинается с броска, а не с перехватчика пакета.
    t.assert_str_matches(
        got.stderr,
        'команда probe сломалась: .*app_test%.lua:%d+: поломка обработчика\n'
            .. "stack traceback:\n\t%[C%]: in function 'error'\n\t[^\n]*app_test%.lua:%d+: in function .*"
    )
end

g.test_fault_stack_starts_at_faulting_line = function()
    local app = build(function(input)
        return input.missing.field
    end)
    local got = outcome(app, { 'probe', 'd' })

    t.assert_str_matches(
        got.stderr,
        "команда probe сломалась: .*app_test%.lua:%d+: attempt to index field 'missing' %(a nil value%)\n"
            .. 'stack traceback:\n\t[^\n]*app_test%.lua:%d+: in function .*'
    )
end

g.test_call_failure = function()
    local app = build(function()
        return nil, 'не вышло'
    end)
    local result, refusal = app:call({ 'probe', 'd' })
    local err = refusal --[[@as TntProcessFailure]]

    t.assert_equals(result, nil)
    t.assert_equals({ err.kind, err.program, tostring(err), err.code, err.stdout, err.stderr }, {
        'exit',
        'recovery.lua',
        'вызов recovery.lua кончился с кодом 1',
        1,
        '',
        'не вышло\n',
    })
end

-- Итог одной таблицей при любом коде: его отдаёт по iproto функция
-- узла, и сценарий оператора повторяет код, вывод и поток ошибок.
g.test_reply_is_one_table_at_any_code = function()
    local app = build(function(input, out)
        out:line('каталог: %s', input.directory)

        if input.directory == 'плохой' then
            return nil, 'не вышло'
        end
    end)

    t.assert_equals(app:reply({ 'probe', 'd' }), { code = 0, stdout = 'каталог: d\n', stderr = '' })
    t.assert_equals(
        app:reply({ 'probe', 'плохой' }),
        { code = 1, stdout = 'каталог: плохой\n', stderr = 'не вышло\n' }
    )
    t.assert_equals(app:reply({ 'probe', '--help' }).code, 0)

    local usage = app:reply({ 'probe' })

    t.assert_equals({ usage.code, usage.stdout }, { 2, '' })
    t.assert_str_contains(usage.stderr, 'Ошибка: не хватает аргумента «directory»')
end

g.test_run_writes_to_process_streams = function()
    local written = {}
    local app = build(function(_, out)
        out:line('вывод')
        out:error('ошибки')

        return 4
    end)

    console._set_source({
        stdout = function(text)
            table.insert(written, { 'stdout', text })
        end,
        stderr = function(text)
            table.insert(written, { 'stderr', text })
        end,
    })

    t.assert_equals(app:run({ 'probe', 'd' }), 4)
    t.assert_equals(written, { { 'stdout', 'вывод\n' }, { 'stderr', 'ошибки\n' } })
end

g.test_main_exits_with_code = function()
    local exited = {}
    local app = build(function(input)
        return #input.rest
    end)

    console._set_source({
        arguments = function()
            return { 'probe', 'd', 'f', 'a', 'b' }
        end,
        exit = function(code)
            table.insert(exited, code)
        end,
    })

    app:main()

    t.assert_equals(exited, { 2 })
end

g.test_command_returns_app = function()
    local app = console.new({ name = 'app' })

    t.assert_is(app:command('noop', { description = 'ничего', handler = function() end }), app)
end

g.test_argv_is_checked = function()
    local app = build(function() end)

    t.assert_equals(
        helper.blamed(function()
            app:run(helper.wrong({ 'probe', 1 }))
        end),
        'аргументы[2] — строка, а не число'
    )
    t.assert_equals(
        helper.blamed(function()
            app:call(helper.wrong('probe'))
        end),
        'аргументы — массив, а не строка'
    )
    t.assert_equals(
        helper.blamed(function()
            app:reply(helper.wrong(nil))
        end),
        'аргументы — массив, а не nil'
    )
end
