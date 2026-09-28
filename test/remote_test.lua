--- Проверки команды на узле: `console.remote` и функция узла на `app:reply`.
---
--- Узел настоящий: отказ соединения, права и срока — тексты `net.box`,
--- и двойник показал бы лишь, что мы правильно разговариваем сами с собой.
--- Функция узла собрана из исходников пакета, учётке выдано право только
--- на неё. Двойник `net.box` — там, где проверяется проводка: что ушло
--- в соединение и что соединение закрыто.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.console.remote')

local console = helper.console

--- Учётка оператора: право у неё только на функции узла ниже.
local USER = 'operator'
local PASSWORD = 'operator-secret'

--- Функция узла, которая выполняет командную строку.
local CALL = 'probe_command'

---@type table
local server

--- Адрес узла в тексте отказа: путь сокета `uri.format` пишет с `unix/:`.
---@type string
local shown

g.before_all(function()
    server = helper.start_node('console')
    shown = 'unix/:' .. server.net_box_uri

    server:exec(function(user, password)
        local fiber = require('fiber')
        local node_console = require('tnt.console')

        local app = node_console.new({ name = 'console.lua', description = 'Команды узла' })

        app:command('greet', {
            description = 'Поздороваться',
            arguments = { { name = 'who', description = 'с кем' } },
            handler = function(input, out)
                out:line('здравствуй, %s', input.who)
                out:error('узел ответил')
            end,
        })
        app:command('refuse', {
            description = 'Отказать',
            handler = function()
                return nil, 'наполнитель customers не выполнен'
            end,
        })
        app:command('boom', {
            description = 'Сломаться',
            handler = function()
                error('поломка на узле')
            end,
        })

        rawset(_G, 'probe_command', function(argv)
            return app:reply(argv)
        end)
        -- Функция, на которую права у учётки нет.
        rawset(_G, 'probe_hidden', function(argv)
            return app:reply(argv)
        end)
        -- Функции, которые отвечают не итогом команды.
        rawset(_G, 'probe_odd', function()
            return { code = 300, stdout = '', stderr = '' }
        end)
        rawset(_G, 'probe_silent', function() end)
        rawset(_G, 'probe_extra', function()
            return { code = 0, stdout = '', stderr = '', pid = 1 }
        end)
        -- Функция, которая отвечает позже срока.
        rawset(_G, 'probe_slow', function()
            fiber.sleep(3)

            return { code = 0, stdout = '', stderr = '' }
        end)

        box.schema.user.create(user, { password = password })
        box.schema.user.create('blind', { password = password })

        for _, name in ipairs({ 'probe_command', 'probe_odd', 'probe_silent', 'probe_extra', 'probe_slow' }) do
            box.schema.user.grant(user, 'execute', 'lua_call', name)
        end
    end, { USER, PASSWORD })
end)

g.after_all(function()
    helper.stop_node(server)
end)

--- Настройки команды на узле с учёткой оператора поверх названных.
---@param overrides table|nil
---@return table
local function options(overrides)
    local given = { uri = server.net_box_uri, user = USER, password = PASSWORD, call = CALL }

    for key, value in pairs(overrides or {}) do
        given[key] = value
    end

    return given
end

--- Выполняет командную строку на узле: код и оба потока процесса.
---@param given table Настройки `console.remote`
---@param argv string[]
---@return { code: integer, stdout: string, stderr: string }
local function ran(given, argv)
    local written = { stdout = {}, stderr = {} }

    console._set_source({
        stdout = function(text)
            table.insert(written.stdout, text)
        end,
        stderr = function(text)
            table.insert(written.stderr, text)
        end,
    })

    local code = console.remote(given):run(argv)

    return { code = code, stdout = table.concat(written.stdout), stderr = table.concat(written.stderr) }
end

-- ─── Итог команды ───────────────────────────────────────────────────────────

g.test_output_and_code_are_those_of_the_node = function()
    t.assert_equals(
        ran(options(), { 'greet', 'мир' }),
        { code = 0, stdout = 'здравствуй, мир\n', stderr = 'узел ответил\n' }
    )
    t.assert_equals(
        ran(options(), { 'refuse' }),
        { code = console.FAILURE, stdout = '', stderr = 'наполнитель customers не выполнен\n' }
    )

    local usage = ran(options(), { 'greet' })

    t.assert_equals({ usage.code, usage.stdout }, { console.USAGE, '' })
    t.assert_str_contains(usage.stderr, 'Вызов: console.lua greet [-h] <who>')

    local broken = ran(options(), { 'boom' })

    t.assert_equals({ broken.code, broken.stdout }, { console.BROKEN, '' })
    t.assert_str_contains(broken.stderr, 'команда boom сломалась: ')
    t.assert_str_contains(broken.stderr, 'поломка на узле')
end

g.test_main_exits_with_the_code_of_the_node = function()
    local exited = {}

    console._set_source({
        stderr = function() end,
        arguments = function()
            return { 'refuse' }
        end,
        exit = function(code)
            table.insert(exited, code)
        end,
    })

    console.remote(options()):main()

    t.assert_equals(exited, { console.FAILURE })
end

-- ─── Узел не ответил ────────────────────────────────────────────────────────

g.test_no_answer_is_unavailable_with_the_reason = function()
    t.assert_equals(console.UNAVAILABLE, 69)

    local denied = "Execute access to function 'probe_hidden' is denied for user 'operator'"

    t.assert_equals(
        ran(options({ call = 'probe_hidden' }), { 'greet', 'мир' }),
        { code = 69, stdout = '', stderr = ('нет ответа узла %s: %s\n'):format(shown, denied) }
    )

    -- Учётка без права на функцию: отказ называет её.
    t.assert_str_contains(
        ran(options({ user = 'blind' }), { 'greet', 'мир' }).stderr,
        "Execute access to function 'probe_command' is denied for user 'blind'"
    )

    local wrong = ran(options({ password = 'не тот' }), { 'greet', 'мир' })

    t.assert_equals({ wrong.code, wrong.stdout }, { 69, '' })
    t.assert_str_contains(wrong.stderr, 'User not found or supplied credentials are invalid')

    local closed = ran(options({ uri = 'unix/:/nonexistent/console.sock' }), { 'greet', 'мир' })

    t.assert_equals({ closed.code, closed.stdout }, { 69, '' })
    t.assert_str_contains(closed.stderr, 'нет ответа узла unix/:/nonexistent/console.sock: ')
    t.assert_str_contains(closed.stderr, 'No such file or directory')
end

g.test_the_address_is_shown_without_the_password = function()
    local refused = ran(options({ uri = 'operator:hunter2@unix/:/nonexistent/console.sock' }), { 'greet' })

    t.assert_str_contains(refused.stderr, 'нет ответа узла operator@unix/:/nonexistent/console.sock: ')
    t.assert_not_str_contains(refused.stderr, 'hunter2')

    -- Адрес, который не разобрать, показан как есть: отказ даёт сам `net.box`.
    t.assert_equals(ran(options({ uri = 'не адрес ::' }), { 'greet' }), {
        code = 69,
        stdout = '',
        stderr = 'нет ответа узла не адрес ::: Incorrect URI: expected host:service or /unix.socket\n',
    })
end

g.test_an_answer_after_the_timeout_is_unavailable = function()
    t.assert_equals(
        ran(options({ call = 'probe_slow', timeout = 0.2 }), { 'greet' }),
        { code = 69, stdout = '', stderr = ('нет ответа узла %s: timed out\n'):format(shown) }
    )
end

-- ─── Ответ не того вида ─────────────────────────────────────────────────────

g.test_an_answer_that_is_not_a_reply_is_broken = function()
    local prefix = ('узел %s ответил не итогом команды: '):format(shown)

    t.assert_equals(ran(options({ call = 'probe_odd' }), { 'greet' }), {
        code = console.BROKEN,
        stdout = '',
        stderr = prefix .. 'ответ узла.code — число от 0 до 255, а не 300\n',
    })
    t.assert_equals(ran(options({ call = 'probe_silent' }), { 'greet' }), {
        code = console.BROKEN,
        stdout = '',
        stderr = prefix .. 'ответ узла — таблица, а не nil\n',
    })
    t.assert_equals(ran(options({ call = 'probe_extra' }), { 'greet' }), {
        code = console.BROKEN,
        stdout = '',
        stderr = prefix .. 'ответ узла: ключа «pid» нет, есть code, stderr, stdout\n',
    })
end

-- ─── Проводка ───────────────────────────────────────────────────────────────

--- Двойник `net.box`: записывает, с чем открыли соединение и что позвали.
---@param answer fun(): any Что ответить на вызов; бросок — отказ вызова
---@return table seen
local function fake_net_box(answer)
    local seen = { closed = 0 }

    console._set_source({
        stdout = function() end,
        stderr = function() end,
        net_box = function()
            return {
                connect = function(address, opts)
                    seen.connect = { address, opts }

                    return {
                        call = function(_, name, args, call_opts)
                            seen.call = { name, args, call_opts }

                            return answer()
                        end,
                        close = function()
                            seen.closed = seen.closed + 1
                        end,
                    }
                end,
            }
        end,
    })

    return seen
end

g.test_the_connection_takes_the_account_and_the_timeout_and_is_closed = function()
    local seen = fake_net_box(function()
        return { code = 3, stdout = '', stderr = '' }
    end)
    local remote = console.remote({
        uri = '127.0.0.1:3301',
        user = USER,
        password = PASSWORD,
        call = CALL,
        timeout = 7,
    })

    t.assert_equals(remote:run({ 'greet', 'мир' }), 3)
    t.assert_equals(seen, {
        connect = { '127.0.0.1:3301', { user = USER, password = PASSWORD, connect_timeout = 7 } },
        call = { CALL, { { 'greet', 'мир' } }, { timeout = 7 } },
        closed = 1,
    })

    -- Срок по умолчанию — минута, и соединению, и ответу.
    seen = fake_net_box(function()
        error('Connection refused')
    end)

    t.assert_equals(console.remote({ uri = '127.0.0.1:3301', call = CALL }):run({}), 69)
    t.assert_equals(seen.connect[2], { connect_timeout = 60 })
    t.assert_equals(seen.call[3], { timeout = 60 })
    t.assert_equals(seen.closed, 1, 'соединение закрыто и после отказа вызова')
end

g.test_the_password_is_not_a_field = function()
    local remote = console.remote(options())

    t.assert_equals({ remote.uri, remote.call, remote.user, remote.timeout }, {
        server.net_box_uri,
        CALL,
        USER,
        60,
    })

    for key, value in pairs(remote) do
        t.assert_not_equals(value, PASSWORD, ('пароль виден полем %s'):format(key))
    end
end

-- ─── Проверки аргументов ────────────────────────────────────────────────────

g.test_options_and_argv_are_checked_at_the_caller = function()
    t.assert_equals(
        helper.blamed(function()
            console.remote(helper.wrong({ call = CALL }))
        end),
        'настройки.uri — непустая строка, а не nil'
    )
    t.assert_equals(
        helper.blamed(function()
            console.remote(helper.wrong({ uri = '127.0.0.1:3301', call = '' }))
        end),
        'настройки.call — непустая строка, а не пустая'
    )
    t.assert_equals(
        helper.blamed(function()
            console.remote(helper.wrong({ uri = '127.0.0.1:3301', call = CALL, timeout = 0 }))
        end),
        'настройки.timeout — число больше 0, а не 0'
    )
    t.assert_equals(
        helper.blamed(function()
            console.remote(helper.wrong({ uri = '127.0.0.1:3301', call = CALL, login = USER }))
        end),
        'настройки: ключа «login» нет, есть call, password, timeout, uri, user'
    )
    t.assert_equals(
        helper.blamed(function()
            console.remote(helper.wrong({ uri = '127.0.0.1:3301', call = CALL, password = 1 }))
        end),
        'настройки.password — строка, а не число'
    )

    local remote = console.remote(options())

    t.assert_equals(
        helper.blamed(function()
            remote:run(helper.wrong({ 'greet', 1 }))
        end),
        'аргументы[2] — строка, а не число'
    )
end
