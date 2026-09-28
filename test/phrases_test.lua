local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.console.phrases')

local phrases = helper.phrases

g.test_known_sentences = function()
    local cases = {
        { "missing argument 'dir'", 'не хватает аргумента «dir»' },
        { "missing option '--node'", 'не хватает ключа «--node»' },
        { 'too many arguments', 'лишний аргумент' },
        { "unknown command 'it's'", "команды «it's» нет" },
        { "unknown option '--x'", 'ключа «--x» нет' },
        { "option '--t' requires an argument", 'ключу «--t» нужно значение' },
        { "option '--f' does not take arguments", 'ключ «--f» значения не берёт' },
        { "argument for option '--f' must be one of 'a', 'b'", 'ключ «--f» — одно из «a», «b»' },
        { "argument 'level' must be one of 'info'", 'аргумент «level» — одно из «info»' },
    }

    for _, case in ipairs(cases) do
        t.assert_equals(phrases.refusal(case[1]), case[2])
    end
end

g.test_tips = function()
    t.assert_equals(
        phrases.refusal("unknown command 'prob'\nDid you mean 'probe'?"),
        'команды «prob» нет\nможет быть, «probe»?'
    )
    t.assert_equals(
        phrases.refusal("unknown option '-x'\nDid you mean one of these: '-h' '-t'?"),
        'ключа «-x» нет\nможет быть, одно из: «-h», «-t»?'
    )
end

g.test_unknown_sentence_as_is = function()
    t.assert_equals(phrases.refusal('something new'), 'something new')
    t.assert_equals(phrases.refusal("unknown option '-x'\nSomething else"), 'ключа «-x» нет\nSomething else')
    t.assert_equals(phrases.refusal("say: missing argument 'x'"), "say: missing argument 'x'")
    t.assert_equals(phrases.refusal("missing argument 'x' now"), "missing argument 'x' now")
    -- Пустое предложение перед подсказкой — всё равно две строки.
    t.assert_equals(phrases.refusal("\nDid you mean 'x'?"), '\nможет быть, «x»?')
end

g.test_usage = function()
    t.assert_equals(phrases.usage('Usage: app probe\n\nUsage: again'), 'Вызов: app probe\n\nUsage: again')
    t.assert_equals(phrases.usage('app Usage: probe'), 'app Usage: probe')
    t.assert_equals(#phrases.USAGE:gsub('[\128-\191]', ''), #'Usage: ')
end
