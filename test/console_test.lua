local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.console')

local console = helper.console

--- Сценарий приложения: команда `echo` повторяет слова в вывод, пишет
--- в поток ошибок и кончается кодом, который ей назвали.
local ECHO = [[
local console = require('tnt.console')
local app = console.new({ name = 'child' })

app:command('echo', {
    description = 'Повторить слова',
    arguments = { { name = 'words', description = 'слова', many = true, optional = true } },
    options = { { name = 'code', description = 'код выхода', type = 'integer', default = 0 } },
    handler = function(input, out)
        out:line(table.concat(input.words, ' '))
        out:error('в поток ошибок')

        return input.code
    end,
})

app:main()
]]

g.test_codes = function()
    t.assert_equals({ console.OK, console.FAILURE, console.USAGE, console.BROKEN }, { 0, 1, 2, 70 })
end

g.test_new = function()
    local app = console.new({ name = 'app', description = 'Команды' })

    t.assert_equals({ app.name, app.description, app.commands }, { 'app', 'Команды', {} })
    t.assert_equals(console.new({ name = 'x' }).description, nil)
end

g.test_new_options_are_checked = function()
    t.assert_equals(
        helper.blamed(function()
            console.new(helper.wrong({ name = '' }))
        end),
        'настройки.name — непустая строка, а не пустая'
    )
    t.assert_equals(
        helper.blamed(function()
            console.new(helper.wrong({ name = 'app', title = 'x' }))
        end),
        'настройки: ключа «title» нет, есть description, name'
    )
end

g.test_execute_command_in_process = function()
    local script = helper.script(ECHO)
    local result, err = console.execute(script, { 'echo', 'один', 'два' }, { timeout = 30 })

    t.assert_equals(err, nil)
    t.assert_equals(result, { code = 0, stdout = 'один два\n', stderr = 'в поток ошибок\n' })
end

g.test_execute_code_is_failure = function()
    local script = helper.script(ECHO)
    local result, err = console.execute(script, { 'echo', '--code', '3', 'слово' }, { timeout = 30 })

    t.assert_equals(result, nil)
    t.assert_equals(
        { err.kind, err.code, err.stdout, err.stderr },
        { 'exit', 3, 'слово\n', 'в поток ошибок\n' }
    )
end

g.test_execute_without_arguments = function()
    local script = helper.script(ECHO)
    local _, err = console.execute(script)

    t.assert_equals(err.code, 2)
    t.assert_str_contains(err.stderr, 'Ошибка: не названа команда')
end

g.test_execute_input_and_timeout = function()
    local script = helper.script([[
local console = require('tnt.console')
local app = console.new({ name = 'child' })

app:command('read', {
    description = 'Прочитать вход',
    handler = function(_, out)
        out:line(io.read('*a'))
    end,
})
app:command('wait', {
    description = 'Ждать',
    handler = function()
        require('fiber').sleep(30)
    end,
})
app:main()
]])

    t.assert_equals(console.execute(script, { 'read' }, { input = 'вход', timeout = 30 }).stdout, 'вход\n')

    local _, err = console.execute(script, { 'wait' }, { timeout = 0.5 })

    t.assert_equals(err.kind, 'timeout')
end

g.test_execute_uses_interpreter = function()
    -- На месте Tarantool — программа, которая печатает, что получила:
    -- видно, как собрана командная строка.
    console._set_source({
        interpreter = function()
            return '/bin/echo'
        end,
    })

    t.assert_equals(
        console.execute('console.lua', { 'probe', '-t', '5' }),
        { code = 0, stdout = 'console.lua probe -t 5\n', stderr = '' }
    )
    t.assert_equals(console.execute('console.lua').stdout, 'console.lua\n')
end

g.test_execute_arguments_are_checked = function()
    t.assert_equals(
        helper.blamed(function()
            console.execute(helper.wrong(''))
        end),
        'сценарий — непустая строка, а не пустая'
    )
    t.assert_equals(
        helper.blamed(function()
            console.execute('console.lua', helper.wrong({ 'probe', 5 }))
        end),
        'аргументы[2] — строка, а не число'
    )
    t.assert_equals(
        helper.blamed(function()
            console.execute('console.lua', {}, helper.wrong({ cwd = '/tmp' }))
        end),
        'настройки: ключа «cwd» нет, есть env, input, max_output, timeout'
    )
end

g.test_arguments_of_process = function()
    local saved = arg
    local arguments = helper.system.current().arguments

    rawset(_G, 'arg', { [-1] = '/usr/bin/tarantool', [0] = 'console.lua', 'probe', 'd' })

    local list = arguments()

    rawset(_G, 'arg', saved)

    t.assert_equals(list, { 'probe', 'd' })
end

g.test_interpreter_of_process = function()
    local saved = arg
    local interpreter = helper.system.current().interpreter

    t.assert_equals(interpreter(), arg[-1])

    rawset(_G, 'arg', {})

    local fallback = interpreter()

    rawset(_G, 'arg', saved)

    t.assert_equals(fallback, 'tarantool')
end

g.test_process_streams = function()
    local source = helper.system.current()

    -- Что именно уходит в потоки, сверяет ребёнок (`execute` выше): вывод
    -- процесса проверок читает luatest, и сверить его здесь нечем. Здесь —
    -- что запись в настоящие потоки идёт и не бросает.
    t.assert_equals({ source.stdout(''), source.stderr('') }, {})
end
