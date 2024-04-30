-- t: table
-- level: 最大显示table层级。不输入时处理为math.huge，即展开所有层级
function tablestr(t, level)
    -- 非table类型直接返回
    if type(t) ~= 'table' then
        return tostring(t)
    end

    -- 检查level类型
    if level == nil then
        level = math.huge
    elseif type(level) ~= "number" then
        print(debug.traceback('TableString: level must be a number'))
        os.exit()
    elseif level < 0 then
        print(debug.traceback('TableString: level must be a positive number'))
        os.exit()
    end

    if level == 0 then
        return '{...}'
    end

    -- 剩下table类型
    local str = '{'

    -- 迭代table中的内容
    local keys = 0
    local indices = 0
    for k, v in pairs(t) do
        if type(k) == 'number' then
            -- 键值为index
            if type(v) == 'table' then
                str = str .. tablestr(v, level - 1)
            elseif type(v) == 'function' then
                str = str .. '(function)'
            else
                str = str .. tostring(v)
            end
            indices = indices + 1
        else
            -- 键值为key
            if type(v) == 'table' then
                str = str .. k .. '=' .. tablestr(v, level - 1)
            elseif type(v) == 'function' then
                str = str .. k .. '=' .. 'function()'
            else
                str = str .. k .. '=' .. tostring(v)
            end
            keys = keys + 1
        end

        str = str .. ', '
    end

    if indices + keys > 0 then
        str = string.sub(str, 1, -3)
    end

    str = str .. '}'

    return str
end

-- 示例代码
-- local collection = {'a',{1,2},{'hi', {'Anna', 'Bell', name='AnnaBell'}},{{'x','y','z'},{1,2,3}}}
-- local collection = {a='1',b='2', 'x', 'y', 'z', f=function() print('hi') end}
-- local collection = {1,2,3}
-- print(TableString('a'))
-- print(TableString(2))
-- print(TableString({}))

-- print(TableString(collection))