local operators = {
    prefix = { -- -1
        ["-"] = 1;
        ["!"] = 1;
        ["~"] = 1;
        ["%"] = 0;
        ["$"] = 0;
    };

    infix = { -- 1 + 2
        ["<"] = 2;
        [">"] = 2;
        ["<="] = 2;
        [">="] = 2;
        ["=="] = 2;

        ["+"] = 3;
        ["-"] = 3;
        ["@"] = 3;
        ["SPC"] = 3;
        ["TAB"] = 3;
        ["NL"] = 3;
        ["*"] = 4;
        ["/"] = 4;
        ["%"] = 4;

        ["="] = 5; -- kinda a hack, w/e
    };

    suffix = { -- 2++
        ["++"] = 1;
        ["--"] = 1;
    };

    declarations = {
        ["+="] = 1;
        ["-="] = 1;
        ["/="] = 1;
        ["*="] = 1;
        ["="] = 1;
    };

    -- multifix are handled by the expression object
    -- since there is only one of them
}

-- Graciously stolen from a gist which I can't remember the link of
-- Just know this aint me :)
function tprint (tbl, indent)
    if not indent then indent = 0 end
    for k, v in pairs(tbl) do
        local formatting = string.rep("    ", indent) .. k .. ": "
        if type(v) == "table" then
            print(formatting)
            tprint(v, indent+1)
        elseif type(v) == 'boolean' then
            print(formatting .. tostring(v))
        else
            print(formatting .. v)
        end
    end
end

function tsname(lex, locality)
    if not locality then
        if not lex:matches("%") and not lex:matches("$") then
            return nil
        end

        locality = lex:next().type == "%"
    end

    local obj = {
        type = "variable";
        locality = locality;
        name = lex:expect(lex.name).value;
    };

    if lex:nextif("::") then
        if obj.locality then
            lex:error("Local variables cannot be scoped")
        end

        repeat
            obj.name = obj.name .. "::" .. lex:expect(lex.name).value
        until not lex:nextif("::")
    elseif lex:nextif(".") then
        repeat
            obj = {
                type = "property";
                obj = obj;
                property = lex:expect(lex.name).value
            }

            if lex:matches("(") then
                obj.type = "method";
                obj.args = terralib.newlist()

                local start = lex:expect("(").linenumber

                repeat
                    obj.args:insert(tsexpression(lex, 0))
                until not lex:nextif(",")

                lex:expectmatch(")", "(", start)
            end
        until (not lex:lookaheadmatches(lex.name)) and (not lex:nextif("."))
    end

    if lex:nextif("[") then
        obj = {
            type = "arrayget";
            index = tsexpression(lex, 0);
            array = obj;
        };

        lex:expect("]")
    end

    return obj
end

function tsexpression(lex, precedence)
    local left = {}
    local current = lex:cur()

    if current.type == "(" then
        lex:next()
        local expr = tsexpression(lex, 0)
        lex:expect(")")
        left.expresson = expr
        left.type = "expression"
    elseif operators.prefix[current.type] ~= nil then
        lex:next()

        if current.type == "%" or current.type == "$" then
            local locality = current.type == "%" or current.type == "$"
            local variable = nil

            if locality then
                variable = tsname(lex, locality)
            else
                variable = tsname(lex)
            end

            left = variable
        else
            left.type = "prefix-exp"
            left.value = tsexpression(lex, operators.prefix[current.type])
            left.op = current.type
        end
    elseif current.type == lex.number then
        lex:next()
        left.type = "number"
        left.value = current.value
    elseif current.type == lex.name then
        if current.value == "new" then
            left = tsobject(lex)
        else
            local start = lex:next().linenumber
            local name = current.value

            if lex:nextif("::") then
                name = name .. "::" .. lex:expect(lex.name).value
            end

            if lex:nextif(".") then
                repeat
                    name = name .. "." .. lex:expect(lex.name).value
                until not lex:nextif(".")
            end

            if lex:nextif("(") then
                left.type = "functioncall"
                left.call = name
                left.args = terralib.newlist()

                repeat
                    local arg = tsexpression(lex, 0)
                    left.args:insert(arg)
                until not lex:nextif(",")

                lex:expectmatch(")", "(", start)
            else
                left.type = "object"
                left.name = current.value
            end
        end
    elseif current.type == lex.string then
        lex:next()

        left.type = "string"
        left.value = current.value
    elseif current.type == "true" or current.type == "false" then
        left = {
            type = "boolean";
            value = current.type == true;
        }

        lex:next()
    end

    local op = lex:cur().type

    if operators.suffix[op] ~= nil then
        return {
            type = "suffix-exp";
            left = left;
            op = op;
        }
    elseif operators.infix[op] ~= nil then
        if operators.infix[op] > precedence then
            lex:next()

            local right = tsexpression(lex, operators.infix[op])

            if right.type == "dumb-infix-exp" then
                return {
                    type = "infix-exp";
                    left = {
                        left = left;
                        op = op;
                        right = right.left;
                    };
                    op = right.op;
                    right = right.right;

                }
            end

            return {
                type = "infix-exp";
                left = left;
                op = op;
                right = right;
            }
        else
            lex:next()

            local right = tsexpression(lex, operators.infix[op])

            return {
                type = "dumb-infix-exp";
                left = left;
                op = op;
                right = right;
            }
        end
    elseif op == "?" then
        local iftrue = tsexpression(lex, 0)

        lex:expect(":")

        local iffalse = tsexpression(lex, 0)

        return {
            type = "multifix-exp";
            cond = left;
            yes = iftrue;
            no = iffalse;
        }
    end

    return left
end

function tsobject(lex)
    if lex:cur().value ~= "new" then
        return nil
    end

    lex:next()

    local obj = {
        type = "new-stmt";
        class = lex:expect(lex.name).value;
    }

    lex:expect("(")

    obj.name = lex:expect(lex.name).value

    if lex:nextif(":") then
        obj.inherit = lex:expect(lex.name).value
    end

    lex:expect(")")
    obj.args = terralib.newlist()

    local start = lex:expect("{").linenumber

    if lex:nextif("}") then -- empty object
        lex:expect(";")
        return obj
    end

    repeat
        local keyval = {}
        keyval.key = lex:expect(lex.name).value

        if lex:nextif("[") then
            keyval.array = tsexpression(lex, 0)
            lex:expect("]")
        end

        lex:expect("=")

        keyval.value = tsexpression(lex, 0)
        lex:expect(";")
        obj.args:insert(keyval)

    until lex:nextif("}")
    print("WEW")
    return obj
end

function tsblock(lex)
    local block = terralib.newlist()
    local blockstart = lex:expect("{").linenumber
    local obj = nil

    repeat
        obj = nil

        if lex:matches("%") or lex:matches("$") then
            local variable = tsname(lex)

            if variable.type == "method" then
                lex:expect(";")
                block:insert(variable)
                obj = 1
            else
                obj = {
                    type = "variable-dec";
                    variable = variable;
                }

                obj.op = lex:next().type

                if operators.declarations[obj.op] == nil then
                    lex:error(tostring(obj.op) .. " is not a valid declaror")
                end

                obj.value = tsexpression(lex, 0)

                lex:expect(";")
            end
        elseif lex:matches(lex.name) then
            if lex:cur().value == "new" then
                block:insert(tsobject(lex))
                lex:expect(";")
            elseif lex:lookahead().type == "(" then
                obj = {
                    type = "function-call";
                    name = lex:next().value;
                    args = terralib.newlist();
                }

                local start = lex:expect("(").linenumber

                repeat
                    local arg = tsexpression(lex, 0)
                    obj.args:insert(arg)
                until not lex:nextif(",")

                lex:expectmatch(")", "(", start)
                lex:expect(";")
            elseif lex:cur().value == "break" or lex:cur().value == "continue" then
                obj = {
                    type = lex:cur().value .. "-stmt";
                };
            end
        elseif lex:nextif("if") then
            local start = lex:expect("(").linenumber

            obj = {
                type = "if-stmt";
                ifstmt = tsexpression(lex, 0);
                block = nil;
            }

            lex:expectmatch(")", "(", start)
            obj.block = tsblock(lex)
        elseif lex:nextif("for") then
            local start = lex:expect("(").linenumber
            local init = tsexpression(lex, 0)
            lex:expect(";")
            local each = tsexpression(lex, 0)
            lex:expect(";")
            local atend = tsexpression(lex, 0)
            lex:expectmatch(")", "(", start)

            obj = {
                type = "for-stmt";
                init = init;
                each = each;
                atend = atend;
                block = tsblock(lex);
            }
        elseif lex:nextif("while") then
            local start = lex:expect("(").linenumber

            obj = {
                type = "while-stmt";
                ifstmt = tsexpression(lex, 0);
                block = nil;
            }
            lex:expectmatch(")", "(", start)
            obj.block = tsblock(lex)
        else
            if lex:cur().value ~= nil then
                lex:error("Unexpected " .. lex:cur().value)
            end
        end

        block:insert(obj)
    until not obj

    lex:expectmatch("}", "{", blockstart)
    return block
end

function tsdatablock(lex)
    if not lex:nextif("tsdatablock") then
        return nil
    end

    local datablock = {
        type = "datablock";
        dbtype = lex:expect(lex.name).value;
    };

    lex:expect("(")
    datablock.name = lex:expect(lex.name).value

    if lex:nextif(":") then
        datablock.inherit = lex:expect(lex.name).value
    end

    lex:expect(")")
    datablock.args = terralib.newlist()

    local start = lex:expect("{").linenumber

    if lex:nextif("}") then -- empty datablock
        lex:expect(";")
        return datablock
    end

    repeat
        local obj = {}
        obj.key = lex:expect(lex.name).value;

        if lex:nextif("[") then
            obj.array = tsexpression(lex, 0)
            lex:expect("]")
        end

        lex:expect("=")

        obj.value = tsexpression(lex, 0)
        lex:expect(";")
        datablock.args:insert(obj)

    until lex:nextif("}")

    lex:expect(";")
    return datablock
end

function tsfunction(lex)
    if not lex:nextif("tsfunction") then
        return nil
    end

    local fnc = {
        name = lex:expect(lex.name).value;
        arguments = terralib.newlist();
        type = "function";
    };

    if lex:nextif("::") then
        fnc.namespace = fnc.name
        fnc.name = lex:expect(lex.name).value
    end

    local begin = lex:expect("(").linenumber

    if not lex:matches(")") then
        repeat
            lex:expect("%")
            local t = lex:expect(lex.name)
            fnc.arguments:insert(t.value)
            lex:ref(t.value)
        until not lex:nextif(",")
    end

    lex:expectmatch(")", "(", begin)

    fnc.block = tsblock(lex);
    tprint(fnc, 0)
    return fnc
end

function tspackage(lex)
    if not lex:nextif("tspackage") then
        return nil
    end

    local pkg = {
        name = lex:expect(lex.name).value;
        block = terralib.newlist();
        type = "package";
    };

    local start = lex:expect("{").linenumber
    local next = nil

    repeat
        next = tsfunction(lex)
        if next then pkg.block:append(next) end
    until not next

    lex:expectmatch("}", "{", start)
    return pkg
end

local torquescript = {
    name = "torquescript";
    entrypoints = {"tsfunction", "tspackage", "tsdatablock"};
    keywords = {"if", "else", "for", "while", "package", "SPC", "TAB", "NL"};

    statement = function (self, lex)
        local newfunctions = terralib.newlist()
        local newpackages = terralib.newlist()
        local newdatablocks = terralib.newlist()

        if lex:matches("tsfunction") then
            newfunctions:insert(tsfunction(lex))
        elseif lex:matches("tspackage") then
            newpackages:insert(tspackage(lex))
        elseif lex:matches("tsdatablock") then
            newdatablocks:insert(tsdatablock(lex))
        end

        return function(environment_function)
            return 0
        end
    end
}

return torquescript
