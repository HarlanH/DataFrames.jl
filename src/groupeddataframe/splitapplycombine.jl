#
# groupby(), map(), combine(), by(), aggregate() and related
#

"""
    groupby(d::AbstractDataFrame, cols; sort=false, skipmissing=false)

Return a `GroupedDataFrame` representing a view of an `AbstractDataFrame` split into row groups.

# Arguments
- `df` : an `AbstractDataFrame` to split
- `cols` : data frame columns to group by
- `sort` : whether to sort rows according to the values of the grouping columns `cols`
- `skipmissing` : whether to skip rows with `missing` values in one of the grouping columns `cols`

# Details
An iterator over a `GroupedDataFrame` returns a `SubDataFrame` view
for each grouping into `df`.
Within each group, the order of rows in `df` is preserved.

`cols` can be any valid data frame indexing expression.
In particular if it is an empty vector then a single-group `GroupedDataFrame`
is created.

A `GroupedDataFrame` also supports
indexing by groups, `map` (which applies a function to each group)
and `combine` (which applies a function to each group
and combines the result into a data frame).

See the following for additional split-apply-combine operations:

* [`by`](@ref) : split-apply-combine using functions
* [`aggregate`](@ref) : split-apply-combine; applies functions in the form of a cross product
* [`map`](@ref) : apply a function to each group of a `GroupedDataFrame` (without combining)
* [`combine`](@ref) : combine a `GroupedDataFrame`, optionally applying a function to each group

`GroupedDataFrame` also supports the dictionary interface. The keys are
[`GroupKey`](@ref) objects returned by [`keys(::GroupedDataFrame)`](@ref),
which can also be used to get the values of the grouping columns for each group.
`Tuples` and `NamedTuple`s containing the values of the grouping columns (in the
same order as the `cols` argument) are also accepted as indices, but this will
be slower than using the equivalent `GroupKey`.

# Examples
```julia
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> gd = groupby(df, :a)
GroupedDataFrame with 4 groups based on key: a
First Group (2 rows): a = 1
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 2     │ 1     │
│ 2   │ 1     │ 2     │ 5     │
⋮
Last Group (2 rows): a = 4
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 4     │ 1     │ 4     │
│ 2   │ 4     │ 1     │ 8     │

julia> gd[1]
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 2     │ 1     │
│ 2   │ 1     │ 2     │ 5     │

julia> last(gd)
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 4     │ 1     │ 4     │
│ 2   │ 4     │ 1     │ 8     │

julia> gd[(a=3,)]
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 3     │ 2     │ 3     │
│ 2   │ 3     │ 2     │ 7     │

julia> gd[(3,)]
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 3     │ 2     │ 3     │
│ 2   │ 3     │ 2     │ 7     │

julia> k = first(keys(gd))
GroupKey: (a = 3)

julia> gd[k]
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 3     │ 2     │ 3     │
│ 2   │ 3     │ 2     │ 7     │

julia> for g in gd
           println(g)
       end
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 2     │ 1     │
│ 2   │ 1     │ 2     │ 5     │
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 2     │ 1     │ 2     │
│ 2   │ 2     │ 1     │ 6     │
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 3     │ 2     │ 3     │
│ 2   │ 3     │ 2     │ 7     │
2×3 SubDataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 4     │ 1     │ 4     │
│ 2   │ 4     │ 1     │ 8     │
```
"""
function groupby(df::AbstractDataFrame, cols;
                 sort::Bool=false, skipmissing::Bool=false)
    _check_consistency(df)
    idxcols = index(df)[cols]
    intcols = idxcols isa Int ? [idxcols] : convert(Vector{Int}, idxcols)
    if isempty(intcols)
        return GroupedDataFrame(df, intcols, ones(Int, nrow(df)),
                                collect(axes(df, 1)), [1], [nrow(df)], 1, nothing)
    end
    sdf = df[!, intcols]

    groups = Vector{Int}(undef, nrow(df))
    ngroups, rhashes, gslots, sorted =
        row_group_slots(ntuple(i -> sdf[!, i], ncol(sdf)), Val(false), groups, skipmissing)

    gd = GroupedDataFrame(df, intcols, groups, nothing, nothing, nothing, ngroups, nothing)

    # sort groups if row_group_slots hasn't already done that
    if sort && !sorted
        # Find index of representative row for each group
        idx = Vector{Int}(undef, length(gd))
        fillfirst!(nothing, idx, 1:nrow(parent(gd)), gd)
        group_invperm = invperm(sortperm(view(parent(gd)[!, gd.cols], idx, :)))
        groups = gd.groups
        @inbounds for i in eachindex(groups)
            gix = groups[i]
            groups[i] = gix == 0 ? 0 : group_invperm[gix]
        end
    end

    return gd
end

const F_TYPE_RULES =
    """
    `fun` can return a single value, a row, a vector, or multiple rows.
    The type of the returned value determines the shape of the resulting `DataFrame`.
    There are four kind of return values allowed:
    - A single value gives a `DataFrame` with a single additional column and one row
      per group.
    - A named tuple of single values or a [`DataFrameRow`](@ref) gives a `DataFrame`
      with one additional column for each field and one row per group (returning a
      named tuple will be faster). It is not allowed to mix single values and vectors
      if a named tuple is returned.
    - A vector gives a `DataFrame` with a single additional column and as many rows
      for each group as the length of the returned vector for that group.
    - A data frame, a named tuple of vectors or a matrix gives a `DataFrame` with
      the same additional columns and as many rows for each group as the rows
      returned for that group (returning a named tuple is the fastest option).
      Returning a table with zero columns is allowed, whatever the number of columns
      returned for other groups.

    `fun` must always return the same kind of object (out of four
    kinds defined above) for all groups, and with the same column names.

    Optimized methods are used when standard summary functions (`sum`, `prod`,
    `minimum`, `maximum`, `mean`, `var`, `std`, `first`, `last` and `length`)
    are specified using the `Pair` syntax (e.g. `:col => sum`).
    When computing the `sum` or `mean` over floating point columns, results will be
    less accurate than the standard [`sum`](@ref) function (which uses pairwise
    summation). Use `col => x -> sum(x)` to avoid the optimized method and use the
    slower, more accurate one.

    Column names are automatically generated when necessary using the rules defined
    in [`select`](@ref) if the `Pair` syntax is used and `fun` returns a single
    value or a vector (e.g. for `:col => sum` the column name is `col_sum`); otherwise
    (if `fun` is a function or a return value is an `AbstractMatrix`) columns are
    named `x1`, `x2` and so on.
    """

"""
    map(fun::Union{Function, Type}, gd::GroupedDataFrame)
    map(pair::Pair, gd::GroupedDataFrame)

Apply `fun` or `pair` to each group of rows and return a [`GroupedDataFrame`](@ref).

If `fun` is specified it must be a function, and it is passed a [`SubDataFrame`](@ref)
view for each group and can return any return value defined below.
Note that this form is slower than `pair` due to type instability.

If `pair` is passed then it must follow the rules specified for transformations in
[`select`](@ref) and have the form `source_cols => fun` or `source_cols => fun => target_col`.
Function defined by `fun` is passed `SubArray` views as positional arguments for
each column specified to be selected and can return any return value defined below.
As a special case `nrow` or `nrow => target_col` can be passed without specifying
input columns to efficiently calculate number of rows in each group.
If `nrow` is passed the resulting column name is `:nrow`.


$F_TYPE_RULES

See also [`combine`](@ref) that returns a `DataFrame` rather than a `GroupedDataFrame`.

# Examples
```jldoctest
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> gd = groupby(df, :a);

julia> map(sdf -> sum(sdf.c), gd)
GroupedDataFrame{DataFrame} with 4 groups based on key: :a
First Group: 1 row
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
⋮
Last Group: 1 row
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 4     │ 12    │

julia> map(:c => sum, gd)
GroupedDataFrame with 4 groups based on key: a
First Group (1 row): a = 1
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
⋮
Last Group (1 row): a = 4
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 4     │ 12    │

julia> map(nrow, gd)
GroupedDataFrame with 4 groups based on key: a
First Group (1 row): a = 1
│ Row │ a     │ nrow  │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 2     │
⋮
Last Group (1 row): a = 4
│ Row │ a     │ nrow  │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 4     │ 2     │
```

See [`by`](@ref) for more examples.
"""
function Base.map(f::Union{Base.Callable, Pair}, gd::GroupedDataFrame)
    if length(gd) > 0
        # here we know that parent(gd) has at least 1 column
        if f isa Pair || f === nrow
            if f isa Pair && first(f) isa Tuple
                Base.depwarn("passing a Tuple $(first(f)) as column selector is deprecated" *
                             ", use a vector $(collect(first(f))) instead", :combine)
                source_cols, (fun, out_col) = normalize_selection(index(parent(gd)),
                                                                  collect(first(f)) => last(f))
            else
                source_cols, (fun, out_col) = normalize_selection(index(parent(gd)), f)
            end
            if isagg(source_cols => fun)
                idx, valscat = _combine([source_cols => fun], gd, [out_col])
            else
                idx, valscat = _combine(source_cols => last(f), gd, nothing)
            end
        else
            idx, valscat = _combine(f, gd, nothing)
        end
        keys = _names(parent(gd))[gd.cols]
        for key in keys
            if hasproperty(valscat, key) &&
               !isequal(valscat[!, key], view(parent(gd)[!, key], idx))
               throw(ArgumentError("column :$key in returned data frame " *
                                   "is not equal to grouping key :$key"))
            end
        end
        newparent = hcat!(parent(gd)[idx, gd.cols],
                          without(valscat, intersect(keys, _names(valscat))))
        if length(idx) == 0
            return GroupedDataFrame(newparent, collect(1:length(gd.cols)), idx,
                                    Int[], Int[], Int[], 0, Dict{Any,Int}())
        end
        starts = Vector{Int}(undef, length(gd))
        ends = Vector{Int}(undef, length(gd))
        starts[1] = 1
        j = 1
        @inbounds for i in 2:length(idx)
            if idx[i] != idx[i-1]
                j += 1
                starts[j] = i
                ends[j-1] = i - 1
            end
        end
        # In case some groups have to be dropped
        resize!(starts, j)
        resize!(ends, j)
        ends[end] = length(idx)
        return GroupedDataFrame(newparent, collect(1:length(gd.cols)), idx,
                                collect(1:length(idx)), starts, ends, j, nothing)
    else
        return GroupedDataFrame(parent(gd)[1:0, gd.cols], collect(1:length(gd.cols)),
                                Int[], Int[], Int[], Int[], 0, Dict{Any,Int}())
    end
end

const F_ARGUMENT_RULES =
    """
    If `pairs` arguments are passed they must consist of more than one `Pair`s,
    or vectors of such `Pair`s. Allowed transformations follow the rules specified
    for [`select`](@ref) and have the form `source_cols => fun` or
    `source_cols => fun => target_col`. Function `fun` is passed `SubArray` views
    as positional arguments for each column specified to be selected and can return
    an abstract vector or a single value (defined precisely below).
    As a special case `nrow` or `nrow => target_col` can be passed without specifying
    input columns to efficiently calculate number of rows in each group.
    If `nrow` is passed the resulting column name is `:nrow`.

    If the first or last argument is `pair` then it must be a `Pair` following the
    rules for pairs described above, except that in this case function defined
    by `fun` can return any return value defined below.

    If the first or last argument is a function `fun`, it is passed a [`SubDataFrame`](@ref)
    view for each group and can return any return value defined below.
    Note that this form is slower than `pair` or `pairs` due to type instability.
    """

const KWARG_PROCESSING_RULES =
    """
    If `keepkeys=true`, the resulting `DataFrame` contains all the grouping columns
    in addition to those generated. In this case if the returned
    value contains columns with the same names as the grouping columns, they are
    required to be equal.
    """

"""
    combine(gd::GroupedDataFrame, pairs...; keepkeys::Bool=true)
    combine(fun::Union{Function, Type}, gd::GroupedDataFrame; keepkeys::Bool=true)
    combine(pair::Pair, gd::GroupedDataFrame; keepkeys::Bool=true)
    combine(gd::GroupedDataFrame, fun::Union{Function, Type}; keepkeys::Bool=true)
    combine(gd::GroupedDataFrame, pair::Pair; keepkeys::Bool=true)

Transform a [`GroupedDataFrame`](@ref) into a `DataFrame`.

$F_ARGUMENT_RULES

$F_TYPE_RULES

$KWARG_PROCESSING_RULES

The resulting data frame will be sorted if `sort=true` was passed to the
[`groupby`](@ref) call from which `gd` was constructed. Otherwise, ordering of rows
is undefined.

See also:
- [`by(f, df, cols)`](@ref) is a shorthand for `combine(f, groupby(df, cols))`.
- [`map`](@ref): `combine(f, groupby(df, cols))` is a more efficient equivalent
of `combine(map(f, groupby(df, cols)))`.

# Examples
```jldoctest
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> gd = groupby(df, :a);

julia> combine(gd, :c => sum, nrow)
4×3 DataFrame
│ Row │ a     │ c_sum │ nrow  │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 6     │ 2     │
│ 2   │ 2     │ 8     │ 2     │
│ 3   │ 3     │ 10    │ 2     │
│ 4   │ 4     │ 12    │ 2     │

julia> combine(sdf -> sum(sdf.c), gd) # Slower variant
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> by(df, :a) do d # do syntax for the slower variant
           sum(d.c)
       end
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> combine(gd, :c => (x -> sum(log, x)) => :sum_log_c) # specifying a name for target column
4×2 DataFrame
│ Row │ a     │ sum_log_c │
│     │ Int64 │ Float64   │
├─────┼───────┼───────────┤
│ 1   │ 1     │ 1.60944   │
│ 2   │ 2     │ 2.48491   │
│ 3   │ 3     │ 3.04452   │
│ 4   │ 4     │ 3.46574   │


julia> combine(gd, [:b, :c] .=> sum) # passing a vector of pairs
4×3 DataFrame
│ Row │ a     │ b_sum │ c_sum │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 4     │ 6     │
│ 2   │ 2     │ 2     │ 8     │
│ 3   │ 3     │ 4     │ 10    │
│ 4   │ 4     │ 2     │ 12    │

julia> combine(gd) do sdf # dropping group when DataFrame() is returned
          sdf.c[1] != 1 ? sdf : DataFrame()
       end
6×3 DataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 2     │ 1     │ 2     │
│ 2   │ 2     │ 1     │ 6     │
│ 3   │ 3     │ 2     │ 3     │
│ 4   │ 3     │ 2     │ 7     │
│ 5   │ 4     │ 1     │ 4     │
│ 6   │ 4     │ 1     │ 8     │

julia> combine(gd, :b => identity => :b, :c => identity => :c,
               [:b, :c] => +, keepkeys=false) # auto-splatting and keepkeys
8×3 DataFrame
│ Row │ b     │ c     │ b_c_+ │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 2     │ 1     │ 3     │
│ 2   │ 2     │ 5     │ 7     │
│ 3   │ 1     │ 2     │ 3     │
│ 4   │ 1     │ 6     │ 7     │
│ 5   │ 2     │ 3     │ 5     │
│ 6   │ 2     │ 7     │ 9     │
│ 7   │ 1     │ 4     │ 5     │
│ 8   │ 1     │ 8     │ 9     │
```

See [`by`](@ref) for more examples.
"""
combine(f::Union{Base.Callable, Pair}, gd::GroupedDataFrame; keepkeys::Bool=true) =
    combine(gd, f, keepkeys=keepkeys)
combine(gd::GroupedDataFrame, f::Base.Callable; keepkeys::Bool=true) =
    combine_helper(f, gd, keepkeys=keepkeys)
combine(gd::GroupedDataFrame, f::typeof(nrow); keepkeys::Bool=true) =
    combine(gd, [nrow => :nrow], keepkeys=keepkeys)

function combine(gd::GroupedDataFrame, f::Pair; keepkeys::Bool=true)
    # move handling of aggregate to specialized combine
    f_from, f_to = f

    # verify if it is not better to use a fast path
    if isagg(f_from => (f_to isa Pair ? first(f_to) : f_to)) || f_from === nrow
        return combine(gd, [f], keepkeys=keepkeys)
    end

    if f_from isa Tuple
        cs = collect(f_from)
        Base.depwarn("passing a Tuple $f_from as column selector is deprecated" *
                     ", use a vector $cs instead", :combine)
    else
        cs = f_from
    end
    return combine_helper(cs => f_to, gd, keepkeys=keepkeys)
end

function combine(gd::GroupedDataFrame,
                 @nospecialize(cs::Union{Pair, AbstractVector{<:Pair}, typeof(nrow)}...);
                 keepkeys::Bool=true)
    @assert !isempty(cs)
    cs_vec = Pair[]
    for p in cs
        if p isa Pair
            push!(cs_vec, p)
        elseif p === nrow
            push!(cs_vec, nrow => :nrow)
        else
            @assert p isa AbstractVector{<:Pair}
            append!(cs_vec, p)
        end
    end
    if any(x -> first(x) isa Tuple, cs_vec)
        x = cs_vec[findfirst(x -> first(x) isa Tuple, cs_vec)]
        Base.depwarn("passing a Tuple $(first(x)) as column selector is deprecated" *
                     ", use a vector $(collect(first(x))) instead", :combine)
        for (i, v) in enumerate(cs_vec)
            if first(v) isa Tuple
                cs_vec[i] = collect(first(v)) => last(v)
            end
        end
    end
    cs_norm = Pair[normalize_selection(index(parent(gd)), c) for c in cs_vec]
    f = Pair[first(x) => first(last(x)) for x in cs_norm]
    nms = Symbol[last(last(x)) for x in cs_norm]
    return combine_helper(f, gd, nms, keepkeys=keepkeys)
end

function combine(gd::GroupedDataFrame; f...)
    if length(f) == 0
        throw(ArgumentError("combine(gd) is not allowed, use DataFrame(gd) " *
                            "to combine a GroupedDataFrame into a DataFrame"))
    end
    Base.depwarn("`combine(gd; target_col = source_cols => fun, ...)` is deprecated" *
                 ", use `combine(gd, source_cols => fun => :target_col, ...)` instead",
                 :combine)
    return combine(gd, [source_cols => fun => out_col for (out_col, (source_cols, fun)) in f])
end

function combine_helper(f, gd::GroupedDataFrame,
                        nms::Union{AbstractVector{Symbol},Nothing}=nothing;
                        keepkeys::Bool=true)
    if length(gd) > 0
        idx, valscat = _combine(f, gd, nms)
        keepkeys || return valscat
        keys = groupvars(gd)
        for key in keys
            if hasproperty(valscat, key) &&
               !isequal(valscat[!, key], view(parent(gd)[!, key], idx))
               throw(ArgumentError("column :$key in returned data frame " *
                                   "is not equal to grouping key :$key"))
            end
        end
        return hcat!(parent(gd)[idx, gd.cols],
                     without(valscat, intersect(keys, _names(valscat))))
    else
        return keepkeys ? parent(gd)[1:0, gd.cols] : DataFrame()
    end
end

# Wrapping automatically adds column names when the value returned
# by the user-provided function lacks them
wrap(x::Union{AbstractDataFrame, NamedTuple, DataFrameRow}) = x
wrap(x::AbstractMatrix) =
    NamedTuple{Tuple(gennames(size(x, 2)))}(Tuple(view(x, :, i) for i in 1:size(x, 2)))
wrap(x::Any) = (x1=x,)

wrap_table(x::Any, ::Val) =
    throw(ArgumentError("return value must not change its kind " *
                        "(single row or variable number of rows) across groups"))
function wrap_table(x::Union{NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}},
                             AbstractDataFrame, AbstractMatrix},
                             ::Val{firstmulticol}) where firstmulticol
    if !firstmulticol
        throw(ArgumentError("function must return only single-column values, " *
                            "or only multiple-column values"))
    end
    wrap(x)
end

function wrap_table(x::AbstractVector, ::Val{firstmulticol}) where firstmulticol
    if firstmulticol
        throw(ArgumentError("function must return only single-column values, " *
                            "or only multiple-column values"))
    end
    wrap(x)
end

function wrap_row(x::Any, ::Val{firstmulticol}) where firstmulticol
    # NamedTuple is not possible in this branch
    if (x isa DataFrameRow) ⊻ firstmulticol
        throw(ArgumentError("function must return only single-column values, " *
                            "or only multiple-column values"))
    end
    wrap(x)
end

# note that also NamedTuple() is correctly captured by this definition
# as it is more specific than the one below
wrap_row(::Union{AbstractVecOrMat, AbstractDataFrame,
                 NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}}, ::Val) =
    throw(ArgumentError("return value must not change its kind " *
                        "(single row or variable number of rows) across groups"))

function wrap_row(x::NamedTuple, ::Val{firstmulticol}) where firstmulticol
    if any(v -> v isa AbstractVector, x)
        throw(ArgumentError("mixing single values and vectors in a named tuple is not allowed"))
    end
    if !firstmulticol
        throw(ArgumentError("function must return only single-column values, " *
                            "or only multiple-column values"))
    end
    return x
end

# idx, starts and ends are passed separately to avoid cost of field access in tight loop
function do_call(f::Any, idx::AbstractVector{<:Integer},
                 starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
                 gd::GroupedDataFrame, incols::Tuple{}, i::Integer)
    f()
end

function do_call(f::Any, idx::AbstractVector{<:Integer},
                 starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
                 gd::GroupedDataFrame, incols::Tuple{AbstractVector}, i::Integer)
    idx = idx[starts[i]:ends[i]]
    f(view(incols[1], idx))
end

function do_call(f::Any, idx::AbstractVector{<:Integer},
                 starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
                 gd::GroupedDataFrame, incols::NTuple{2, AbstractVector}, i::Integer)
    idx = idx[starts[i]:ends[i]]
    f(view(incols[1], idx), view(incols[2], idx))
end

function do_call(f::Any, idx::AbstractVector{<:Integer},
                 starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
                 gd::GroupedDataFrame, incols::NTuple{3, AbstractVector}, i::Integer)
    idx = idx[starts[i]:ends[i]]
    f(view(incols[1], idx), view(incols[2], idx), view(incols[3], idx))
end

function do_call(f::Any, idx::AbstractVector{<:Integer},
                 starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
                 gd::GroupedDataFrame, incols::NTuple{4, AbstractVector}, i::Integer)
    idx = idx[starts[i]:ends[i]]
    f(view(incols[1], idx), view(incols[2], idx), view(incols[3], idx),
           view(incols[4], idx))
end

function do_call(f::Any, idx::AbstractVector{<:Integer},
                 starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
                 gd::GroupedDataFrame, incols::Tuple, i::Integer)
    idx = idx[starts[i]:ends[i]]
    f(map(c -> view(c, idx), incols)...)
end

do_call(f::Any, idx::AbstractVector{<:Integer},
        starts::AbstractVector{<:Integer}, ends::AbstractVector{<:Integer},
        gd::GroupedDataFrame, incols::Nothing, i::Integer) = f(gd[i])

_nrow(df::AbstractDataFrame) = nrow(df)
_nrow(x::NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}) =
    isempty(x) ? 0 : length(x[1])
_ncol(df::AbstractDataFrame) = ncol(df)
_ncol(x::Union{NamedTuple, DataFrameRow}) = length(x)

abstract type AbstractAggregate end

struct Reduce{O, C, A} <: AbstractAggregate
    op::O
    condf::C
    adjust::A
    checkempty::Bool
end
Reduce(f, condf=nothing, adjust=nothing) = Reduce(f, condf, adjust, false)

check_aggregate(f::Any) = f
check_aggregate(::typeof(sum)) = Reduce(Base.add_sum)
check_aggregate(::typeof(prod)) = Reduce(Base.mul_prod)
check_aggregate(::typeof(maximum)) = Reduce(max)
check_aggregate(::typeof(minimum)) = Reduce(min)
check_aggregate(::typeof(mean)) = Reduce(Base.add_sum, nothing, /)
check_aggregate(::typeof(sum∘skipmissing)) = Reduce(Base.add_sum, !ismissing)
check_aggregate(::typeof(prod∘skipmissing)) = Reduce(Base.mul_prod, !ismissing)
check_aggregate(::typeof(mean∘skipmissing)) = Reduce(Base.add_sum, !ismissing, /)
check_aggregate(::typeof(maximum∘skipmissing)) = Reduce(max, !ismissing, nothing, true)
check_aggregate(::typeof(minimum∘skipmissing)) = Reduce(min, !ismissing, nothing, true)

# Other aggregate functions which are not strictly reductions
struct Aggregate{F, C} <: AbstractAggregate
    f::F
    condf::C
end
Aggregate(f) = Aggregate(f, nothing)

check_aggregate(::typeof(var)) = Aggregate(var)
check_aggregate(::typeof(var∘skipmissing)) = Aggregate(var, !ismissing)
check_aggregate(::typeof(std)) = Aggregate(std)
check_aggregate(::typeof(std∘skipmissing)) = Aggregate(std, !ismissing)
check_aggregate(::typeof(first)) = Aggregate(first)
check_aggregate(::typeof(first∘skipmissing)) = Aggregate(first, !ismissing)
check_aggregate(::typeof(last)) = Aggregate(last)
check_aggregate(::typeof(last∘skipmissing)) = Aggregate(last, !ismissing)
check_aggregate(::typeof(length)) = Aggregate(length)
# SkipMissing does not support length

# Find first value matching condition for each group
# Optimized for situations where a matching value is typically encountered
# among the first rows for each group
function fillfirst!(condf, outcol::AbstractVector, incol::AbstractVector,
                    gd::GroupedDataFrame; rev::Bool=false)
    ngroups = gd.ngroups
    # Use group indices if they have already been computed
    idx = getfield(gd, :idx)
    if idx !== nothing && condf === nothing
        v = rev ? gd.ends : gd.starts
        @inbounds for i in 1:ngroups
            outcol[i] = incol[idx[v[i]]]
        end
    elseif idx !== nothing
        nfilled = 0
        starts = gd.starts
        @inbounds for i in eachindex(outcol)
            s = starts[i]
            offsets = rev ? (nrow(gd[i])-1:-1:0) : (0:nrow(gd[i])-1)
            for j in offsets
                x = incol[idx[s+j]]
                if !condf === nothing || condf(x)
                    outcol[i] = x
                    nfilled += 1
                    break
                end
            end
        end
        if nfilled < length(outcol)
            throw(ArgumentError("some groups contain only missing values"))
        end
    else # Finding first row is faster than computing all group indices
        groups = gd.groups
        if rev
            r = length(groups):-1:1
        else
            r = 1:length(groups)
        end
        filled = fill(false, ngroups)
        nfilled = 0
        @inbounds for i in r
            gix = groups[i]
            x = incol[i]
            if gix > 0 && (condf === nothing || condf(x)) && !filled[gix]
                filled[gix] = true
                outcol[gix] = x
                nfilled += 1
                nfilled == ngroups && break
            end
        end
        if nfilled < length(outcol)
            throw(ArgumentError("some groups contain only missing values"))
        end
    end
    outcol
end

# Use reducedim_init to get a vector of the right type,
# but trick it into using the expected length
groupreduce_init(op, condf, incol, gd) =
    Base.reducedim_init(identity, op, view(incol, 1:length(gd)), 2)
for (op, initf) in ((:max, :typemin), (:min, :typemax))
    @eval begin
        function groupreduce_init(::typeof($op), condf, incol::AbstractVector{T}, gd) where T
            # !ismissing check is purely an optimization to avoid a copy later
            outcol = similar(incol, condf === !ismissing ? nonmissingtype(T) : T, length(gd))
            # Comparison is possible only between CatValues from the same pool
            if incol isa CategoricalVector
                U = Union{CategoricalArrays.leveltype(outcol),
                          eltype(outcol) >: Missing ? Missing : Union{}}
                outcol = CategoricalArray{U, 1}(outcol.refs, incol.pool)
            end
            # It is safe to use a non-missing init value
            # since missing will poison the result if present
            S = nonmissingtype(T)
            if isconcretetype(S) && hasmethod($initf, Tuple{S})
                fill!(outcol, $initf(S))
            else
                fillfirst!(condf, outcol, incol, gd)
            end
            return outcol
        end
    end
end

function copyto_widen!(res::AbstractVector{T}, x::AbstractVector) where T
    @inbounds for i in eachindex(res, x)
        val = x[i]
        S = typeof(val)
        if S <: T || promote_type(S, T) <: T
            res[i] = val
        else
            newres = Tables.allocatecolumn(promote_type(S, T), length(x))
            return copyto_widen!(newres, x)
        end
    end
    return res
end

function groupreduce!(res, f, op, condf, adjust, checkempty::Bool,
                      incol::AbstractVector{T}, gd::GroupedDataFrame) where T
    n = length(gd)
    if adjust !== nothing || checkempty
        counts = zeros(Int, n)
    end
    groups = gd.groups
    @inbounds for i in eachindex(incol, groups)
        gix = groups[i]
        x = incol[i]
        if gix > 0 && (condf === nothing || condf(x))
            res[gix] = op(res[gix], f(x, gix))
            if adjust !== nothing || checkempty
                counts[gix] += 1
            end
        end
    end
    outcol = adjust === nothing ? res : map(adjust, res, counts)
    if checkempty && any(iszero, counts)
        throw(ArgumentError("some groups contain only missing values"))
    end
    # Undo pool sharing done by groupreduce_init
    if outcol isa CategoricalVector && outcol.pool === incol.pool
        U = Union{CategoricalArrays.leveltype(outcol),
                  eltype(outcol) >: Missing ? Missing : Union{}}
        outcol = CategoricalArray{U, 1}(outcol.refs, copy(outcol.pool))
    end
    if isconcretetype(eltype(outcol))
        return outcol
    else
        copyto_widen!(Tables.allocatecolumn(typeof(first(outcol)), n), outcol)
    end
end

# function barrier works around type instability of _groupreduce_init due to applicable
groupreduce(f, op, condf, adjust, checkempty::Bool,
            incol::AbstractVector, gd::GroupedDataFrame) =
    groupreduce!(groupreduce_init(op, condf, incol, gd),
                 f, op, condf, adjust, checkempty, incol, gd)
# Avoids the overhead due to Missing when computing reduction
groupreduce(f, op, condf::typeof(!ismissing), adjust, checkempty::Bool,
            incol::AbstractVector, gd::GroupedDataFrame) =
    groupreduce!(disallowmissing(groupreduce_init(op, condf, incol, gd)),
                 f, op, condf, adjust, checkempty, incol, gd)

(r::Reduce)(incol::AbstractVector, gd::GroupedDataFrame) =
    groupreduce((x, i) -> x, r.op, r.condf, r.adjust, r.checkempty, incol, gd)

function (agg::Aggregate{typeof(var)})(incol::AbstractVector, gd::GroupedDataFrame)
    means = groupreduce((x, i) -> x, Base.add_sum, agg.condf, /, false, incol, gd)
    # !ismissing check is purely an optimization to avoid a copy later
    if eltype(means) >: Missing && agg.condf !== !ismissing
        T = Union{Missing, real(eltype(means))}
    else
        T = real(eltype(means))
    end
    res = zeros(T, length(gd))
    groupreduce!(res, (x, i) -> @inbounds(abs2(x - means[i])), +, agg.condf,
                 (x, l) -> l <= 1 ? oftype(x / (l-1), NaN) : x / (l-1),
                 false, incol, gd)
end

function (agg::Aggregate{typeof(std)})(incol::AbstractVector, gd::GroupedDataFrame)
    outcol = Aggregate(var, agg.condf)(incol, gd)
    map!(sqrt, outcol, outcol)
end

for f in (first, last)
    function (agg::Aggregate{typeof(f)})(incol::AbstractVector, gd::GroupedDataFrame)
        n = length(gd)
        outcol = similar(incol, n)
        fillfirst!(agg.condf, outcol, incol, gd, rev=agg.f === last)
        if isconcretetype(eltype(outcol))
            return outcol
        else
            return copyto_widen!(Tables.allocatecolumn(typeof(first(outcol)), n), outcol)
        end
    end
end

function (agg::Aggregate{typeof(length)})(incol::AbstractVector, gd::GroupedDataFrame)
    if getfield(gd, :idx) === nothing
        lens = zeros(Int, length(gd))
        @inbounds for gix in gd.groups
            gix > 0 && (lens[gix] += 1)
        end
        return lens
    else
        return gd.ends .- gd.starts .+ 1
    end
end

isagg(p::Pair) = check_aggregate(last(p)) isa AbstractAggregate && first(p) isa ColumnIndex

const MULTI_COLS_TYPE = Union{AbstractDataFrame, NamedTuple, DataFrameRow, AbstractMatrix}

function _combine(f::AbstractVector{<:Pair}, gd::GroupedDataFrame, nms::AbstractVector{Symbol})
    # here f should be normalized and in a form of source_cols => fun
    if any(isagg, f)
        # Compute indices of representative rows only once for all AbstractAggregates
        idx_agg = Vector{Int}(undef, length(gd))
        fillfirst!(nothing, idx_agg, 1:length(gd.groups), gd)
    elseif !all(isagg, f)
        # Trigger computation of indices
        # This can speed up some aggregates that would not trigger this on their own
        @assert gd.idx !== nothing
    end
    res = Vector{Any}(undef, length(f))
    parentdf = parent(gd)
    for (i, p) in enumerate(f)
        source_cols, fun = p
        if isagg(p)
            incol = parentdf[!, source_cols]
            agg = check_aggregate(last(p))
            outcol = agg(incol, gd)
            res[i] = idx_agg, outcol
        else
            if source_cols isa Int
                incols = (parentdf[!, source_cols],)
            else
                @assert source_cols isa AbstractVector{Int}
                incols = ntuple(i -> parentdf[!, source_cols[i]], length(source_cols))
            end
            firstres = do_call(fun, gd.idx, gd.starts, gd.ends, gd, incols, 1)
            firstmulticol = firstres isa MULTI_COLS_TYPE
            if firstmulticol
                throw(ArgumentError("a single value or vector result is required when passing " *
                                    "multiple functions (got $(typeof(res)))"))
            end
            idx, outcols, _ = _combine_with_first(wrap(firstres), fun, gd, incols,
                                                  Val(firstmulticol))
            res[i] = idx, outcols[1]
        end
    end
    # TODO: avoid recomputing idx for each pair when !all(isagg, f)
    idx = res[1][1]
    outcols = map(x -> x[2], res)
    if !all(x -> length(x) == length(outcols[1]), outcols)
        throw(ArgumentError("all functions must return values of the same length"))
    end
    return idx, DataFrame(collect(AbstractVector, outcols), nms)
end

function _combine(fun::Base.Callable, gd::GroupedDataFrame, ::Nothing)
    firstres = fun(gd[1])
    firstmulticol = firstres isa MULTI_COLS_TYPE
    idx, outcols, nms = _combine_with_first(wrap(firstres), fun, gd, nothing,
                                            Val(firstmulticol))
    valscat = DataFrame(collect(AbstractVector, outcols), nms)
    return idx, valscat
end

function _combine(p::Pair, gd::GroupedDataFrame, ::Nothing)
    # here p should not be normalized as we allow tabular return value from fun
    # map and combine should not dispatch here if p is isagg
    source_cols, (fun, out_col) = normalize_selection(index(parent(gd)), p)
    parentdf = parent(gd)
    if source_cols isa Int
        incols = (parent(gd)[!, source_cols],)
    else
        @assert source_cols isa AbstractVector{Int}
        incols = ntuple(i -> parent(gd)[!, source_cols[i]], length(source_cols))
    end
    firstres = do_call(fun, gd.idx, gd.starts, gd.ends, gd, incols, 1)
    firstmulticol = firstres isa MULTI_COLS_TYPE
    idx, outcols, nms = _combine_with_first(wrap(firstres), fun, gd, incols,
                                            Val(firstmulticol))
    # disallow passing target column name to genuine tables
    if firstres isa MULTI_COLS_TYPE
        if p isa Pair{<:Any, <:Pair{<:Any, Symbol}}
            throw(ArgumentError("setting column name for tabular return value is disallowed"))
        end
    else
        # fetch auto generated or passed target column name to nms overwritting
        # what _combine_with_first produced
        nms = [out_col]
    end
    valscat = DataFrame(collect(AbstractVector, outcols), nms)
    return idx, valscat
end

function _combine_with_first(first::Union{NamedTuple, DataFrameRow, AbstractDataFrame},
                             f::Any, gd::GroupedDataFrame,
                             incols::Union{Nothing, AbstractVector, Tuple},
                             firstmulticol::Val)
    if first isa AbstractDataFrame
        n = 0
        eltys = eltype.(eachcol(first))
    elseif first isa NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}
        n = 0
        eltys = map(eltype, first)
    elseif first isa DataFrameRow
        n = length(gd)
        eltys = [eltype(parent(first)[!, i]) for i in parentcols(index(first))]
    else # NamedTuple giving a single row
        n = length(gd)
        eltys = map(typeof, first)
        if any(x -> x <: AbstractVector, eltys)
            throw(ArgumentError("mixing single values and vectors in a named tuple is not allowed"))
        end
    end
    idx = Vector{Int}(undef, n)
    local initialcols
    let eltys=eltys, n=n # Workaround for julia#15276
        initialcols = ntuple(i -> Tables.allocatecolumn(eltys[i], n), _ncol(first))
    end
    targetcolnames = tuple(propertynames(first)...)
    if first isa Union{AbstractDataFrame,
                       NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}}
        outcols, finalcolnames = _combine_tables_with_first!(first, initialcols, idx, 1, 1,
                                                             f, gd, incols, targetcolnames,
                                                             firstmulticol)
    else
        outcols, finalcolnames = _combine_rows_with_first!(first, initialcols, idx, 1, 1,
                                                           f, gd, incols, targetcolnames,
                                                           firstmulticol)
    end
    idx, outcols, collect(Symbol, finalcolnames)
end

function fill_row!(row, outcols::NTuple{N, AbstractVector},
                   i::Integer, colstart::Integer,
                   colnames::NTuple{N, Symbol}) where N
    if _ncol(row) != N
        throw(ArgumentError("return value must have the same number of columns " *
                            "for all groups (got $N and $(length(row)))"))
    end
    @inbounds for j in colstart:length(outcols)
        col = outcols[j]
        cn = colnames[j]
        local val
        try
            val = row[cn]
        catch
            throw(ArgumentError("return value must have the same column names " *
                                "for all groups (got $colnames and $(propertynames(row)))"))
        end
        S = typeof(val)
        T = eltype(col)
        if S <: T || promote_type(S, T) <: T
            col[i] = val
        else
            return j
        end
    end
    return nothing
end

function _combine_rows_with_first!(first::Union{NamedTuple, DataFrameRow},
                                   outcols::NTuple{N, AbstractVector},
                                   idx::Vector{Int}, rowstart::Integer, colstart::Integer,
                                   f::Any, gd::GroupedDataFrame,
                                   incols::Union{Nothing, AbstractVector, Tuple},
                                   colnames::NTuple{N, Symbol},
                                   firstmulticol::Val) where N
    len = length(gd)
    gdidx = gd.idx
    starts = gd.starts
    ends = gd.ends
    # Handle first group
    j = fill_row!(first, outcols, rowstart, colstart, colnames)
    @assert j === nothing # eltype is guaranteed to match
    idx[rowstart] = gdidx[starts[rowstart]]
    # Handle remaining groups
    @inbounds for i in rowstart+1:len
        row = wrap_row(do_call(f, gdidx, starts, ends, gd, incols, i), firstmulticol)
        j = fill_row!(row, outcols, i, 1, colnames)
        if j !== nothing # Need to widen column type
            local newcols
            let i = i, j = j, outcols=outcols, row=row # Workaround for julia#15276
                newcols = ntuple(length(outcols)) do k
                    S = typeof(row[k])
                    T = eltype(outcols[k])
                    U = promote_type(S, T)
                    if S <: T || U <: T
                        outcols[k]
                    else
                        copyto!(Tables.allocatecolumn(U, length(outcols[k])),
                                1, outcols[k], 1, k >= j ? i-1 : i)
                    end
                end
            end
            return _combine_rows_with_first!(row, newcols, idx, i, j,
                                             f, gd, incols, colnames, firstmulticol)
        end
        idx[i] = gdidx[starts[i]]
    end
    return outcols, colnames
end

# This needs to be in a separate function
# to work around a crash due to JuliaLang/julia#29430
if VERSION >= v"1.1.0-DEV.723"
    @inline function do_append!(do_it, col, vals)
        do_it && append!(col, vals)
        return do_it
    end
else
    @noinline function do_append!(do_it, col, vals)
        do_it && append!(col, vals)
        return do_it
    end
end

function append_rows!(rows, outcols::NTuple{N, AbstractVector},
                      colstart::Integer, colnames::NTuple{N, Symbol}) where N
    if !isa(rows, Union{AbstractDataFrame, NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}})
        throw(ArgumentError("return value must not change its kind " *
                            "(single row or variable number of rows) across groups"))
    elseif _ncol(rows) != N
        throw(ArgumentError("return value must have the same number of columns " *
                            "for all groups (got $N and $(_ncol(rows)))"))
    end
    @inbounds for j in colstart:length(outcols)
        col = outcols[j]
        cn = colnames[j]
        local vals
        try
            vals = getproperty(rows, cn)
        catch
            throw(ArgumentError("return value must have the same column names " *
                                "for all groups (got $colnames and $(propertynames(rows)))"))
        end
        S = eltype(vals)
        T = eltype(col)
        if !do_append!(S <: T || promote_type(S, T) <: T, col, vals)
            return j
        end
    end
    return nothing
end

function _combine_tables_with_first!(first::Union{AbstractDataFrame,
                                     NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}},
                                     outcols::NTuple{N, AbstractVector},
                                     idx::Vector{Int}, rowstart::Integer, colstart::Integer,
                                     f::Any, gd::GroupedDataFrame,
                                     incols::Union{Nothing, AbstractVector, Tuple},
                                     colnames::NTuple{N, Symbol},
                                     firstmulticol::Val) where N
    len = length(gd)
    gdidx = gd.idx
    starts = gd.starts
    ends = gd.ends
    # Handle first group

    @assert _ncol(first) == N
    if !isempty(colnames)
        j = append_rows!(first, outcols, colstart, colnames)
        @assert j === nothing # eltype is guaranteed to match
        append!(idx, Iterators.repeated(gdidx[starts[rowstart]], _nrow(first)))
    end
    # Handle remaining groups
    @inbounds for i in rowstart+1:len
        rows = wrap_table(do_call(f, gdidx, starts, ends, gd, incols, i), firstmulticol)
        _ncol(rows) == 0 && continue
        if isempty(colnames)
            newcolnames = tuple(propertynames(rows)...)
            if rows isa AbstractDataFrame
                eltys = eltype.(eachcol(rows))
            else
                eltys = map(eltype, rows)
            end
            initialcols = ntuple(i -> Tables.allocatecolumn(eltys[i], 0), _ncol(rows))
            return _combine_tables_with_first!(rows, initialcols, idx, i, 1,
                                               f, gd, incols, newcolnames, firstmulticol)
        end
        j = append_rows!(rows, outcols, 1, colnames)
        if j !== nothing # Need to widen column type
            local newcols
            let i = i, j = j, outcols=outcols, rows=rows # Workaround for julia#15276
                newcols = ntuple(length(outcols)) do k
                    S = eltype(rows isa AbstractDataFrame ? rows[!, k] : rows[k])
                    T = eltype(outcols[k])
                    U = promote_type(S, T)
                    if S <: T || U <: T
                        outcols[k]
                    else
                        copyto!(Tables.allocatecolumn(U, length(outcols[k])), outcols[k])
                    end
                end
            end
            return _combine_tables_with_first!(rows, newcols, idx, i, j,
                                               f, gd, incols, colnames, firstmulticol)
        end
        append!(idx, Iterators.repeated(gdidx[starts[i]], _nrow(rows)))
    end
    return outcols, colnames
end

"""
    by(d::AbstractDataFrame, cols::Any, pairs...;
       sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true)
    by(fun::Union{Function, Type}, d::AbstractDataFrame, cols::Any;
       sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true)
    by(pair::Pair, d::AbstractDataFrame, cols::Any;
       sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true)
    by(d::AbstractDataFrame, cols::Any, fun::Union{Function, Type};
       sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true)
    by(d::AbstractDataFrame, cols::Any, pair::Pair;
       sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true)

Split-apply-combine in one step: apply `fun`, `pair` or `pairs` to each grouping
in `df` based on grouping columns `cols`, and return a `DataFrame`.
This is a shorthand for `combine` called on
`groupby(df, cols, sort=sort, skipmissing=skipmissing)`.

$F_ARGUMENT_RULES

$F_TYPE_RULES

$KWARG_PROCESSING_RULES

The resulting data frame will be sorted if `sort=true` is passed.
Otherwise, ordering of rows is undefined.

If `skipmissing=true` rows with `missing` values in one of the grouping columns
`cols` will be skipped.

See [`groupby`](@ref) and [`combine`](@ref) and for details and more examples.

# Examples
```jldoctest
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> by(df, :a, :c => sum, nrow)
4×3 DataFrame
│ Row │ a     │ c_sum │ nrow  │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 6     │ 2     │
│ 2   │ 2     │ 8     │ 2     │
│ 3   │ 3     │ 10    │ 2     │
│ 4   │ 4     │ 12    │ 2     │

julia> by(sdf -> sum(sdf.c), df, :a) # Slower variant
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> by(df, :a) do d # do syntax for the slower variant
           sum(d.c)
       end
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> by(df, :a, :c => (x -> sum(log, x)) => :sum_log_c) # specifying a name for target column
4×2 DataFrame
│ Row │ a     │ sum_log_c │
│     │ Int64 │ Float64   │
├─────┼───────┼───────────┤
│ 1   │ 1     │ 1.60944   │
│ 2   │ 2     │ 2.48491   │
│ 3   │ 3     │ 3.04452   │
│ 4   │ 4     │ 3.46574   │

julia> by(df, :a, [:b, :c] .=> sum) # passing a vector of pairs
4×3 DataFrame
│ Row │ a     │ b_sum │ c_sum │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 4     │ 6     │
│ 2   │ 2     │ 2     │ 8     │
│ 3   │ 3     │ 4     │ 10    │
│ 4   │ 4     │ 2     │ 12    │

julia> by(df, :a) do sdf # dropping group when DataFrame() is returned
          sdf.c[1] != 1 ? sdf : DataFrame()
       end
6×3 DataFrame
│ Row │ a     │ b     │ c     │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 2     │ 1     │ 2     │
│ 2   │ 2     │ 1     │ 6     │
│ 3   │ 3     │ 2     │ 3     │
│ 4   │ 3     │ 2     │ 7     │
│ 5   │ 4     │ 1     │ 4     │
│ 6   │ 4     │ 1     │ 8     │

julia> by(df, :a, :b => identity => :b, :c => identity => :c,
               [:b, :c] => +, keepkeys=false) # auto-splatting and keepkeys
8×3 DataFrame
│ Row │ b     │ c     │ b_c_+ │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 2     │ 1     │ 3     │
│ 2   │ 2     │ 5     │ 7     │
│ 3   │ 1     │ 2     │ 3     │
│ 4   │ 1     │ 6     │ 7     │
│ 5   │ 2     │ 3     │ 5     │
│ 6   │ 2     │ 7     │ 9     │
│ 7   │ 1     │ 4     │ 5     │
│ 8   │ 1     │ 8     │ 9     │
```
"""
by(f::Union{Base.Callable, Pair}, d::AbstractDataFrame, cols::Any;
   sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true) =
    combine(groupby(d, cols, sort=sort, skipmissing=skipmissing), f,
            keepkeys=keepkeys)
by(d::AbstractDataFrame, cols::Any, f::Base.Callable;
   sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true) =
    combine(groupby(d, cols, sort=sort, skipmissing=skipmissing), f,
            keepkeys=keepkeys)
by(d::AbstractDataFrame, cols::Any, f::Pair;
   sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true) =
    combine(groupby(d, cols, sort=sort, skipmissing=skipmissing), f,
            keepkeys=keepkeys)

by(d::AbstractDataFrame, cols::Any, f::Union{Pair, AbstractVector{<:Pair}, typeof(nrow)}...;
   sort::Bool=false, skipmissing::Bool=false, keepkeys::Bool=true) =
    combine(groupby(d, cols, sort=sort, skipmissing=skipmissing),
            f..., keepkeys=keepkeys)

"""
    aggregate(df::AbstractDataFrame, fs)
    aggregate(df::AbstractDataFrame, cols, fs; sort=false, skipmissing=false)
    aggregate(gd::GroupedDataFrame, fs; sort=false)

Split-apply-combine that applies a set of functions over columns of an
`AbstractDataFrame` or [`GroupedDataFrame`](@ref).
Return an aggregated data frame.

# Arguments
- `df` : an `AbstractDataFrame`
- `gd` : a `GroupedDataFrame`
- `cols` : a column indicator (`Symbol`, `Int`, `Vector{Symbol}`, etc.)
- `fs` : a function or vector of functions to be applied to vectors
  within groups; expects each argument to be a column vector
- `sort` : whether to sort rows according to the values of the grouping columns
- `skipmissing` : whether to skip rows with `missing` values in one of the grouping columns `cols`

Each `fs` should return a value or vector. All returns must be the
same length.

# Examples
```jldoctest
julia> using Statistics

julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> aggregate(df, :a, sum)
4×3 DataFrame
│ Row │ a     │ b_sum │ c_sum │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 4     │ 6     │
│ 2   │ 2     │ 2     │ 8     │
│ 3   │ 3     │ 4     │ 10    │
│ 4   │ 4     │ 2     │ 12    │

julia> aggregate(df, :a, [sum, x->mean(skipmissing(x))])
4×5 DataFrame
│ Row │ a     │ b_sum │ c_sum │ b_function │ c_function │
│     │ Int64 │ Int64 │ Int64 │ Float64    │ Float64    │
├─────┼───────┼───────┼───────┼────────────┼────────────┤
│ 1   │ 1     │ 4     │ 6     │ 2.0        │ 3.0        │
│ 2   │ 2     │ 2     │ 8     │ 1.0        │ 4.0        │
│ 3   │ 3     │ 4     │ 10    │ 2.0        │ 5.0        │
│ 4   │ 4     │ 2     │ 12    │ 1.0        │ 6.0        │

julia> aggregate(groupby(df, :a), [sum, x->mean(skipmissing(x))])
4×5 DataFrame
│ Row │ a     │ b_sum │ c_sum │ b_function │ c_function │
│     │ Int64 │ Int64 │ Int64 │ Float64    │ Float64    │
├─────┼───────┼───────┼───────┼────────────┼────────────┤
│ 1   │ 1     │ 4     │ 6     │ 2.0        │ 3.0        │
│ 2   │ 2     │ 2     │ 8     │ 1.0        │ 4.0        │
│ 3   │ 3     │ 4     │ 10    │ 2.0        │ 5.0        │
│ 4   │ 4     │ 2     │ 12    │ 1.0        │ 6.0        │
```
"""
aggregate(d::AbstractDataFrame, fs::Any; sort::Bool=false) =
    aggregate(d, [fs], sort=sort)
function aggregate(d::AbstractDataFrame, fs::AbstractVector; sort::Bool=false)
    headers = _makeheaders(fs, _names(d))
    _aggregate(d, fs, headers, sort)
end

# Applies aggregate to non-key cols of each SubDataFrame of a GroupedDataFrame
aggregate(gd::GroupedDataFrame, f::Any; sort::Bool=false) = aggregate(gd, [f], sort=sort)
function aggregate(gd::GroupedDataFrame, fs::AbstractVector; sort::Bool=false)
    headers = _makeheaders(fs, setdiff(_names(gd), _names(parent(gd))[gd.cols]))
    res = combine(x -> _aggregate(without(x, gd.cols), fs, headers), gd)
    sort && sort!(res, headers)
    res
end

# Groups DataFrame by cols before applying aggregate
function aggregate(d::AbstractDataFrame, cols, fs::Any;
                   sort::Bool=false, skipmissing::Bool=false)
    aggregate(groupby(d, cols, sort=sort, skipmissing=skipmissing), fs)
end

_makeheaders(fs::AbstractVector, cn::AbstractVector{Symbol}) =
    [Symbol(colname, '_', funname(f)) for f in fs for colname in cn]

function _aggregate(d::AbstractDataFrame, fs::AbstractVector,
                    headers::AbstractVector{Symbol}, sort::Bool=false)
    res = DataFrame(AbstractVector[vcat(f(d[!, i])) for f in fs for i in 1:size(d, 2)], headers, makeunique=true)
    sort && sort!(res, headers)
    res
end
