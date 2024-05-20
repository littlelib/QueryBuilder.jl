function concat(sql1::SqlObject, sql2::SqlObject, delim=" ")
    query=join([sql1.query, sql2.query], delim)
    sqlobjects=vcat(sql1.sqlobjects, sql2.sqlobjects)
    typeof(sql1)(query, sqlobjects)
end

function concat(sqls::Vector, delim=" ")
    function delim_added_concat(sql1, sql2)
        concat(sql1, sql2, delim)
    end
    foldl(delim_added_concat, sqls)
end