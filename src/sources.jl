using DBI

"""
`AbstractDataSource` provides an interfaces for wrappers that help
map inserting raw data from real data sources into `DataView`s.

[Required Methods]
* fetch!(src::AbstractDataSource) fetches data an inserts into into the
   DataViews, returning those DataViews.
"""
abstract AbstractDataSource
fetch!(src::AbstractDataSource) = error("Not Implemented")

"""
`SQLConnectionInfo{T<:DBI.DatabaseSystem}` stores the common
connection information needed by DBI to create the DB connection.
"""
immutable SQLConnectionInfo{T<:DBI.DatabaseSystem}
    driver::Type{T}
    addr::AbstractString
    username::AbstractString
    password::AbstractString
    dbname::AbstractString
    port::Int64
end


"""
`SQLDataSource{T<:AbstractDatum}` is a subtype of AbstractDataSource which implements
the DataSource interface for DBI compatible raw sources. Takes the db connection
info, the query info, a datum type to convert to and a list of view to dump into.

NOTE: currently isn't mutable cause of the fetched bool.
"""
type SQLDataSource{T<:AbstractDatum} <: AbstractDataSource
    dbinfo::SQLConnectionInfo                       # Stores common db info required for making a connection to the db
    query::AbstractString                           # the sql query to run
    views::Tuple{Vararg{AbstractDataView}}          # A list of caches to use.
    params::Tuple                                   # Parameters to pass to the query
    datum_type::Type{T}                             # A type to convert each row to, which allows us to dispatch on inserting into a cache
    fetched::Bool

    function SQLDataSource(dbinfo, query, views, params, datum_type)
        new(
            dbinfo,
            query,
            views,
            (),
            DefaultDatum,
            false
        )
    end

end

"""
`SQLDataSource{T<:AbstractDatum}` the SQLDataSource constructor.
"""
function SQLDataSource{T<:AbstractDatum}(
        dbinfo::SQLConnectionInfo,
        query::AbstractString,
        views::Tuple{Vararg{AbstractDataView}};
        parameters=(),
        datum_type::Type{T}=DefaultDatum
    )
    SQLDataSource{T}(
        dbinfo,
        query,
        views,
        parameters,
        datum_type
    )
end

"""
`fetch!(src::SQLDataSource)` handles the grabbing of data from the datasource
and inserting it into the dataviews. Currently, this is a synchronous
operation, but support for an async fetch maybe provided in the future.
"""
function fetch!(src::SQLDataSource)
    if !src.fetched
        dbinfo = src.dbinfo

        # This entire process of fetching data should probably happen in a separate thread, however,
        # we would need to make restrictions on the order in which data is inserted into the dataview.
        connect(dbinfo.driver, dbinfo.addr, dbinfo.username, dbinfo.password, dbinfo.dbname, dbinfo.port) do conn
            stmt = prepare(conn, src.query)
            results = execute(stmt, [src.params...])

            for r in results
                datum = src.datum_type((r...))

                # At the very least we parallelize the insertion of the datum into each view.
                for i in 1:length(src.views)
                    insert!(src.views[i], datum)
                end
            end
        end
        src.fetched = true
    end
    return src.views
end
