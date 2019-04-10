using Tables, TableTraits, IteratorInterfaceExtensions

Tables.istable(::Type{<:AbstractDataFrame}) = true
Tables.columnaccess(::Type{<:AbstractDataFrame}) = true
Tables.columns(df::AbstractDataFrame) = df
Tables.rowaccess(::Type{<:AbstractDataFrame}) = true
Tables.rows(df::AbstractDataFrame) = Tables.rows(columntable(df))

Tables.schema(df::AbstractDataFrame) = Tables.Schema(names(df), eltypes(df))
Tables.materializer(df::AbstractDataFrame) = DataFrame

getvector(x::AbstractVector) = x
getvector(x) = collect(x)
fromcolumns(x; copycols::Bool=true) =
    DataFrame(AbstractVector[getvector(c) for c in Tables.eachcolumn(x)],
              Index(collect(Symbol, propertynames(x))),
              copycols=copycols)

function DataFrame(x; copycols::Bool=true)
    if x isa AbstractVector && all(col -> isa(col, AbstractVector), x)
        return DataFrame(Vector{AbstractVector}(x), copycols=copycols)
    end
    if applicable(iterate, x)
        if all(v -> v isa Pair{Symbol, <:AbstractVector}, x)
            return DataFrame(AbstractVector[last(v) for v in x], [first(v) for v in x],
                             copycols=copycols)
        end
    end
    if Tables.istable(x)
        return fromcolumns(Tables.columns(x), copycols=copycols)
    end
    throw(ArgumentError("unable to construct DataFrame from $(typeof(x))"))
end

"""
    DataFrame!(table)

Create a `DataFrame` from a `table` with `copycols=false`.
`table` can be any type that implements the
[Tables.jl](https://github.com/JuliaData/Tables.jl) interface

### Examples

```jldoctest
julia> df1 = DataFrame(a=1:3)
3×1 DataFrame
│ Row │ a     │
│     │ Int64 │
├─────┼───────┤
│ 1   │ 1     │
│ 2   │ 2     │
│ 3   │ 3     │

julia> df2 = DataFrame!(df1)

julia> df1.a === df2.a
true
"""
DataFrame!(table) = DataFrame(table, copycols=false)

Base.append!(df::DataFrame, x) = append!(df, DataFrame(x, copycols=false))

# This supports the Tables.RowTable type; needed to avoid ambiguities w/ another constructor
DataFrame(x::Vector{<:NamedTuple}) =
    fromcolumns(Tables.columns(Tables.IteratorWrapper(x)), copycols=false)

IteratorInterfaceExtensions.getiterator(df::AbstractDataFrame) = Tables.datavaluerows(df)
IteratorInterfaceExtensions.isiterable(x::AbstractDataFrame) = true
TableTraits.isiterabletable(x::AbstractDataFrame) = true
