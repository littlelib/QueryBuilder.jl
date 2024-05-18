# QueryBuilder.jl
A SQL query builder package for Julia, focused on building parameterized query, and adding some layer of abstraction on it.

## Why yet another SQL query package

- **Parameterized Query**

There are already great SQL query packages like [Octo.jl](https://github.com/wookay/Octo.jl) and [FunSQL.jl](https://github.com/MechanicalRabbit/FunSQL.jl), but they are not specialized in building parameterized queries. Parameterized queries are quite useful, offering reusable code and preventing SQL injection, but may become cumbersome if you have to build a complex one by yourself. QueryBuilder.jl aims at creating parameterized queries in a more efficient and fault avoiding way.

- **Abstraction**

QueryBuilder.jl provides you a set of tools to create your own abstraction of sql queries, which can later be rendered differently by your choice of DBMS. This helps your code become resuable across DBMSs.

- **Direct query string manipulation**

Unlike the majority of SQL query packages that avoid directly manipulating the query string in favor of abstraction, direct query string manipulation is at the heart of QueryBuilder.jl. Although some might find this unappealing, it does have the advantage of providing explicit and transparent result.

## Installation

QueryBuilder.jl is currently not registered in the official Julia repository. You have to install it via the github url for now.
```julia
# Enter Pkg mode by pressing ']'
pkg> add https://github.com/littlelib/QueryBuilder.jl.git
```

## Examples

```julia
using QueryBuilder
# Automatically assigns necessary query building functions to their predefined names.
@Sql

# Creates a simple, non-parameterized query
julia> Sql("create table Test (id int, value text);")|>render
FinalSqlObject("create table Test (id int, value text);", Any[])

# Creates a parameterized query. DBMS should be specified for correct parameter placeholders.
julia> Sql("insert into Test values ($(P(0)), $(P("first")))")|>sqlite|>render
FinalSqlObject("insert into Test values (?, ?)", Any[0, "first"])

julia> Sql("insert into Test values ($(P(0)), $(P("first")))")|>postgres|>render
FinalSqlObject("insert into Test values (\$1, \$2)", Any[0, "first"])

# Creates an intermediate SqlObject, nests it into another SqlObject, and renders it to a final FinalSqlObject. SqlObject should not be rendered if it will be nested.
where=Sql("where id=$(P(0)) and value=$(P("first"))")
finalSql=Sql("select id, value from Test $(N(where));")
julia> finalSql|>sqlite|>render
FinalSqlObject("select id, value from Test where id=? and value=?;", Any[0, "first"])

julia> finalSql|>postgres|>render
FinalSqlObject("select id, value from Test where id=\$1 and value=\$2;", Any[0, "first"])

# Creates a SqlObject creating function that will be lazily evaluated. This is how an abstract SQL query is defined in QueryBuilder.jl.
function id(::SqlObject{:sqlite}, isprimary::Bool, notnull::Bool, autoincrement::Bool)
    @Sql
    Sql("id int $(isprimary ? "primary key" : "") $(notnull ? "not null" : "") $(autoincrement ? "autoincrement" : "")")
end

function id(::SqlObject{:postgres}, isprimary::Bool, notnull::Bool, autoincrement::Bool)
    @Sql
    if autoincrement
        Sql("id serial $(isprimary ? "primary key" : "") $(notnull ? "not null" : "")")
    else
        Sql("id int $(isprimary ? "primary key" : "") $(notnull ? "not null" : "")")
    end
end

# Now you can use this function across SQLite and Postgresql.
create_table_test2=Sql("create table Test2 ($(A(id, true, true, true)), value text);")

julia> create_table_test2|>sqlite|>render
FinalSqlObject("create table Test2 (id int primary key not null autoincrement, value text);", Any[])
julia> create_table_test2|>postgres|>render
FinalSqlObject("create table Test2 (id serial primary key not null, value text);", Any[])
```

Examples above handle most of the use cases of QueryBuilder.jl. Some advanced topics like caching will be dealt with in their own sections.

## Intrinsics
### Query building closures
There are 5 essential functions that make up this package: Sql, P, L, N, A.
They are closures that share the same captured variable, which holds every parameter received by them. For instance, in `Sql("inserting parameter $(P("Parameter"))")`, the function `P` pushes "Parameter" into the shared captured variable, and returns a placeholder "\xf8", creating an intermediate query "inserting parameter \xf8". The function `Sql` takes the created query and the shared captured variable to create a SqlObject instance.

The closures can be created by calling the function "sqlbuilder".
```julia
(sql, parameter, lazy_parameter, nest_sql, abstract_sql)=sqlbuilder()
```
This way, you can name the closures any way you'd like.


Or, if you have no problem with the predefined closure names, you can just use the @Sql macro
```julia
@Sql
```
and the closures will be automatically instantiated, with their names being Sql, P, L, N, A.

#### Sql

`Sql(query::String)::SqlObject{:abstract}`

Takes the query string, and returns a `SqlObject{:abstract}(query, some_captured_variable).`
All `SqlObject`s are created as a `SqlObject{:abstract}` type when created by `Sql`. It is then changed to other `SqlObject` type by functions like `sqlite`, which will change the type from `SqlObject{:abstract}` to `SqlObject{:sqlite}`.
If the `SqlObject` will be used with other `SqlObject`s, or there's an extra operation to be done, there is no need to specify the DBMS symbol from :abstract. DBMS needs to be specified only just before `render`.

#### P (Parameter)

`P(parameter::Any)::String=PLACEHOLDER_PARAMETER`

Takes the parameter input, pushes it to the shared captured variable, and returns `PLACEHOLDER_PARAMETER` which is "\xf8". In QueryBuilder.jl, among the unused UTF-8 bytes, 0xf8 and 0xf9 are used as placeholders in QueryBuilder.jl. Thus, their usage must be avoided in writing queries, while using them as parameters will work just fine. 

#### L (Lazy parameter)

`L(param::Any, foo::Function)::String=PLACEHOLDER_PARAMETER`
`L(paramNfoo::Tuple{Any, Function})::String=PLACEHOLDER_PARAMETER`

Same as `P`, but takes the lazily evaluated form of a parameter. If the parameter you want to use in the final parameterized query is of form `somefunc(x)`, you can use `L(x, somefunc)` instead of `P(somefunc(x))`.
In usual cases, it will be a completely unnecessay way of expressing a parameter. `render` will detect and evaluate the lazy form, yielding the same FinalSqlObject just like you'd get when using `P`. However, it is of great importance when 'caching' the rendered result of SqlObject and reusing it, as this lazy evaluation is a crucial part of this process. More will be discussed in the "Caching" section below.

#### N (Nest Sql)
`N(sql::SqlObject)::String`
Takes a SqlObject, appends its parameters to the shared captured variable, and returns its query string.
Although quite simple, this nesting of SqlObjects makes creating complex Sql queries much easier.

#### A (Abstract Sql)
`A(foo::Function, args...)::String=PLACEHOLDER_ABSTRACT`

Takes a function `foo` with signature `(sql::SqlObject, args...)::SqlObject`, creates a function with signature `(sql::SqlObject)::SqlObject` that returns `foo(sql, args...)`, pushes it to the shared captured variable, and returns the placeholder.
When writing the `foo` function, make sure that the argument `sql`'s DBMS type is specified, e.g. `sql::SqlObject{:sqlite}`, so that it will return different Sql queries depending on the DBMS via multiple dispatch. Using multiple dispatch makes adding support for different DBMS later on easy, as all you have to do is add a method to `foo` with signature `(sql::SqlObject{DBMS_TO_ADD}, args)::SqlObject`.

### Concatenating SqlObjects
`concat(sql1::SqlObject, sql2::SqlObject, [delim=" "])::SqlObject`
`concat(sqls::Vector, [delim=" "]::SqlObject)`

There are some cases where you would want to concatenate multiple SqlObjects into a single SqlObject. You can use the `concat` function to achieve this.

E.g. if you're trying to insert multiple values into a table
```julia
value_template=(id, val)->Sql("($(P(id)), $(P(val)))")
example_values=map(zip(1:20, string.(20:-1:1))) do x
    value_template(x...)
end
values=concat(example_values, ", ")

julia> Sql("insert into Test values $(N(values));")|>postgres|>render
FinalSqlObject("insert into Test values (\$1, \$2) (\$3, \$4) (\$5, \$6) (\$7, \$8) (\$9, \$10) (\$11, \$12) (\$13, \$14) (\$15, \$16) (\$17, \$18) (\$19, \$20) (\$21, \$22) (\$23, \$24) (\$25, \$26) (\$27, \$28) (\$29, \$30) (\$31, \$32) (\$33, \$34) (\$35, \$36) (\$37, \$38) (\$39, \$40);", Any[1, "20", 2, "19", 3, "18", 4, "17", 5, "16"  …  16, "5", 17, "4", 18, "3", 19, "2", 20, "1"])
```

### Specifying DBMS

You can use the `specifyDBMS(sql::SqlObject, dbms::Symbol)` function to set the DBMS of the `SqlObject`. The DBMS representation must be of type `Symbol`. There are already DBMS representations for SQLite(:sqlite), MySQL/MariaDB(:mysql), PostgreSQL(:postgres), and functions that change a `SqlObject`'s DBMS accordingly (`sqlite`, `mysql`, `postgres`).

### Render

You use the function `render` to evaluate lazy parameters and abstractions, and return the FinalSqlObject which holds the final query string and vector of parameters.

`render(sql::SqlObject)::FinalSqlObject`

This can be used in many SQL packages.
E.g. if you're using SQLite.jl
```julia
db=SQLite.DB()
some_sql=Sql(...something...)|>sqlite|>render
some_statement=SQLite.Stmt(db, some_sql.query)
SQLite.DBInterface.execute(some_statement, some_sql.parameters)
``` 

## Caching (or something like it)

While going through the intrinsics, you may have found out that creating the final `FinalSqlStatement` object is essentially, if not costly, not the cheapest of operations. It will therefore be reasonable to cache the result somehow, and reuse it whenever you possibly can.
It is possible to achieve this without further tricks - just use the query string from the `FinalSqlObject` object, and simply feed the parameters manually. This approach is valid and even preferable in simple queries, but if the hierarchy of parameters gets complex, or there are just too many parameters, the manual approach can become a stuff of a nightmare.
In QueryBuilder.jl, you can use the `cache` function instead of `render`, to return both a rendered `FinalSqlObject` and an anonymous function that creates a `FinalSqlObject` according to the inputs given in the same pattern. The anonymous function skips many operations like query string manipulation or pushing parameters into the shared captured variable. What it does is mostly just assinging argument values to references, and dereferencing them for the final result, which makes it a cheaper alternative.

```julia

function some_complex_sql(id, some_val_container, date)
    @Sql
    where=Sql("id=$(L(id, x->x*x)) or value=$(L(@lazy(some_val_container[1]))) or date=$(P(date)) or isdone=$(L(some_val_container, x->x[2]))")
    Sql("select * from Test where $(N(where));")|>postgres
end

final_sqlobj, final_sql_generator=cache(some_complex_sql, 3, ["val1", true], "May 1st")
julia> final_sqlobj
FinalSqlObject("select * from Test where id=\$1 or value=\$2 or date=\$3 or isdone=\$4;", Any[9, "val1", "May 1st", true])

julia> final_sql_generator(4, ["val2", false], "May 2nd")
FinalSqlObject("select * from Test where id=\$1 or value=\$2 or date=\$3 or isdone=\$4;", Any[16, "val2", "May 2nd", false])
 ```

 Benchmarking the example above shows some substantial speedup.

 ```julia
using BenchmarkTools

function some_complex_sql_uncached(id, some_val_container, date)
    @Sql
    where=Sql("id=$(P(id*id)) or value=$(P(some_val_container[1])) or date=$(P(date)) or isdone=$(P(some_val_container[2]))")
    Sql("select * from Test where $(N(where));")|>postgres|>render
end

julia> @benchmark some_complex_sql_uncached(3, ["val1", true], "May 1st")
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  66.370 μs …  40.805 ms  ┊ GC (min … max): 0.00% … 98.91%
 Time  (median):     69.832 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   75.986 μs ± 407.385 μs  ┊ GC (mean ± σ):  5.31% ±  0.99%

    ▄▆███▇▅▄▄▃▃▃▂▂▂▁▁▁▁        ▁▁                              ▂
  ▆██████████████████████▇███████████▆▆▇▇▇▆▇▇█▇▇▆▇▆▇▆▄▅▅▅▅▅▅▄▄ █
  66.4 μs       Histogram: log(frequency) by time      99.5 μs <

 Memory estimate: 4.35 KiB, allocs estimate: 86.

julia> @benchmark final_sql_generator(3, ["val1", true], "May 1st")
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  25.019 μs … 132.202 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     25.814 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   25.968 μs ±   1.965 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

            ▃▁▅▇█▃▇▆▁▃▁                                         
  ▂▂▂▂▂▃▄▄▆█████████████▅▆▅▄▃▃▃▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▁▂▂▂▂▂▁▁▁▂▂▂▁▂▂▂ ▃
  25 μs           Histogram: frequency by time         28.1 μs <

 Memory estimate: 928 bytes, allocs estimate: 24.
 ```
 ### Constraints to caching
A cachable function must satisfy some constraints, making it a bit verbose. 

First, if the input argument to the function is x, and the value you want to put in as a parameter is of form `foo(x)`, it must be inserted as `L((x, foo))`, and not `P(foo(x))`. This is because the parameter-generating function relies on references to the values of a shared captured variable (might as well call it a pseudo-heap), and eager evalution of foo(x) leaves no choice but to dereference `Ref(x)` and lose the reference, or `foo(Ref(x))` and cause an error. For the same reason, if there's no foo required, it's safe to insert via `P(x)`. The @lazy macro in the example above simplifies some of the process. `@lazy(a.x)` will be expanded to `(a, y->getproperty(y, :x))`, @lazy(a[y]) to `(a, x->x[y])`, and `@lazy(x, x[1]*x[3])` to `(x, x->x[1]*x[3])`.

Second, for the cached sql generating function to work, there should be no change in pattern of the function arguments and parameters: no change in the number of arguments and parameters, nor the types of arguments and parameters. If they do have to change, that means that you need a different set of query string and parameters, making the previous cache useless. In such cases, caching is not an option for you.

Third, the function to be cached should return a `SqlObject` with its DBMS specified, as the `SqlObject` will be rendered during the caching process. If you want to use a more general function returning `SqlObject{:abstract}`, then you can specify its DBMS like:
```julia
function some_complex_sql_abstract(id, some_val_container, date)
    @Sql
    where=Sql("id=$(L(id, x->x*x)) or value=$(L(@lazy(some_val_container[1]))) or date=$(P(date)) or isdone=$(L(some_val_container, x->x[2]))")
    Sql("select * from Test where $(N(where));")
end

final_sqlobj, final_sql_generator=cache(some_complex_sql_abstract|>postgres, 3, ["val1", true], "May 1st")
```
Functions `sqlite`, `mysql`, `postgres`, when given a function as an argument, return a wrapper function so that the resulting `SqlObject` will have its DBMS specified.

## Caveats
- Query building closures will work as intended only when they're executed sequentially. Make sure that functions asynchronous to each other **DO NOT** share the same captured variable. Using the @Sql macro at the beginning of a function would be a safe practice to do, preventing sharing of captured variable across functions in the first place.
- The `@lazy` macro has not been thoroughly tested, and may cause error in some edge cases.


