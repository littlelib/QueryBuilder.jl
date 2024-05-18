macro Sql()
    esc(:((Sql, P, L, N, A)=QueryBuilder.sqlbuilder()))
end

macro lazy(expr)
    if expr.head==:.
        :($(esc(expr.args[1])), x->getproperty(x, $(expr.args[2])))
    elseif expr.head==:ref
        :($(esc(expr.args[1])), x->x[$(expr.args[2:end]...)])
    elseif expr.head==:tuple && length(expr.args)==2
        :($(esc(expr.args[1])), $(expr.args[1])->$(expr.args[2]))
    else
        return_exp=string(expr)
        :(error("Unsupported expression pattern: $($return_exp)"))
    end
end

macro lazy(exp1, exp2)
    :($(esc(exp1)), $(esc(exp1))->$(esc(exp2)))
end