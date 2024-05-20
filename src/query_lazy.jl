function lazyrender!(sqlobj::SqlObject)
    sqlobjects=sqlobj.sqlobjects

    lazysqls=filter(sqlobj.sqlobjects) do x
        isa(x, LazySqlPart)
    end

    for lazysql in lazysqls
        result=lazysql.query(sqlobj)
        sqlobj.query=replace(sqlobj.query, PLACEHOLDER_ABSTRACT=>result.query, count=1)
        sqlobjects=replace(sqlobjects, lazysql=>result.sqlobjects, count=1)
    end

    sqlobjects=isempty(sqlobjects) ? sqlobjects : reduce(vcat, sqlobjects)|>vcat
    render_placeholder!(sqlobj)
    sqlobj
end

function cache(fun::Function, args...)
    heap::Vector{Any}=args|>collect
    refs=map(1:length(heap)) do x
        Ref(heap, x)
    end
    result=fun(refs...)
    result=result|>lazyrender!
    parameters=result.sqlobjects|>Tuple
    function final_sql_generator(args2...)
        for (i,v) in args2|>enumerate
            heap[i]=v
        end
        final_params=map(parameters) do x
            if isa(x, Parameter)
                x.value[]
            else
                x.fun(x.value[])
            end
        end
        FinalSqlObject(result.query, final_params|>collect)
    end
    return (final_sql_generator(args...), final_sql_generator)
end

#=
function cache_2(fun::Function, args...)
    heap=map(args) do arg
        Ref(arg)
    end
    
    result=fun(heap...)
    result=result|>lazyrender!
    parameters=result.sqlobjects|>Tuple
    function final_sql_generator(args2...)
        for (i,v) in args2|>enumerate
            heap[i][]=v
        end
        final_params=map(parameters) do x
            if isa(x, Parameter)
                x.value[]
            else
                x.fun(x.value[])
            end
        end
        FinalSqlObject(result.query, final_params|>collect)
    end
    return (final_sql_generator(args...), final_sql_generator)
end
=#