abstract type AbstractSqlObject end;

const PLACEHOLDER_PARAMETER=String([0xf8])
const PLACEHOLDER_ABSTRACT=String([0xf9])

@kwdef mutable struct SqlObject{T} <: AbstractSqlObject
    query::String=""
    sqlobjects::Vector{AbstractSqlObject}=[]
end

@kwdef mutable struct LazySqlPart <: AbstractSqlObject
    query::Function
end

mutable struct Parameter <: AbstractSqlObject
    value
end

struct FinalSqlObject <: AbstractSqlObject
    query::String
    parameters::Vector
end

mutable struct LazyParameter <: AbstractSqlObject
    value
    fun::Function
end

gettype(x)=gettype(typeof(x))
gettype(::Type{SqlObject{T}}) where T=T

function sqlbuilder()
    sqlobjects::Vector{AbstractSqlObject}=[]
    
    # Sql
    function buildsql(query::AbstractString)
        return_query=SqlObject{:abstract}(query, sqlobjects)
        sqlobjects=[]
        return return_query
    end

    # P for Parameter
    function insert_parameter(param)
        push!(sqlobjects, Parameter(param))
        return PLACEHOLDER_PARAMETER
    end

    # L for Lazy parameter
    function insert_lazyparameter(param, fun::Function)
        push!(sqlobjects, LazyParameter(param, fun))
        return PLACEHOLDER_PARAMETER
    end

    # L for Lazy parameter
    function insert_lazyparameter(paramNfun::Tuple{Any, Function})
        param, fun = paramNfun
        insert_lazyparameter(param, fun)
    end

    # N for Nest
    function nestsql(sqlobj::SqlObject)
        append!(sqlobjects, sqlobj.sqlobjects)
        return sqlobj.query
    end

    # A for Abstract 
    function lazy_nestsql(lazyfunc::Function, args...)
        lazy_query=function (sqlobj::SqlObject)
            lazyfunc(sqlobj, args...)
        end
        push!(sqlobjects, LazySqlPart(lazy_query))
        return PLACEHOLDER_ABSTRACT
    end

    return (Sql=buildsql, P=insert_parameter, L=insert_lazyparameter, N=nestsql, A=lazy_nestsql)
end

function specifyDBMS(sqlobj::SqlObject, dbms::Symbol)
    SqlObject{dbms}(sqlobj.query, sqlobj.sqlobjects)
end

function specifyDBMS(sqlobj_generator::Function, specify_dbms::Function)
    return function(args...)
        sqlobj_generator(args...)|>specify_dbms
    end
end

function sqlite(sqlobj::SqlObject)
    specifyDBMS(sqlobj, :sqlite)
end

function sqlite(sqlobj_generator::Function)
    specifyDBMS(sqlobj_generator, sqlite)
end    

function mysql(sqlobj::SqlObject)
    specifyDBMS(sqlobj, :mysql)
end

function mysql(sqlobj_generator::Function)
    specifyDBMS(sqlobj_generator, mysql)
end  

function postgres(sqlobj::SqlObject)
    specifyDBMS(sqlobj, :postgres)
end

function postgres(sqlobj_generator::Function)
    specifyDBMS(sqlobj_generator, postgres)
end  

function render(sqlobj::SqlObject)
    sqlobj=sqlobj|>deepcopy
    sqlobjects=sqlobj.sqlobjects
    lazysqls=filter(sqlobj.sqlobjects) do x
        isa(x, LazySqlPart)
    end
    
    for lazysql in lazysqls
        result=lazysql.query(sqlobj)
        sqlobj.query=replace(sqlobj.query, PLACEHOLDER_ABSTRACT=>result.query, count=1)
        sqlobjects=replace(sqlobjects, lazysql=>result.sqlobjects, count=1)
    end
    lazyparameters=filter(sqlobj.sqlobjects) do x
        isa(x, LazyParameter)
    end
    for lazyparameter in lazyparameters
        result=Parameter(lazyparameter.fun(lazyparameter.value))
        sqlobjects=replace(sqlobjects, lazyparameter=>result, count=1)
    end

    sqlobjects=isempty(sqlobjects) ? sqlobjects : reduce(vcat, sqlobjects)|>vcat
    render_placeholder!(sqlobj)
    FinalSqlObject(sqlobj.query, map(x->x.value, sqlobjects))
end

function render_placeholder!(sqlobj::SqlObject{:postgres})
    counter=0
    while contains(sqlobj.query, PLACEHOLDER_PARAMETER)
        counter+=1
        sqlobj.query=replace(sqlobj.query, PLACEHOLDER_PARAMETER=>"\$$counter", count=1)
    end
    sqlobj
end

function render_placeholder!(sqlobj::SqlObject{:sqlite})
    sqlobj.query=replace(sqlobj.query, PLACEHOLDER_PARAMETER=>"?")
    sqlobj
end

function render_placeholder!(sqlobj::SqlObject)
    sqlobj.query=replace(sqlobj.query, PLACEHOLDER_PARAMETER=>"?")
    sqlobj
end