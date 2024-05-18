function concat(sql1::SqlObject, sql2::SqlObject, delim=" ")
    query=join([sql1.query, sql2.query], delim)
    sqlobjects=vcat(sql1.sqlobjects, sql2.sqlobjects)
    typeof(sql1)(query, sqlobjects)
end

function concat(sqls::Vector, delim=" ")
    foldl(concat, sqls)
end