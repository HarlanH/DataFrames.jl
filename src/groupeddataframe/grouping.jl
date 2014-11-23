#
#  Split - Apply - Combine operations
#

##############################################################################
##
## GroupedDataFrame...
##
##############################################################################

type GroupedDataFrame
    parent::AbstractDataFrame
    cols::Vector         # columns used for sorting
    idx::Vector{Int}     # indexing vector when sorted by the given columns
    starts::Vector{Int}  # starts of groups
    ends::Vector{Int}    # ends of groups
end

#
# Split
#
function groupby{T}(df::AbstractDataFrame, cols::Vector{T})
    ## a subset of Wes McKinney's algorithm here:
    ##     http://wesmckinney.com/blog/?p=489

    ncols = length(cols)
    # use the pool trick to get a set of integer references for each unique item
    dv = PooledDataArray(df[cols[ncols]])
    # if there are NAs, add 1 to the refs to avoid underflows in x later
    dv_has_nas = (findfirst(dv.refs, 0) > 0 ? 1 : 0)
    x = copy(dv.refs) .+ dv_has_nas
    # also compute the number of groups, which is the product of the set lengths
    ngroups = length(dv.pool) + dv_has_nas
    # if there's more than 1 column, do roughly the same thing repeatedly
    for j = (ncols - 1):-1:1
        dv = PooledDataArray(df[cols[j]])
        dv_has_nas = (findfirst(dv.refs, 0) > 0 ? 1 : 0)
        for i = 1:nrow(df)
            x[i] += (dv.refs[i] + dv_has_nas- 1) * ngroups
        end
        ngroups = ngroups * (length(dv.pool) + dv_has_nas)
        # TODO if ngroups is really big, shrink it
    end
    (idx, starts) = DataArrays.groupsort_indexer(x, ngroups)
    # Remove zero-length groupings
    starts = _uniqueofsorted(starts)
    ends = [starts[2:end] .- 1]
    GroupedDataFrame(df, cols, idx, starts[1:end-1], ends)
end
groupby(d::AbstractDataFrame, cols) = groupby(d, [cols])

# add a function curry
groupby{T}(cols::Vector{T}) = x -> groupby(x, cols)
groupby(cols) = x -> groupby(x, cols)

Base.start(gd::GroupedDataFrame) = 1
Base.next(gd::GroupedDataFrame, state::Int) =
    (sub(gd.parent, gd.idx[gd.starts[state]:gd.ends[state]]),
     state + 1)
Base.done(gd::GroupedDataFrame, state::Int) = state > length(gd.starts)
Base.length(gd::GroupedDataFrame) = length(gd.starts)
Base.endof(gd::GroupedDataFrame) = length(gd.starts)
Base.first(gd::GroupedDataFrame) = gd[1]
Base.last(gd::GroupedDataFrame) = gd[end]

Base.getindex(gd::GroupedDataFrame, idx::Int) = sub(gd.parent, gd.idx[gd.starts[idx]:gd.ends[idx]])
Base.getindex(gd::GroupedDataFrame, I::AbstractArray{Bool}) = GroupedDataFrame(gd.parent,
                                                                          gd.cols,
                                                                          gd.idx,
                                                                          gd.starts[I],
                                                                          gd.ends[I])

function Base.show(io::IO, gd::GroupedDataFrame)
    N = length(gd)
    println(io, "$(typeof(gd))  $N groups with keys: $(gd.cols)")
    println(io, "First Group:")
    show(io, gd[1])
    if N > 1
        print(io, "\n⋮\n")
        println(io, "Last Group:")
        show(io, gd[N])
    end
end

function Base.showall(io::IO, gd::GroupedDataFrame)
    N = length(gd)
    println(io, "$(typeof(gd))  $N groups with keys: $(gd.cols)")
    for i = 1:N
        println(io, "gd[$i]:")
        show(io, gd[i])
    end
end

Base.names(d::GroupedDataFrame) = names(d.parent)

##############################################################################
##
## GroupApplied...
##    the result of a split-apply operation
##    TODOs:
##      - better name?
##      - ref
##      - keys, vals
##      - length
##      - start, next, done -- should this return (k,v) or just v?
##      - make it a real associative type? Is there a need to look up key columns?
##
##############################################################################

type GroupApplied
    keys
    vals
end


#
# Apply / map
#

# map() sweeps along groups
function Base.map(f::Function, gd::GroupedDataFrame)
    ## [d[1,gd.cols] => f(d) for d in gd]
    ## [f(g) for g in gd]
    keys = [d[1,gd.cols] for d in gd]
    vals = Any[f(d) for d in gd]
    GroupApplied(keys,vals)
end

Base.map(f::Function, x::GroupApplied) = GroupApplied(x.keys, map(f, x.vals))

function combine(x)   # expecting (keys,vals) with keys to be DataFrames and values are what are to be combined
    keys = copy(x.keys)
    vals = map(DataFrame, x.vals)
    for i in 1:length(keys)
        keys[i] = vcat(fill(copy(keys[i]), nrow(vals[i]))...)
    end
    hcat(vcat(keys...), vcat(vals...))
end

wrap(df::DataFrame) = df
wrap(A::Matrix) = convert(DataFrame, A)
wrap(s::Any) = DataFrame(x1 = s)

function based_on(gd::GroupedDataFrame, f::Function)
    x = DataFrame[wrap(f(d)) for d in gd]
    idx = rep([1:length(x)], convert(Vector{Int}, map(nrow, x)))
    keydf = DataFrame(gd.parent[gd.idx[gd.starts[idx]], gd.cols])
    resdf = vcat(x)
    hcat(keydf, resdf)
end


# default pipelines:
Base.map(f::Function, x::SubDataFrame) = f(x)

# apply a function to each column in a DataFrame
colwise(f::Function, d::AbstractDataFrame) = Any[[f(d[idx])] for idx in 1:size(d, 2)]
colwise(f::Function, d::GroupedDataFrame) = map(colwise(f), d)
colwise(f::Function) = x -> colwise(f, x)
colwise(f) = x -> colwise(f, x)
# apply several functions to each column in a DataFrame
colwise(fns::Vector{Function}, d::AbstractDataFrame) = Any[[f(d[idx])] for f in fns, idx in 1:size(d, 2)][:]
colwise(fns::Vector{Function}, d::GroupedDataFrame) = map(colwise(fns), d)
colwise(fns::Vector{Function}, d::GroupedDataFrame, cn::Vector{String}) = map(colwise(fns), d)
colwise(fns::Vector{Function}) = x -> colwise(fns, x)

# By convenience functions
by(d::AbstractDataFrame, cols, f::Function) = based_on(groupby(d, cols), f)
by(f::Function, d::AbstractDataFrame, cols) = by(d, cols, f)

# Applies a set of functions over a DataFrame, in the from of a cross-product
function aggregate(d::AbstractDataFrame, fs::Vector{Function}, cn::Vector)
    fnames = _fnames(fs) # see other/utils.jl
    header = [symbol("$(colname)_$(fname)") for fname in fnames, colname in cn][:]
    payload = colwise(fs, d)
    DataFrame(payload, header)
end

aggregate(d::AbstractDataFrame, f::Function, x) = aggregate(d, [f], x)
aggregate(d::AbstractDataFrame, f::Vector{Function}, x::String) = aggregate(d, f, [x])
aggregate(d::AbstractDataFrame, f::Vector{Function}) = aggregate(d, f, names(d))
aggregate(d::AbstractDataFrame, f::Function) = aggregate(d, [f])

# TODO make this faster by applying the header just once.
# BUG zero-rowed groupings cause problems here, because a sum of a zero-length
# DataVector is 0 (not 0.0).
function aggregate(gd::GroupedDataFrame, fs::Vector{Function})
    x = map(x -> aggregate(without(x, gd.cols),fs), gd)
    hcat(vcat(x.keys...), vcat(x.vals...))
end
aggregate(d::GroupedDataFrame, f::Function) = aggregate(d, [f])
aggregate(d::GroupedDataFrame, f::Function, x) = aggregate(d, [f], x)
aggregate(d::GroupedDataFrame, fs::Vector{Function}, x::Union(String, Symbol)) = aggregate(d, fs, [x])
Base.(:|>)(d::GroupedDataFrame, fs::Vector{Function}) = aggregate(d, fs)
Base.(:|>)(d::GroupedDataFrame, f::Function) = aggregate(d, [s])

aggregate{T <: ColumnIndex}(d::AbstractDataFrame, cols :: AbstractVector{T}, fs::Vector{Function}) = aggregate(groupby(d, cols), fs)
aggregate{T <: ColumnIndex}(d::AbstractDataFrame, cols :: AbstractVector{T}, f::Function) = aggregate(d, cols, [f])
aggregate(d::AbstractDataFrame, col :: ColumnIndex, fs::Vector{Function}) = aggregate(d, [col], fs)
aggregate(d::AbstractDataFrame, col :: ColumnIndex, f::Function) = aggregate(d, [col], [f])