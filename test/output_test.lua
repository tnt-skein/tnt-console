local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.console.output')

g.test_line_and_error = function()
    local out, written = helper.output_capture()

    out:line('готово')
    out:error('внимание')
    out:line()

    t.assert_equals(written, { stdout = { 'готово\n', '\n' }, stderr = { 'внимание\n' } })
end

g.test_pattern_only_with_arguments = function()
    local out, written = helper.output_capture()

    out:line('файлов: %d, испорченных: %s', 3, nil)
    out:line('100%')
    out:error('%s из %d', 'один', 2)
    out:error('50% готово')

    t.assert_equals(written, {
        stdout = { 'файлов: 3, испорченных: nil\n', '100%\n' },
        stderr = { 'один из 2\n', '50% готово\n' },
    })
end

g.test_line_arguments_are_checked = function()
    local out = helper.output_capture()

    t.assert_equals(
        helper.blamed(function()
            out:line(helper.wrong(42))
        end),
        'строка — строка, а не число'
    )
    t.assert_equals(
        helper.blamed(function()
            out:error(nil, 'значение')
        end),
        'образец строки — строка, а не nil'
    )
end

g.test_table_aligned_by_characters = function()
    local out, written = helper.output_capture()

    out:table({ 'файл', 'записей', 'целый' }, {
        { '00000000000000000000.xlog', 12, true },
        { 'ё', '', false },
        { 'журнал' },
    })

    t.assert_equals(written.stdout, {
        'файл                       записей  целый\n',
        '-------------------------  -------  -----\n',
        '00000000000000000000.xlog  12       true\n',
        'ё                                   false\n',
        'журнал\n',
    })
end

g.test_table_without_headers = function()
    local out, written = helper.output_capture()

    out:table(nil, { { 'а', 'бб' }, { 'ввв', 'г' } })

    t.assert_equals(written.stdout, { 'а    бб\n', 'ввв  г\n' })
end

g.test_table_rows_end_on_hole = function()
    local out, written = helper.output_capture()

    out:table({ 'имя' }, { { 'a', nil, 'c' }, {} })

    t.assert_equals(written.stdout, { 'имя\n', '---\n', 'a\n', '\n' })
end

g.test_table_not_utf8_by_bytes = function()
    local out, written = helper.output_capture()

    out:table(nil, { { '\xff\xfe', 'x' }, { 'abc', 'y' } })

    t.assert_equals(written.stdout, { '\xff\xfe   x\n', 'abc  y\n' })
end

g.test_table_arguments_are_checked = function()
    local out = helper.output_capture()

    t.assert_equals(
        helper.blamed(function()
            out:table({ 'a', 1 }, {})
        end),
        'шапка[2] — строка, а не число'
    )
    t.assert_equals(
        helper.blamed(function()
            out:table(nil, { 'a' })
        end),
        'строки[1] — таблица, а не строка'
    )
end

g.test_describe = function()
    local out, written = helper.output_capture()

    out:describe({ id = 7, password = 'hunter2', tags = { 'a' } })
    out:describe({ a = { 1, 2 } }, { inline = true })

    t.assert_equals(written.stdout, {
        '{\n    id = 7,\n    password = [скрыто],\n    tags = {\n        "a"\n    }\n}\n',
        '{ a = { 1, 2 } }\n',
    })
end

g.test_describe_options_are_checked = function()
    local out = helper.output_capture()

    t.assert_equals(
        helper.blamed(function()
            out:describe({}, { inlne = true })
        end),
        'настройки показа: ключа «inlne» нет, есть depth, inline, items, length'
    )
end
