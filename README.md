# tnt-console

Консольные команды приложения на Tarantool: команда объявляется
таблицей, командную строку разбирает рок `argparse`, код выхода различает
удачу, отказ, неверный вызов и поломку, а ту же команду зовут из кода,
отдельным процессом и на живом узле по iproto.

```lua
local console = require('tnt.console')

local app = console.new({ name = 'console.lua', description = 'Команды приложения' })

app:command('cache:clear', {
    description = 'Забыть записи кэша',
    options = { { name = 'force', short = 'f', flag = true, description = 'без слова подтверждения' } },
    handler = function(input, out)
        if not input.force then
            return nil, 'нужен ключ --force'          -- отказ: код 1, причина в поток ошибок
        end

        out:line('забыто')
    end,
})

app:main()                                            -- tarantool console.lua cache:clear -f
app:call({ 'cache:clear', '-f' })                     --> { code = 0, stdout = 'забыто\n', stderr = '' }
console.execute('console.lua', { 'cache:clear', '-f' }, { timeout = 60 })  -- отдельным процессом

-- на узле: функция, которой учётке оператора выдано право lua_call
rawset(_G, 'app_command', function(argv) return app:reply(argv) end)
-- у оператора: вывод и код выхода — те, что у команды на узле
console.remote({ uri = '127.0.0.1:3301', user = 'operator', password = secret, call = 'app_command' }):main()
```

Зависимости: рок [argparse](https://github.com/luarocks/argparse) 0.7.2,
[tnt-process](https://github.com/tnt-skein/tnt-process),
[tnt-debug](https://github.com/tnt-skein/tnt-debug),
[tnt-must](https://github.com/tnt-skein/tnt-must),
[tnt-external](https://github.com/tnt-skein/tnt-external).

## Зачем

- **Справка и отказ разбора не завершают процесс.** У рока `--help`
  и ошибка разбора зовут `os.exit`; здесь это итог вызова, и команда,
  позванная из кода узла, узел не роняет.
- **По-русски.** Отказы разбора, строка вызова и справка — по-русски,
  а неверное объявление — бросок на строке объявления.
- **Код выхода со смыслом.** 0 — сделано, 1 — отказ обработчика,
  2 — команду набрали неверно, 70 — обработчик бросил, 69 — узел
  не ответил на команду.
- **Вывод, не знающий, куда уходит.** Строки, таблица, выровненная
  по знакам UTF-8, и показ значения с тайнами под отметкой — в потоки
  процесса либо в итог вызова из кода.
- **Отдельным процессом.** `execute` запускает команду тем же Tarantool
  со сроком: долгая работа без уступки не держит узел.
- **На живом узле.** `remote` зовёт по iproto функцию узла на `reply`
  и кончается тем кодом, которым команда кончилась на узле; учётке
  хватает права на одну функцию, `eval` ей не нужен.

## Установка

```sh
tt rocks install tnt-console --server=https://tnt-skein.github.io/rocks
```

Или из исходников — зависимости и тогда ставятся с того же сервера:

```sh
git clone https://github.com/tnt-skein/tnt-console.git
cd tnt-console && tt rocks make --server=https://tnt-skein.github.io/rocks
```

## Как пользоваться

| Вызов | Что делает |
|---|---|
| `console.new({ name, description })` | приложение командной строки |
| `app:command(name, spec)` | объявляет команду: `description`, `arguments`, `options`, `handler` |
| `app:main()` | выполняет команду из аргументов процесса и кончает процесс её кодом |
| `app:run(argv)` | выполняет командную строку с выводом в потоки процесса; отдаёт код |
| `app:call(argv)` | из кода: итог `{ code = 0, stdout, stderr }`, всякий другой код — отказ `exit` |
| `app:reply(argv)` | итог одной таблицей при любом коде — тело функции узла |
| `console.execute(script, argv, opts)` | команда отдельным процессом Tarantool со сроком |
| `console.remote(opts)` | команда на узле по iproto: `run(argv)` отдаёт код, `main()` кончает им процесс |

Обработчик получает вход — значения аргументов и ключей по именам — и
вывод: `out:line`, `out:error`, `out:table`, `out:describe`. Неверное
объявление — бросок на строке объявления:

```lua
app:command('probe', {
    description = 'Прочитать файл',
    arguments = {
        { name = 'file', description = 'файл', optional = true },
        { name = 'directory', description = 'каталог' },
    },
    handler = function() end,
})
--> команда probe: аргументы[2]: обязательный аргумент не ставится после необязательного
```

Отказ разбора — по-русски, со строкой вызова той команды, которую
набрали, и кодом 2:

```sh
$ tarantool console.lua cache:clear --forse
Вызов: console.lua cache:clear [-h] [-f]

Ошибка: ключа «--forse» нет
может быть, «--force»?
$ echo $?
2
```

## Проверки

```sh
make deps          # luatest, luacheck, luacov с cluacov, argparse и зависимости пакета в .rocks
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

Разбирает настоящий рок `argparse`, отказы и справка сверяются дословно
с закреплённым выпуском. Команда отдельным процессом и выход процесса
проверяются ребёнком — сценарием отдельным Tarantool, команда на узле —
на настоящем узле с учёткой, у которой право только на одну функцию.
73 проверки; покрытие строк — 100 %, убитых мутантов — 100 %
(311 мутантов в восьми модулях).

## Документ

Полное описание с обоснованием решений: [docs/console.md](docs/console.md).

## Лицензия

MIT.
