--- Консольные команды приложения: объявление, разбор командной строки
--- роком `argparse`, вывод и запуск отдельным процессом.
---
---     local console = require('tnt.console')
---
---     local app = console.new({ name = 'console.lua', description = 'Команды приложения' })
---
---     app:command('cache:clear', {
---         description = 'Забыть всё в кэше',
---         options = { { name = 'force', short = 'f', flag = true, description = 'не спрашивать' } },
---         handler = function(input, out)
---             out:line('забыто')
---         end,
---     })
---
---     app:main()                                       -- из командной строки
---     app:call({ 'cache:clear', '--force' })           -- из кода: вывод в итоге
---     console.execute('console.lua', { 'cache:clear' }, { timeout = 60 })  -- отдельным процессом
---     console.remote({ uri = '127.0.0.1:3301', call = 'app_command' }):main()  -- на узле
---
--- Командную строку разбирает рок `argparse`, своего разбора здесь нет.
--- Пакет даёт то, чего у рока нет: справку и отказ, которые не завершают
--- процесс, — команду можно позвать из кода узла; слова по-русски; код
--- выхода, различающий отказ, неверный вызов и поломку; вывод, который
--- обработчик пишет, не зная, куда он уйдёт.
---
--- Команда отдельным процессом (`execute`) идёт тем же Tarantool через
--- `tnt-process`: долгая работа без уступки не держит узел, у запуска есть
--- срок, а просроченный процесс убит вместе с группой.
---
--- Команда на узле (`remote`) идёт функцией узла по iproto: узел выполняет
--- командную строку (`app:reply`), а вывод и код выхода повторяет сценарий
--- оператора — с тем кодом, которым команда кончилась на узле.
---
--- Подробно — `docs/console.md`.

local must = require('tnt.must')
local process = require('tnt.process')

local app = require('tnt.console.app')
local remote = require('tnt.console.remote')
local system = require('tnt.console.system')

local Module = {}

--- Команда сделала своё.
Module.OK = app.OK

--- Отказ: обработчик вернул `nil, err` либо `false`.
Module.FAILURE = app.FAILURE

--- Команду набрали неверно: до обработчика дело не дошло.
Module.USAGE = app.USAGE

--- Обработчик бросил: ошибка программиста.
Module.BROKEN = app.BROKEN

--- Команда на узле: узел не ответил — нет связи, права, функции либо срок вышел.
Module.UNAVAILABLE = remote.UNAVAILABLE

--- Настройки `new`.
local NEW = { name = 'not_empty', description = '?string' }

--- Настройки `execute`: те же, что у запуска `tnt-process`.
local EXECUTE = {
    timeout = '?positive',
    input = '?string',
    env = '?table',
    max_output = '?positive',
}

--- Настройки `remote`.
local REMOTE = {
    uri = 'not_empty',
    call = 'not_empty',
    user = '?string',
    password = '?string',
    timeout = '?positive',
}

--- Новое приложение командной строки.
---@param options { name: string, description: string|nil } Имя в строке вызова и что это за приложение
---@return TntConsoleApp
function Module.new(options)
    must.at(2).options(options, 'настройки', NEW)

    return app.new(options.name, options.description)
end

--- Выполняет команду отдельным процессом Tarantool и ждёт её конца.
---
--- Процесс — тот же Tarantool, что у вызывающего, со сценарием `script`
--- и аргументами `argv`. Итог и отказ — те же, что у `tnt-process`:
--- код 0 — итог с выводом, всякий другой код — отказ `exit` с кодом,
--- выводом и потоком ошибок; срок вышел — отказ `timeout`, процесс убит
--- с группой.
---
---     local result, err = console.execute('console.lua', { 'report:build' }, { timeout = 600 })
---@param script string Сценарий приложения командной строки
---@param argv string[]|nil Аргументы: имя команды, её аргументы и ключи
---@param options TntProcessRunOptions|nil Срок, вход, окружение и предел вывода
---@return TntProcessResult|nil result
---@return TntProcessFailure|nil err
function Module.execute(script, argv, options)
    local caller = must.at(2)

    caller.not_empty(script, 'сценарий')
    caller.optional.array_of(argv, 'аргументы', 'string')
    caller.options(options or {}, 'настройки', EXECUTE)

    local command = { system.current().interpreter(), script }

    for _, value in ipairs(argv or {}) do
        table.insert(command, value)
    end

    return process.run(command, options)
end

--- Команда на узле: командную строку выполняет функция узла по iproto.
---
--- Узел публикует функцию, которая зовёт `app:reply(argv)`, а сценарий
--- оператора повторяет её вывод и код выхода у себя. Узел, который
--- не ответил, — код `UNAVAILABLE` и причина в поток ошибок.
---
---     console.remote({
---         uri = '127.0.0.1:3301',
---         user = 'operator',
---         password = secret,
---         call = 'app_command',
---     }):main()
---@param options TntConsoleRemoteOptions Узел, учётка, функция и срок
---@return TntConsoleRemote
function Module.remote(options)
    must.at(2).options(options, 'настройки', REMOTE)

    return remote.new(options)
end

--- Подменяет средства пакета: вывод, аргументы процесса, выход, путь
--- Tarantool и клиент iproto. Только для проверок.
Module._set_source = system._set_source

return Module
