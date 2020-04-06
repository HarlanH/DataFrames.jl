module TestGrouping

using Test, DataFrames, Random, Statistics, PooledArrays
const ≅ = isequal

"""Check that groups in gd are equal to provided data frames, ignoring order"""
function isequal_unordered(gd::GroupedDataFrame,
                            dfs::AbstractVector{<:AbstractDataFrame})
    n = length(gd)
    @assert n == length(dfs)
    remaining = Set(1:n)
    for i in 1:n
        for j in remaining
            if gd[i] ≅ dfs[j]
                pop!(remaining, j)
                break
            end
        end
    end
    isempty(remaining) || error("gd is not equal to provided groups")
end

"""Helper to set the order of values in the pool and add unused values"""
function _levels!(x::PooledArray, levels::AbstractVector)
    res = similar(x)
    copyto!(res, levels)
    copyto!(res, x)
end
_levels!(x::CategoricalArray, levels::AbstractVector) = levels!(x, levels)

function groupby_checked(df::AbstractDataFrame, keys, args...; kwargs...)
    ogd = groupby(df, keys, args...; kwargs...)

    # To return original object to test when indices have not been computed
    gd = deepcopy(ogd)

    # checking that groups field is consistent with other fields
    # (since == and isequal do not use it)
    # and that idx is increasing per group
    new_groups = zeros(Int, length(gd.groups))
    for idx in eachindex(gd.starts)
        subidx = gd.idx[gd.starts[idx]:gd.ends[idx]]
        @assert issorted(subidx)
        new_groups[subidx] .= idx
    end
    @assert new_groups == gd.groups

    if length(gd) > 0
        se = sort!(collect(zip(gd.starts, gd.ends)))

        # correct start-end range
        @assert se[1][1] > 0
        @assert se[end][2] == length(gd.idx)

        # correct start-end relations
        for i in eachindex(se)
            firstkeys = gd.parent[gd.idx[se[i][1]], gd.cols]
            # all grouping keys must be equal within a group
            @assert all(j -> gd.parent[gd.idx[j], gd.cols] ≅ firstkeys, se[i][1]:se[i][2])
            @assert se[i][1] <= se[i][2]
            if i > 1
                # the blocks returned by groupby must be continuous
                @assert se[i-1][2] + 1 == se[i][1]
            end
        end

        # all grouping keys must be equal within a group
        for (s, e) in zip(gd.starts, gd.ends)
            firstkeys = gd.parent[gd.idx[s], gd.cols]
            @assert all(j -> gd.parent[gd.idx[j], gd.cols] ≅ firstkeys, s:e)
        end
        # all groups have different grouping keys
        @test allunique(eachrow(gd.parent[gd.idx[gd.starts], gd.cols]))
    end

    ogd
end

@testset "parent" begin
    df = DataFrame(a = [1, 1, 2, 2], b = [5, 6, 7, 8])
    gd = groupby(df, :a)
    @test parent(gd) === df
    @test_throws ArgumentError identity.(gd)
end

@testset "consistency" begin
    df = DataFrame(a = [1, 1, 2, 2], b = [5, 6, 7, 8], c = 1:4)
    push!(df.c, 5)
    @test_throws AssertionError gd = groupby(df, :a)

    df = DataFrame(a = [1, 1, 2, 2], b = [5, 6, 7, 8], c = 1:4)
    push!(DataFrames._columns(df), df[:, :a])
    @test_throws AssertionError gd = groupby(df, :a)
end

@testset "accepted columns" begin
    df = DataFrame(A=[1,1,1,2,2,2], B=[1,2,1,2,1,2], C=1:6)
    @test groupby(df, [1,2]) == groupby(df, 1:2) == groupby(df, [:A, :B])
    @test groupby(df, [2,1]) == groupby(df, 2:-1:1) == groupby(df, [:B, :A])
end

@testset "by, groupby and map(::Function, ::GroupedDataFrame)" begin
    Random.seed!(1)
    df = DataFrame(a = repeat(Union{Int, Missing}[1, 3, 2, 4], outer=[2]),
                   b = repeat(Union{Int, Missing}[2, 1], outer=[4]),
                   c = repeat([0, 1], outer=[4]),
                   x = Vector{Union{Float64, Missing}}(randn(8)))

    f1(df) = DataFrame(xmax = maximum(df.x))
    f2(df) = (xmax = maximum(df.x),)
    f3(df) = maximum(df.x)
    f4(df) = [maximum(df.x), minimum(df.x)]
    f5(df) = reshape([maximum(df.x), minimum(df.x)], 2, 1)
    f6(df) = [maximum(df.x) minimum(df.x)]
    f7(df) = (x2 = df.x.^2,)
    f8(df) = DataFrame(x2 = df.x.^2)

    for cols in ([:a, :b], [:b, :a], [:a, :c], [:c, :a],
                 [1, 2], [2, 1], [1, 3], [3, 1],
                 [true, true, false, false], [true, false, true, false])
        colssym = names(df[!, cols])
        hcatdf = hcat(df[!, cols], df[!, Not(cols)])
        nms = names(hcatdf)
        res = unique(df[:, cols])
        res.xmax = [maximum(df[(df[!, colssym[1]] .== a) .& (df[!, colssym[2]] .== b), :x])
                    for (a, b) in zip(res[!, colssym[1]], res[!, colssym[2]])]
        res2 = unique(df[:, cols])[repeat(1:4, inner=2), :]
        res2.x1 = collect(Iterators.flatten(
            [[maximum(df[(df[!, colssym[1]] .== a) .& (df[!, colssym[2]] .== b), :x]),
              minimum(df[(df[!, colssym[1]] .== a) .& (df[!, colssym[2]] .== b), :x])]
             for (a, b) in zip(res[!, colssym[1]], res[!, colssym[2]])]))
        res3 = unique(df[:, cols])
        res3.x1 = [maximum(df[(df[!, colssym[1]] .== a) .& (df[!, colssym[2]] .== b), :x])
                   for (a, b) in zip(res[!, colssym[1]], res[!, colssym[2]])]
        res3.x2 = [minimum(df[(df[!, colssym[1]] .== a) .& (df[!, colssym[2]] .== b), :x])
                   for (a, b) in zip(res[!, colssym[1]], res[!, colssym[2]])]
        res4 = df[:, cols]
        res4.x2 = df.x.^2
        shcatdf = sort(hcatdf, colssym)
        sres = sort(res, colssym)
        sres2 = sort(res2, colssym)
        sres3 = sort(res3, colssym)
        sres4 = sort(res4, colssym)

        # by() without groups sorting
        @test sort(by(identity, df, cols), colssym) == shcatdf
        @test sort(by(df -> df[1, :], df, cols), colssym) ==
            shcatdf[.!nonunique(shcatdf, colssym), :]
        @test by(f1, df, cols) == res
        @test by(f2, df, cols) == res
        @test rename(by(f3, df, cols), :x1 => :xmax) == res
        @test by(f4, df, cols) == res2
        @test by(f5, df, cols) == res2
        @test by(f6, df, cols) == res3
        @test sort(by(f7, df, cols), colssym) == sres4
        @test sort(by(f8, df, cols), colssym) == sres4

        # by() with groups sorting
        @test by(identity, df, cols, sort=true) == shcatdf
        @test by(df -> df[1, :], df, cols, sort=true) ==
            shcatdf[.!nonunique(shcatdf, colssym), :]
        @test by(f1, df, cols, sort=true) == sres
        @test by(f2, df, cols, sort=true) == sres
        @test rename(by(f3, df, cols, sort=true), :x1 => :xmax) == sres
        @test by(f4, df, cols, sort=true) == sres2
        @test by(f5, df, cols, sort=true) == sres2
        @test by(f6, df, cols, sort=true) == sres3
        @test by(f7, df, cols, sort=true) == sres4
        @test by(f8, df, cols, sort=true) == sres4

        @test by(f1, df, [:a]) == by(f1, df, :a)
        @test by(f1, df, [:a], sort=true) == by(f1, df, :a, sort=true)

        # groupby() without groups sorting
        gd = groupby_checked(df, cols)
        @test names(parent(gd))[gd.cols] == colssym
        df_comb = combine(identity, gd)
        @test sort(df_comb, colssym) == shcatdf
        df_ref = DataFrame(gd)
        @test sort(hcat(df_ref[!, cols], df_ref[!, Not(cols)]), colssym) == shcatdf
        @test df_ref.x == df_comb.x
        @test combine(f1, gd) == res
        @test combine(f2, gd) == res
        @test rename(combine(f3, gd), :x1 => :xmax) == res
        @test combine(f4, gd) == res2
        @test combine(f5, gd) == res2
        @test combine(f6, gd) == res3
        @test sort(combine(f7, gd), colssym) == sort(res4, colssym)
        @test sort(combine(f8, gd), colssym) == sort(res4, colssym)

        # groupby() with groups sorting
        gd = groupby_checked(df, cols, sort=true)
        @test names(parent(gd))[gd.cols] == colssym
        for i in 1:length(gd)
            @test all(gd[i][!, colssym[1]] .== sres[i, colssym[1]])
            @test all(gd[i][!, colssym[2]] .== sres[i, colssym[2]])
        end
        @test combine(identity, gd) == shcatdf
        df_ref = DataFrame(gd)
        @test hcat(df_ref[!, cols], df_ref[!, Not(cols)]) == shcatdf
        @test combine(f1, gd) == sres
        @test combine(f2, gd) == sres
        @test rename(combine(f3, gd), :x1 => :xmax) == sres
        @test combine(f4, gd) == sres2
        @test combine(f5, gd) == sres2
        @test combine(f6, gd) == sres3
        @test combine(f7, gd) == sres4
        @test combine(f8, gd) == sres4

        # map() without and with groups sorting
        for sort in (false, true)
            gd = groupby_checked(df, cols, sort=sort)
            v = map(d -> d[:, [:x]], gd)
            @test length(gd) == length(v)
            nms = [colssym; :x]
            @test v[1] == gd[1][:, nms]
            @test v[1] == gd[1][:, nms] &&
                v[2] == gd[2][:, nms] &&
                v[3] == gd[3][:, nms] &&
                v[4] == gd[4][:, nms]
            @test names(parent(v))[v.cols] == colssym
            v = map(f1, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f1, df, cols, sort=sort)
            v = map(f2, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f2, df, cols, sort=sort)
            v = map(f3, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f3, df, cols, sort=sort)
            v = map(f4, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f4, df, cols, sort=sort)
            v = map(f5, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f5, df, cols, sort=sort)
            v = map(f5, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f5, df, cols, sort=sort)
            v = map(f6, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f6, df, cols, sort=sort)
            v = map(f7, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f7, df, cols, sort=sort)
            v = map(f8, gd)
            @test vcat(v[1], v[2], v[3], v[4]) == by(f8, df, cols, sort=sort)
        end
    end

    # test number of potential combinations higher than typemax(Int32)
    N = 2000
    df2 = DataFrame(v1 = levels!(categorical(rand(1:N, 100)), collect(1:N)),
                    v2 = levels!(categorical(rand(1:N, 100)), collect(1:N)),
                    v3 = levels!(categorical(rand(1:N, 100)), collect(1:N)))
    df2b = mapcols(Vector{Int}, df2)
    @test groupby_checked(df2, [:v1, :v2, :v3]) ==
        groupby_checked(df2b, [:v1, :v2, :v3])

    # grouping empty table
    @test length(groupby_checked(DataFrame(A=Int[]), :A)) == 0
    # grouping single row
    @test length(groupby_checked(DataFrame(A=Int[1]), :A)) == 1

    # issue #960
    x = CategoricalArray(collect(1:20))
    df = DataFrame(v1=x, v2=x)
    groupby_checked(df, [:v1, :v2])

    df2 = by(e->1, DataFrame(x=Int64[]), :x)
    @test size(df2) == (0, 1)
    @test sum(df2.x) == 0

    # Check that reordering levels does not confuse groupby
    for df in (DataFrame(Key1 = CategoricalArray(["A", "A", "B", "B", "B", "A"]),
                         Key2 = CategoricalArray(["A", "B", "A", "B", "B", "A"]),
                         Value = 1:6),
                DataFrame(Key1 = PooledArray(["A", "A", "B", "B", "B", "A"]),
                          Key2 = PooledArray(["A", "B", "A", "B", "B", "A"]),
                          Value = 1:6))
        gd = groupby_checked(df, :Key1)
        @test length(gd) == 2
        @test gd[1] == DataFrame(Key1="A", Key2=["A", "B", "A"], Value=[1, 2, 6])
        @test gd[2] == DataFrame(Key1="B", Key2=["A", "B", "B"], Value=[3, 4, 5])
        gd = groupby_checked(df, [:Key1, :Key2])
        @test length(gd) == 4
        @test gd[1] == DataFrame(Key1="A", Key2="A", Value=[1, 6])
        @test gd[2] == DataFrame(Key1="A", Key2="B", Value=2)
        @test gd[3] == DataFrame(Key1="B", Key2="A", Value=3)
        @test gd[4] == DataFrame(Key1="B", Key2="B", Value=[4, 5])
        # Reorder levels, add unused level
        _levels!(df.Key1, ["Z", "B", "A"])
        _levels!(df.Key2, ["Z", "B", "A"])
        gd = groupby_checked(df, :Key1)
        @test gd == groupby_checked(df, :Key1, skipmissing=true)
        @test length(gd) == 2
        if df.Key1 isa CategoricalVector
            @test gd[1] == DataFrame(Key1="B", Key2=["A", "B", "B"], Value=[3, 4, 5])
            @test gd[2] == DataFrame(Key1="A", Key2=["A", "B", "A"], Value=[1, 2, 6])
        else
            @test gd[1] == DataFrame(Key1="A", Key2=["A", "B", "A"], Value=[1, 2, 6])
            @test gd[2] == DataFrame(Key1="B", Key2=["A", "B", "B"], Value=[3, 4, 5])
        end
        gd = groupby_checked(df, [:Key1, :Key2])
        @test gd == groupby_checked(df, [:Key1, :Key2], skipmissing=true)
        @test length(gd) == 4
        if df.Key1 isa CategoricalVector
            @test gd[1] == DataFrame(Key1="B", Key2="B", Value=[4, 5])
            @test gd[2] == DataFrame(Key1="B", Key2="A", Value=3)
            @test gd[3] == DataFrame(Key1="A", Key2="B", Value=2)
            @test gd[4] == DataFrame(Key1="A", Key2="A", Value=[1, 6])
        else
            @test gd[1] == DataFrame(Key1="A", Key2="A", Value=[1, 6])
            @test gd[2] == DataFrame(Key1="A", Key2="B", Value=2)
            @test gd[3] == DataFrame(Key1="B", Key2="A", Value=3)
            @test gd[4] == DataFrame(Key1="B", Key2="B", Value=[4, 5])
        end
        # Make first level unused too
        replace!(df.Key1, "A"=>"B")
        gd = groupby_checked(df, :Key1)
        @test length(gd) == 1
        @test gd[1] == DataFrame(Key1="B", Key2=["A", "B", "A", "B", "B", "A"], Value=1:6)
        gd = groupby_checked(df, [:Key1, :Key2])
        @test gd == groupby_checked(df, [:Key1, :Key2])
        @test length(gd) == 2
        if df.Key1 isa CategoricalVector
            @test gd[1] == DataFrame(Key1="B", Key2="B", Value=[2, 4, 5])
            @test gd[2] == DataFrame(Key1="B", Key2="A", Value=[1, 3, 6])
        else
            @test gd[1] == DataFrame(Key1="B", Key2="A", Value=[1, 3, 6])
            @test gd[2] == DataFrame(Key1="B", Key2="B", Value=[2, 4, 5])
        end
    end

    df = DataFrame(Key1 = CategoricalArray(["A", "A", "B", "B", "B", "A"]),
                    Key2 = CategoricalArray(["A", "B", "A", "B", "B", "A"]),
                    Value = 1:6)

    # Check that CategoricalArray column is preserved when returning a value...
    res = combine(d -> DataFrame(x=d[1, :Key2]), groupby_checked(df, :Key1))
    @test typeof(res.x) == typeof(df.Key2)
    res = combine(d -> (x=d[1, :Key2],), groupby_checked(df, :Key1))
    @test typeof(res.x) == typeof(df.Key2)
    # ...and when returning an array
    res = combine(d -> DataFrame(x=d.Key1), groupby_checked(df, :Key1))
    @test typeof(res.x) == typeof(df.Key1)

    # Check that CategoricalArray and String give a String...
    res = combine(d -> d.Key1 == ["A", "A"] ? DataFrame(x=d[1, :Key1]) : DataFrame(x="C"),
                  groupby_checked(df, :Key1))
    @test res.x isa Vector{String}
    res = combine(d -> d.Key1 == ["A", "A"] ? (x=d[1, :Key1],) : (x="C",),
                  groupby_checked(df, :Key1))
    @test res.x isa Vector{String}
    # ...even when CategoricalString comes second
    res = combine(d -> d.Key1 == ["B", "B"] ? DataFrame(x=d[1, :Key1]) : DataFrame(x="C"),
                  groupby_checked(df, :Key1))
    @test res.x isa Vector{String}
    res = combine(d -> d.Key1 == ["B", "B"] ? (x=d[1, :Key1],) : (x="C",),
                  groupby_checked(df, :Key1))
    @test res.x isa Vector{String}

    df = DataFrame(x = [1, 2, 3], y = [2, 3, 1])

    # Test function returning DataFrameRow
    res = by(d -> DataFrameRow(d, 1, :), df, :x)
    @test res == DataFrame(x=df.x, y=df.y)

    # Test function returning Tuple
    res = by(d -> (sum(d.y),), df, :x)
    @test res == DataFrame(x=df.x, x1=tuple.([2, 3, 1]))

    # Test with some groups returning empty data frames
    @test by(d -> d.x == [1] ? DataFrame(z=[]) : DataFrame(z=1), df, :x) ==
        DataFrame(x=[2, 3], z=[1, 1])
    v = map(d -> d.x == [1] ? DataFrame(z=[]) : DataFrame(z=1), groupby_checked(df, :x))
    @test length(v) == 2
    @test vcat(v[1], v[2]) == DataFrame(x=[2, 3], z=[1, 1])

    # Test that returning values of different types works with NamedTuple
    res = by(d -> d.x == [1] ? 1 : 2.0, df, :x)
    @test res.x1 isa Vector{Float64}
    @test res.x1 == [1, 2, 2]
    # Two columns need to be widened at different times
    res = by(d -> (a=d.x == [1] ? 1 : 2.0, b=d.x == [3] ? missing : "a"), df, :x)
    @test res.a isa Vector{Float64}
    @test res.a == [1, 2, 2]
    @test res.b isa Vector{Union{String,Missing}}
    @test res.b ≅ ["a", "a", missing]
    # Corner case: two columns need to be widened at the same time
    res = by(d -> (a=d.x == [1] ? 1 : 2.0, b=d.x == [1] ? missing : "a"), df, :x)
    @test res.a isa Vector{Float64}
    @test res.a == [1, 2, 2]
    @test res.b isa Vector{Union{String,Missing}}
    @test res.b ≅ [missing, "a", "a"]

    # Test that returning values of different types works with DataFrame
    res = by(d -> DataFrame(x1 = d.x == [1] ? 1 : 2.0), df, :x)
    @test res.x1 isa Vector{Float64}
    @test res.x1 == [1, 2, 2]
    # Two columns need to be widened at different times
    res = by(d -> DataFrame(a=d.x == [1] ? 1 : 2.0, b=d.x == [3] ? missing : "a"), df, :x)
    @test res.a isa Vector{Float64}
    @test res.a == [1, 2, 2]
    @test res.b isa Vector{Union{String,Missing}}
    @test res.b ≅ ["a", "a", missing]
    # Corner case: two columns need to be widened at the same time
    res = by(d -> DataFrame(a=d.x == [1] ? 1 : 2.0, b=d.x == [1] ? missing : "a"), df, :x)
    @test res.a isa Vector{Float64}
    @test res.a == [1, 2, 2]
    @test res.b isa Vector{Union{String,Missing}}
    @test res.b ≅ [missing, "a", "a"]

    # Test return values with columns in different orders
    @test by(d -> d.x == [1] ? (x1=1, x2=3) : (x2=2, x1=4), df, :x) ==
        DataFrame(x=1:3, x1=[1, 4, 4], x2=[3, 2, 2])
    @test by(d -> d.x == [1] ? DataFrame(x1=1, x2=3) : DataFrame(x2=2, x1=4), df, :x) ==
        DataFrame(x=1:3, x1=[1, 4, 4], x2=[3, 2, 2])

    # Test with NamedTuple with columns of incompatible lengths
    @test_throws DimensionMismatch by(d -> (x1=[1], x2=[3, 4]), df, :x)
    @test_throws DimensionMismatch by(d -> d.x == [1] ? (x1=[1], x2=[3]) :
                                                        (x1=[1], x2=[3, 4]), df, :x)

    # Test with incompatible return values
    @test_throws ArgumentError by(d -> d.x == [1] ? (x1=1,) : DataFrame(x1=1), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? DataFrame(x1=1) : (x1=1,), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? NamedTuple() : (x1=1), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? (x1=1) : NamedTuple(), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? 1 : DataFrame(x1=1), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? DataFrame(x1=1) : 1, df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? (x1=1) : (x1=[1]), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? (x1=[1]) : (x1=1), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? 1 : [1], df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? [1] : 1, df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? (x1=1, x2=1) : (x1=[1], x2=1), df, :x)
    @test_throws ArgumentError by(d -> d.x == [1] ? (x1=[1], x2=1) : (x1=1, x2=1), df, :x)
    # Special case allowed due to how implementation works
    @test by(d -> d.x == [1] ? 1 : (x1=1), df, :x) == by(d -> 1, df, :x)

    # Test that columns names and types are respected for empty input
    df = DataFrame(x=Int[], y=String[])
    res = by(d -> 1, df, :x)
    @test size(res) == (0, 1)
    @test res.x isa Vector{Int}

    # Test with empty data frame
    df = DataFrame(x=[], y=[])
    gd = groupby_checked(df, :x)
    @test combine(df -> sum(df.x), gd) == DataFrame(x=[])
    res = map(df -> sum(df.x), gd)
    @test length(res) == 0
    @test res.parent == DataFrame(x=[])

    # Test with zero groups in output
    df = DataFrame(A = [1, 2])
    gd = groupby_checked(df, :A)
    gd2 = map(d -> DataFrame(), gd)
    @test length(gd2) == 0
    @test gd.cols == [1]
    @test isempty(gd2.groups)
    @test isempty(gd2.idx)
    @test isempty(gd2.starts)
    @test isempty(gd2.ends)
    @test parent(gd2) == DataFrame(A=[])
    @test eltype.(eachcol(parent(gd2))) == [Int]

    gd2 = map(d -> DataFrame(X=Int[]), gd)
    @test length(gd2) == 0
    @test gd.cols == [1]
    @test isempty(gd2.groups)
    @test isempty(gd2.idx)
    @test isempty(gd2.starts)
    @test isempty(gd2.ends)
    @test parent(gd2) == DataFrame(A=[], X=[])
    @test eltype.(eachcol(parent(gd2))) == [Int, Int]
end

@testset "grouping with missings" begin
    xv = ["A", missing, "B", "B", "A", "B", "A", "A"]
    yv = ["B", "A", "A", missing, "A", missing, "A", "A"]
    xvars = (xv,
             categorical(xv),
             levels!(categorical(xv), ["A", "B", "X"]),
             levels!(categorical(xv), ["X", "B", "A"]),
             _levels!(PooledArray(xv), ["A", "B", missing]),
             _levels!(PooledArray(xv), ["B", "A", missing, "X"]),
             _levels!(PooledArray(xv), [missing, "X", "A", "B"]))
    yvars = (yv,
             categorical(yv),
             levels!(categorical(yv), ["A", "B", "X"]),
             levels!(categorical(yv), ["B", "X", "A"]),
             _levels!(PooledArray(yv), ["A", "B", missing]),
             _levels!(PooledArray(yv), [missing, "A", "B", "X"]),
             _levels!(PooledArray(yv), ["B", "A", "X", missing]))
    for x in xvars, y in yvars
        df = DataFrame(Key1 = x, Key2 = y, Value = 1:8)

        @testset "sort=false, skipmissing=false" begin
            gd = groupby_checked(df, :Key1)
            @test length(gd) == 3
            @test isequal_unordered(gd, [
                    DataFrame(Key1="A", Key2=["B", "A", "A", "A"], Value=[1, 5, 7, 8]),
                    DataFrame(Key1="B", Key2=["A", missing, missing], Value=[3, 4, 6]),
                    DataFrame(Key1=missing, Key2="A", Value=2)
                ])

            gd = groupby_checked(df, [:Key1, :Key2])
            @test length(gd) == 5
            @test isequal_unordered(gd, [
                    DataFrame(Key1="A", Key2="A", Value=[5, 7, 8]),
                    DataFrame(Key1="A", Key2="B", Value=1),
                    DataFrame(Key1="B", Key2="A", Value=3),
                    DataFrame(Key1="B", Key2=missing, Value=[4, 6]),
                    DataFrame(Key1=missing, Key2="A", Value=2)
                ])
        end

        @testset "sort=false, skipmissing=true" begin
            gd = groupby_checked(df, :Key1, skipmissing=true)
            @test length(gd) == 2
            @test isequal_unordered(gd, [
                DataFrame(Key1="A", Key2=["B", "A", "A", "A"], Value=[1, 5, 7, 8]),
                DataFrame(Key1="B", Key2=["A", missing, missing], Value=[3, 4, 6])
            ])

            gd = groupby_checked(df, [:Key1, :Key2], skipmissing=true)
            @test length(gd) == 3
            @test isequal_unordered(gd, [
                    DataFrame(Key1="A", Key2="A", Value=[5, 7, 8]),
                    DataFrame(Key1="A", Key2="B", Value=1),
                    DataFrame(Key1="B", Key2="A", Value=3),
                ])
        end

        @testset "sort=true, skipmissing=false" begin
            gd = groupby_checked(df, :Key1, sort=true)
            @test length(gd) == 3
            @test isequal_unordered(gd, [
                DataFrame(Key1="A", Key2=["B", "A", "A", "A"], Value=[1, 5, 7, 8]),
                DataFrame(Key1="B", Key2=["A", missing, missing], Value=[3, 4, 6]),
                DataFrame(Key1=missing, Key2="A", Value=2)
            ])
            @test issorted(vcat(gd...), :Key1)

            gd = groupby_checked(df, [:Key1, :Key2], sort=true)
            @test length(gd) == 5
            @test isequal_unordered(gd, [
                DataFrame(Key1="A", Key2="A", Value=[5, 7, 8]),
                DataFrame(Key1="A", Key2="B", Value=1),
                DataFrame(Key1="B", Key2="A", Value=3),
                DataFrame(Key1="B", Key2=missing, Value=[4, 6]),
                DataFrame(Key1=missing, Key2="A", Value=2)
            ])
            @test issorted(vcat(gd...), [:Key1, :Key2])
        end

        @testset "sort=true, skipmissing=true" begin
            gd = groupby_checked(df, :Key1, sort=true, skipmissing=true)
            @test length(gd) == 2
            @test isequal_unordered(gd, [
                DataFrame(Key1="A", Key2=["B", "A", "A", "A"], Value=[1, 5, 7, 8]),
                DataFrame(Key1="B", Key2=["A", missing, missing], Value=[3, 4, 6])
            ])
            @test issorted(vcat(gd...), :Key1)

            gd = groupby_checked(df, [:Key1, :Key2], sort=true, skipmissing=true)
            @test length(gd) == 3
            @test isequal_unordered(gd, [
                DataFrame(Key1="A", Key2="A", Value=[5, 7, 8]),
                DataFrame(Key1="A", Key2="B", Value=1),
                DataFrame(Key1="B", Key2="A", Value=3)
            ])
            @test issorted(vcat(gd...), [:Key1, :Key2])
        end
    end
end

@testset "grouping with three keys" begin
    # We need many rows so that optimized CategoricalArray method is used
    xv = rand(["A", "B", missing], 100)
    yv = rand(["A", "B", missing], 100)
    zv = rand(["A", "B", missing], 100)
    xvars = (xv,
             categorical(xv),
             levels!(categorical(xv), ["A", "B", "X"]),
             levels!(categorical(xv), ["X", "B", "A"]),
             _levels!(PooledArray(xv), ["A", "B", missing]),
             _levels!(PooledArray(xv), ["B", "A", missing, "X"]),
             _levels!(PooledArray(xv), [missing, "X", "A", "B"]))
    yvars = (yv,
             categorical(yv),
             levels!(categorical(yv), ["A", "B", "X"]),
             levels!(categorical(yv), ["B", "X", "A"]),
             _levels!(PooledArray(yv), ["A", "B", missing]),
             _levels!(PooledArray(yv), [missing, "A", "B", "X"]),
             _levels!(PooledArray(yv), ["B", "A", "X", missing]))
    zvars = (zv,
             categorical(zv),
             levels!(categorical(zv), ["B", "A"]),
             levels!(categorical(zv), ["X", "A", "B"]),
             _levels!(PooledArray(zv), ["A", missing, "B"]),
             _levels!(PooledArray(zv), ["B", missing, "A", "X"]),
             _levels!(PooledArray(zv), ["X", "A", missing, "B"]))
    for x in xvars, y in yvars, z in zvars
        df = DataFrame(Key1 = x, Key2 = y, Key3 = z, Value = string.(1:100))
        dfb = mapcols(Vector{Union{String, Missing}}, df)

        gd = groupby_checked(df, [:Key1, :Key2, :Key3], sort=true)
        dfs = [groupby_checked(dfb, [:Key1, :Key2, :Key3], sort=true)...]
        @test isequal_unordered(gd, dfs)
        @test issorted(vcat(gd...), [:Key1, :Key2, :Key3])
        gd = groupby_checked(df, [:Key1, :Key2, :Key3], sort=true, skipmissing=true)
        dfs = [groupby_checked(dfb, [:Key1, :Key2, :Key3], sort=true, skipmissing=true)...]
        @test isequal_unordered(gd, dfs)
        @test issorted(vcat(gd...), [:Key1, :Key2, :Key3])

        # This is an implementation detail but it allows checking
        # that the optimized method is used
        if df.Key1 isa CategoricalVector &&
            df.Key2 isa CategoricalVector &&
            df.Key3 isa CategoricalVector
            @test groupby_checked(df, [:Key1, :Key2, :Key3], sort=true) ≅
                groupby_checked(df, [:Key1, :Key2, :Key3], sort=false)
            @test groupby_checked(df, [:Key1, :Key2, :Key3], sort=true, skipmissing=true) ≅
                groupby_checked(df, [:Key1, :Key2, :Key3], sort=false, skipmissing=true)
        end
    end
end

@testset "grouping with hash collisions" begin
    # Hash collisions are almost certain on 32-bit
    df = DataFrame(A=1:2_000_000)
    gd = groupby_checked(df, :A)
    @test DataFrame(df) == df
end

@testset "by, combine and map with pair interface" begin
    vexp = x -> exp.(x)
    Random.seed!(1)
    df = DataFrame(a = repeat([1, 3, 2, 4], outer=[2]),
                   b = repeat([2, 1], outer=[4]),
                   c = rand(Int, 8))

    # Only test that different by syntaxes work,
    # and rely on tests below for deeper checks
    @test by(df, :a, :c => sum) ==
        by(:c => sum, df, :a) ==
        by(df, :a, :c => sum => :c_sum) ==
        by(:c => sum => :c_sum, df, :a) ==
        by(df, :a, [:c => sum]) ==
        by(df, :a, [:c => sum => :c_sum]) ==
        by(d -> (c_sum=sum(d.c),), df, :a) ==
        by(df, :a, d -> (c_sum=sum(d.c),))

    @test by(df, :a, :c => vexp) ==
        by(:c => vexp, df, :a) ==
        by(df, :a, :c => vexp => :c_function) ==
        by(:c => vexp => :c_function, df, :a) ==
        by(:c => c -> (c_function = vexp(c),), df, :a) ==
        by(df, :a, :c => c -> (c_function = vexp(c),)) ==
        by(df, :a, [:c => vexp]) ==
        by(df, :a, [:c => vexp => :c_function]) ==
        by(d -> (c_function=vexp(d.c),), df, :a) ==
        by(df, :a, d -> (c_function=vexp(d.c),))

    @test by(df, :a, :b => sum, :c => sum) ==
        by(df, :a, :b => sum => :b_sum, :c => sum => :c_sum) ==
        by(df, :a, [:b => sum, :c => sum]) ==
        by(df, :a, [:b => sum => :b_sum, :c => sum => :c_sum]) ==
        by(d -> (b_sum=sum(d.b), c_sum=sum(d.c)), df, :a) ==
        by(df, :a, d -> (b_sum=sum(d.b), c_sum=sum(d.c)))

    @test by(df, :a, :b => vexp, :c => identity) ==
        by(df, :a, :b => vexp => :b_function, :c => identity => :c_identity) ==
        by(df, :a, [:b => vexp, :c => identity]) ==
        by(df, :a, [:b => vexp => :b_function, :c => identity => :c_identity]) ==
        by(d -> (b_function=vexp(d.b), c_identity=identity(d.c)), df, :a) ==
        by(df, :a, d -> (b_function=vexp(d.b), c_identity=identity(d.c))) ==
        by(df, :a, [:b, :c] => (b, c) -> (b_function=vexp(b), c_identity=identity(c))) ==
        by([:b, :c] => (b, c) -> (b_function=vexp(b), c_identity=identity(c)), df, :a)

    @test by(x -> extrema(x.c), df, :a) == by(:c => (x -> extrema(x)) => :x1, df, :a)
    @test by(x -> x.b+x.c, df, :a) == by([:b,:c] => (+) => :x1, df, :a)
    @test by(x -> (p=x.b, q=x.c), df, :a) ==
          by([:b,:c] => (b,c) -> (p=b,q=c), df, :a) ==
          by(df, :a, x -> (p=x.b, q=x.c)) ==
          by(df, :a, [:b,:c] => (b,c) -> (p=b,q=c))
    @test by(x -> DataFrame(p=x.b, q=x.c), df, :a) ==
          by([:b,:c] => (b,c) -> DataFrame(p=b,q=c), df, :a) ==
          by(df, :a, x -> DataFrame(p=x.b, q=x.c)) ==
          by(df, :a, [:b,:c] => (b,c) -> DataFrame(p=b,q=c))
    @test by(x -> [1 2; 3 4], df, :a) ==
          by([:b,:c] => (b,c) -> [1 2; 3 4], df, :a) ==
          by(df, :a, x -> [1 2; 3 4]) ==
          by(df, :a, [:b,:c] => (b,c) -> [1 2; 3 4])
    @test by(nrow, df, :a) == by(df, :a, nrow) == by(df, :a, [nrow => :nrow]) ==
          by(df, :a, 1 => length => :nrow)
    @test by(nrow => :res, df, :a) == by(df, :a, nrow => :res) ==
          by(df, :a, [nrow => :res]) == by(df, :a, 1 => length => :res)
    @test by(df, :a, nrow => :res, nrow, [nrow => :res2]) ==
          by(df, :a, 1 => length => :res, 1 => length => :nrow, 1 => length => :res2)

    @test_throws ArgumentError by([:b,:c] => ((b,c) -> [1 2; 3 4]) => :xxx, df, :a)
    @test_throws ArgumentError by(df, :a, [:b,:c] => ((b,c) -> [1 2; 3 4]) => :xxx)
    @test_throws ArgumentError by(df, :a, nrow, nrow)
    @test_throws MethodError by(df, :a, [nrow])

    gd = groupby(df, :a)

    # Only test that different combine syntaxes work,
    # and rely on tests below for deeper checks
    @test combine(gd, :c => sum) ==
        combine(:c => sum, gd) ==
        combine(gd, :c => sum => :c_sum) ==
        combine(:c => sum => :c_sum, gd) ==
        combine(gd, [:c => sum]) ==
        combine(gd, [:c => sum => :c_sum]) ==
        combine(d -> (c_sum=sum(d.c),), gd) ==
        combine(gd, d -> (c_sum=sum(d.c),))

    @test combine(gd, :c => vexp) ==
        combine(:c => vexp, gd) ==
        combine(gd, :c => vexp => :c_function) ==
        combine(:c => vexp => :c_function, gd) ==
        combine(:c => c -> (c_function = vexp(c),), gd) ==
        combine(gd, :c => c -> (c_function = vexp(c),)) ==
        combine(gd, [:c => vexp]) ==
        combine(gd, [:c => vexp => :c_function]) ==
        combine(d -> (c_function=exp.(d.c),), gd) ==
        combine(gd, d -> (c_function=exp.(d.c),))

    @test combine(gd, :b => sum, :c => sum) ==
        combine(gd, :b => sum => :b_sum, :c => sum => :c_sum) ==
        combine(gd, [:b => sum, :c => sum]) ==
        combine(gd, [:b => sum => :b_sum, :c => sum => :c_sum]) ==
        combine(d -> (b_sum=sum(d.b), c_sum=sum(d.c)), gd) ==
        combine(gd, d -> (b_sum=sum(d.b), c_sum=sum(d.c)))

    @test combine(gd, :b => vexp, :c => identity) ==
        combine(gd, :b => vexp => :b_function, :c => identity => :c_identity) ==
        combine(gd, [:b => vexp, :c => identity]) ==
        combine(gd, [:b => vexp => :b_function, :c => identity => :c_identity]) ==
        combine(d -> (b_function=vexp(d.b), c_identity=d.c), gd) ==
        combine(gd, d -> (b_function=vexp(d.b), c_identity=d.c)) ==
        combine([:b, :c] => (b, c) -> (b_function=vexp(b), c_identity=c), gd) ==
        combine(gd, [:b, :c] => (b, c) -> (b_function=vexp(b), c_identity=c))

    @test combine(x -> extrema(x.c), gd) == combine(:c => (x -> extrema(x)) => :x1, gd)
    @test combine(x -> x.b+x.c, gd) == combine([:b,:c] => (+) => :x1, gd)
    @test combine(x -> (p=x.b, q=x.c), gd) ==
          combine([:b,:c] => (b,c) -> (p=b,q=c), gd) ==
          combine(gd, x -> (p=x.b, q=x.c)) ==
          combine(gd, [:b,:c] => (b,c) -> (p=b,q=c))
    @test combine(x -> DataFrame(p=x.b, q=x.c), gd) ==
          combine([:b,:c] => (b,c) -> DataFrame(p=b,q=c), gd) ==
          combine(gd, x -> DataFrame(p=x.b, q=x.c)) ==
          combine(gd, [:b,:c] => (b,c) -> DataFrame(p=b,q=c))
    @test combine(x -> [1 2; 3 4], gd) ==
          combine([:b,:c] => (b,c) -> [1 2; 3 4], gd) ==
          combine(gd, x -> [1 2; 3 4]) ==
          combine(gd, [:b,:c] => (b,c) -> [1 2; 3 4])
    @test combine(nrow, gd) == combine(gd, nrow) == combine(gd, [nrow => :nrow]) ==
          combine(gd, 1 => length => :nrow)
    @test combine(nrow => :res, gd) == combine(gd, nrow => :res) ==
          combine(gd, [nrow => :res]) == combine(gd, 1 => length => :res)
    @test combine(gd, nrow => :res, nrow, [nrow => :res2]) ==
          combine(gd, 1 => length => :res, 1 => length => :nrow, 1 => length => :res2)
    @test_throws ArgumentError combine([:b,:c] => ((b,c) -> [1 2; 3 4]) => :xxx, gd)
    @test_throws ArgumentError combine(gd, [:b,:c] => ((b,c) -> [1 2; 3 4]) => :xxx)
    @test_throws ArgumentError combine(gd, nrow, nrow)
    @test_throws MethodError combine(gd, [nrow])

    for f in (map, combine)
        for col in (:c, 3)
            @test f(col => sum, gd) == f(d -> (c_sum=sum(d.c),), gd)
            @test f(col => x -> sum(x), gd) == f(d -> (c_function=sum(d.c),), gd)
            @test f(col => x -> (z=sum(x),), gd) == f(d -> (z=sum(d.c),), gd)
            @test f(col => x -> DataFrame(z=sum(x),), gd) == f(d -> (z=sum(d.c),), gd)
            @test f(col => identity, gd) == f(d -> (c_identity=d.c,), gd)
            @test f(col => x -> (z=x,), gd) == f(d -> (z=d.c,), gd)

            @test f(col => sum => :xyz, gd) ==
                f(d -> (xyz=sum(d.c),), gd)
            @test f(col => (x -> sum(x)) => :xyz, gd) ==
                f(d -> (xyz=sum(d.c),), gd)
            @test f(col => (x -> (sum(x),)) => :xyz, gd) ==
                f(d -> (xyz=(sum(d.c),),), gd)
            @test f(nrow, gd) == f(d -> (nrow=length(d.c),), gd)
            @test f(nrow => :res, gd) == f(d -> (res=length(d.c),), gd)
            @test f(col => sum => :res, gd) == f(d -> (res=sum(d.c),), gd)
            @test f(col => (x -> sum(x)) => :res, gd) == f(d -> (res=sum(d.c),), gd)
            @test_throws ArgumentError f(col => (x -> (z=sum(x),)) => :xyz, gd)
            @test_throws ArgumentError f(col => (x -> DataFrame(z=sum(x),)) => :xyz, gd)
            @test_throws ArgumentError f(col => (x -> (z=x,)) => :xyz, gd)
            @test_throws ArgumentError f(col => x -> (z=1, xzz=[1]), gd)
        end
        for cols in ([:b, :c], 2:3, [2, 3], [false, true, true])
            @test f(cols => (b,c) -> (y=exp.(b), z=c), gd) ==
                f(d -> (y=exp.(d.b), z=d.c), gd)
            @test f(cols => (b,c) -> [exp.(b) c], gd) ==
                f(d -> [exp.(d.b) d.c], gd)
            @test f(cols => ((b,c) -> sum(b) + sum(c)) => :xyz, gd) ==
                f(d -> (xyz=sum(d.b) + sum(d.c),), gd)
            if eltype(cols) === Bool
                cols2 = [[false, true, false], [false, false, true]]
                @test_throws MethodError f((xyz = cols[1] => sum, xzz = cols2[2] => sum), gd)
                @test_throws MethodError f((xyz = cols[1] => sum, xzz = cols2[1] => sum), gd)
                @test_throws MethodError f((xyz = cols[1] => sum, xzz = cols2[2] => x -> first(x)), gd)
            else
                cols2 = cols
                if f === combine
                    @test f(gd, cols2[1] => sum => :xyz, cols2[2] => sum => :xzz) ==
                        f(d -> (xyz=sum(d.b), xzz=sum(d.c)), gd)
                    @test f(gd, cols2[1] => sum => :xyz, cols2[1] => sum => :xzz) ==
                        f(d -> (xyz=sum(d.b), xzz=sum(d.b)), gd)
                    @test f(gd, cols2[1] => sum => :xyz, cols2[2] => (x -> first(x)) => :xzz) ==
                        f(d -> (xyz=sum(d.b), xzz=first(d.c)), gd)
                    @test_throws ArgumentError f(gd, cols2[1] => vexp => :xyz, cols2[2] => sum => :xzz)
                end
            end

            @test_throws ArgumentError f(cols => (b,c) -> (y=exp.(b), z=sum(c)), gd)
            @test_throws ArgumentError f(cols2 => ((b,c) -> DataFrame(y=exp.(b), z=sum(c))) => :xyz, gd)
            @test_throws ArgumentError f(cols2 => ((b,c) -> [exp.(b) c]) => :xyz, gd)
        end
    end
end

struct TestType end
Base.isless(::TestType, ::Int) = true
Base.isless(::Int, ::TestType) = false
Base.isless(::TestType, ::TestType) = false

@testset "combine with aggregation functions (skipmissing=$skip, sort=$sort, indices=$indices)" for
    skip in (false, true), sort in (false, true), indices in (false, true)
    Random.seed!(1)
    df = DataFrame(a = rand([1:5;missing], 20), x1 = rand(Int, 20), x2 = rand(Complex{Int}, 20))

    for f in (sum, prod, maximum, minimum, mean, var, std, first, last, length)
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices

        res = combine(gd, :x1 => f => :y)
        expected = combine(gd, :x1 => (x -> f(x)) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)

        for T in (Union{Missing, Int}, Union{Int, Int8},
                  Union{Missing, Int, Int8})
            df.x3 = Vector{T}(df.x1)
            gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
            indices && @test gd.idx !== nothing # Trigger computation of indices
            res = combine(gd, :x3 => f => :y)
            expected = combine(gd, :x3 => (x -> f(x)) => :y)
            @test res ≅ expected
            @test typeof(res.y) == typeof(expected.y)
        end

        f === length && continue

        df.x3 = allowmissing(df.x1)
        df.x3[1] = missing
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices
        res = combine(gd, :x3 => f => :y)
        expected = combine(gd, :x3 => (x -> f(x)) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)
        res = combine(gd, :x3 => f∘skipmissing => :y)
        expected = combine(gd, :x3 => (x -> f(collect(skipmissing(x)))) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)

        # Test reduction over group with only missing values
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices
        gd[1][:, :x3] .= missing
        if f in (maximum, minimum, first, last)
            @test_throws ArgumentError combine(gd, :x3 => f∘skipmissing => :y)
        else
            res = combine(gd, :x3 => f∘skipmissing => :y)
            expected = combine(gd, :x3 => (x -> f(collect(skipmissing(x)))) => :y)
            @test res ≅ expected
            @test typeof(res.y) == typeof(expected.y)
        end
    end
    # Test complex numbers
    for f in (sum, prod, mean, var, std, first, last, length)
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices

        res = combine(gd, :x2 => f => :y)
        expected = combine(gd, :x2 => (x -> f(x)) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)
    end
    # Test CategoricalArray
    for f in (maximum, minimum, first, last, length),
        (T, m) in ((Int, false),
                   (Union{Missing, Int}, false), (Union{Missing, Int}, true))
        df.x3 = CategoricalVector{T}(df.x1)
        m && (df.x3[1] = missing)
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices
        res = combine(gd, :x3 => f => :y)
        expected = combine(gd, :x3 => (x -> f(x)) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)

        f === length && continue

        res = combine(gd, :x3 => f∘skipmissing => :y)
        expected = combine(gd, :x3 => (x -> f(collect(skipmissing(x)))) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)
        if m
            gd[1][:, :x3] .= missing
            @test_throws ArgumentError combine(gd, :x3 => f∘skipmissing => :y)
        end
    end
    @test combine(gd, :x1 => maximum => :y, :x2 => sum => :z) ≅
        combine(gd, :x1 => (x -> maximum(x)) => :y, :x2 => (x -> sum(x)) => :z)

    # Test floating point corner cases
    df = DataFrame(a = [1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6],
                   x1 = [0.0, 1.0, 2.0, NaN, NaN, NaN, Inf, Inf, Inf, 1.0, NaN, 0.0, -0.0])

    for f in (sum, prod, maximum, minimum, mean, var, std, first, last, length)
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices

        res = combine(gd, :x1 => f => :y)
        expected = combine(gd, :x1 => (x -> f(x)) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)

        f === length && continue

        df.x3 = allowmissing(df.x1)
        df.x3[1] = missing
        gd = groupby_checked(df, :a, skipmissing=skip, sort=sort)
        indices && @test gd.idx !== nothing # Trigger computation of indices
        res = combine(gd, :x3 => f => :y)
        expected = combine(gd, :x3 => (x -> f(x)) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)
        res = combine(gd, :x3 => f∘skipmissing => :y)
        expected = combine(gd, :x3 => (x -> f(collect(skipmissing(x)))) => :y)
        @test res ≅ expected
        @test typeof(res.y) == typeof(expected.y)
    end

    df = DataFrame(x = [1, 1, 2, 2], y = Any[1, 2.0, 3.0, 4.0])
    res = by(df, :x, :y => maximum => :z)
    @test res.z isa Vector{Float64}
    @test res.z == by(df, :x, :y => (x -> maximum(x)) => :z).z

    # Test maximum when no promotion rule exists
    df = DataFrame(x = [1, 1, 2, 2], y = [1, TestType(), TestType(), TestType()])
    gd = groupby_checked(df, :x, skipmissing=skip, sort=sort)
    indices && @test gd.idx !== nothing # Trigger computation of indices
    for f in (maximum, minimum)
        res = combine(gd, :y => maximum => :z)
        @test res.z isa Vector{Any}
        @test res.z == by(df, :x, :y => (x -> maximum(x)) => :z).z
    end
end

@testset "combine and map with columns named like grouping keys" begin
    df = DataFrame(x=["a", "a", "b", missing], y=1:4)
    gd = groupby(df, :x)
    @test combine(identity, gd) ≅ df
    @test combine(d -> d[:, [2, 1]], gd) ≅ df
    @test_throws ArgumentError combine(f -> DataFrame(x=["a", "b"], z=[1, 1]), gd)
    @test map(identity, gd) ≅ gd
    @test map(d -> d[:, [2, 1]], gd) ≅ gd
    @test_throws ArgumentError map(f -> DataFrame(x=["a", "b"], z=[1, 1]), gd)

    gd = groupby(df, :x, skipmissing=true)
    @test combine(identity, gd) == df[1:3, :]
    @test combine(d -> d[:, [2, 1]], gd) == df[1:3, :]
    @test_throws ArgumentError combine(f -> DataFrame(x=["a", "b"], z=[1, 1]), gd)
    @test map(identity, gd) == gd
    @test map(d -> d[:, [2, 1]], gd) == gd
    @test_throws ArgumentError map(f -> DataFrame(x=["a", "b"], z=[1, 1]), gd)
end

@testset "iteration protocol" begin
    gd = groupby_checked(DataFrame(A = [:A, :A, :B, :B], B = 1:4), :A)
    count = 0
    for v in gd
        count += 1
        @test v ≅ gd[count]
    end
    @test count == length(gd)
end

@testset "type stability of index fields" begin
    gd = groupby_checked(DataFrame(A = [:A, :A, :B, :B], B = 1:4), :A)
    idx(gd::GroupedDataFrame) = gd.idx
    starts(gd::GroupedDataFrame) = gd.starts
    ends(gd::GroupedDataFrame) = gd.ends
    @inferred idx(gd) == getfield(gd, :idx)
    @inferred starts(gd) == getfield(gd, :starts)
    @inferred ends(gd) == getfield(gd, :ends)
end

@testset "Array-like getindex" begin
    df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                   b = 1:8)
    gd = groupby_checked(df, :a)

    # Invalid
    @test_throws ArgumentError gd[true]
    @test_throws ArgumentError gd[[1, 2, 1]]  # Duplicate
    @test_throws ArgumentError gd["a"]

    # Single integer
    @test gd[1] isa SubDataFrame
    @test gd[1] == view(df, [1, 5], :)
    @test_throws BoundsError gd[5]

    # first, last, lastindex
    @test first(gd) == gd[1]
    @test last(gd) == gd[4]
    @test lastindex(gd) == 4
    @test gd[end] == gd[4]

    # Boolean array
    idx2 = [false, true, false, false]
    gd2 = gd[idx2]
    @test length(gd2) == 1
    @test gd2[1] == gd[2]
    @test_throws BoundsError gd[[true, false]]
    @test gd2.groups == [0, 1, 0, 0, 0, 1, 0, 0]
    @test gd2.starts == [3]
    @test gd2.ends == [4]
    @test gd2.idx == gd.idx
    @test gd[BitArray(idx2)] ≅ gd2
    @test gd[1:2][false:true] ≅ gd[[2]]  # AbstractArray{Bool}

    # Colon
    gd3 = gd[:]
    @test gd3 isa GroupedDataFrame
    @test length(gd3) == 4
    @test gd3 == gd
    for i in 1:4
        @test gd3[i] == gd[i]
    end

    # Integer array
    idx4 = [2,1]
    gd4 = gd[idx4]
    @test gd4 isa GroupedDataFrame
    @test length(gd4) == 2
    for (i, j) in enumerate(idx4)
        @test gd4[i] == gd[j]
    end
    @test gd4.groups == [2, 1, 0, 0, 2, 1, 0, 0]
    @test gd4.starts == [3,1]
    @test gd4.ends == [4,2]
    @test gd4.idx == gd.idx

    # Infer eltype
    @test gd[Array{Any}(idx4)] ≅ gd4
    # Mixed (non-Bool) integer types should work
    @test gd[Any[idx4[1], Unsigned(idx4[2])]] ≅ gd4
    @test_throws ArgumentError gd[Any[2, true]]

    # Out-of-bounds
    @test_throws BoundsError gd[1:5]
end

@testset "== and isequal" begin
    df1 = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                    b = 1:8)
    df2 = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                    b = [1:7;missing])
    gd1 = groupby_checked(df1, :a)
    gd2 = groupby_checked(df2, :a)
    @test gd1 == gd1
    @test isequal(gd1, gd1)
    @test ismissing(gd1 == gd2)
    @test !isequal(gd1, gd2)
    @test ismissing(gd2 == gd2)
    @test isequal(gd2, gd2)
    df1.c = df1.a
    df2.c = df2.a
    @test gd1 != groupby_checked(df2, :c)
    df2[7, :b] = 10
    @test gd1 != gd2
    df3 = DataFrame(a = repeat([1, 2, 3, missing], outer=[2]),
                    b = 1:8)
    df4 = DataFrame(a = repeat([1, 2, 3, missing], outer=[2]),
                    b = [1:7;missing])
    gd3 = groupby_checked(df3, :a)
    gd4 = groupby_checked(df4, :a)
    @test ismissing(gd3 == gd4)
    @test !isequal(gd3, gd4)
    gd3 = groupby_checked(df3, :a, skipmissing = true)
    gd4 = groupby_checked(df4, :a, skipmissing = true)
    @test gd3 == gd4
    @test isequal(gd3, gd4)
end

@testset "show" begin
    function capture_stdout(f::Function)
        oldstdout = stdout
        rd, wr = redirect_stdout()
        f()
        str = String(readavailable(rd))
        redirect_stdout(oldstdout)
        size = displaysize(rd)
        close(rd)
        close(wr)
        str, size
    end

    df = DataFrame(A = Int64[1:4;], B = ["x\"", "∀ε>0: x+ε>x", "z\$", "A\nC"],
                   C = Float32[1.0, 2.0, 3.0, 4.0])
    gd = groupby_checked(df, :A)
    io = IOContext(IOBuffer(), :limit=>true)
    show(io, gd)
    str = String(take!(io.io))
    summary_str = summary(gd)
    @test summary_str == "$GroupedDataFrame with 4 groups based on key: A"
    @test str == """
    $summary_str
    First Group (1 row): A = 1
    │ Row │ A     │ B      │ C       │
    │     │ Int64 │ String │ Float32 │
    ├─────┼───────┼────────┼─────────┤
    │ 1   │ 1     │ x"     │ 1.0     │
    ⋮
    Last Group (1 row): A = 4
    │ Row │ A     │ B      │ C       │
    │     │ Int64 │ String │ Float32 │
    ├─────┼───────┼────────┼─────────┤
    │ 1   │ 4     │ A\\nC   │ 4.0     │"""
    show(io, gd, allgroups=true)
    str = String(take!(io.io))
    @test str == """
    $summary_str
    Group 1 (1 row): A = 1
    │ Row │ A     │ B      │ C       │
    │     │ Int64 │ String │ Float32 │
    ├─────┼───────┼────────┼─────────┤
    │ 1   │ 1     │ x\"     │ 1.0     │
    Group 2 (1 row): A = 2
    │ Row │ A     │ B           │ C       │
    │     │ Int64 │ String      │ Float32 │
    ├─────┼───────┼─────────────┼─────────┤
    │ 1   │ 2     │ ∀ε>0: x+ε>x │ 2.0     │
    Group 3 (1 row): A = 3
    │ Row │ A     │ B      │ C       │
    │     │ Int64 │ String │ Float32 │
    ├─────┼───────┼────────┼─────────┤
    │ 1   │ 3     │ z\$     │ 3.0     │
    Group 4 (1 row): A = 4
    │ Row │ A     │ B      │ C       │
    │     │ Int64 │ String │ Float32 │
    ├─────┼───────┼────────┼─────────┤
    │ 1   │ 4     │ A\\nC   │ 4.0     │"""

    # Test two-argument show
    str1, dsize = capture_stdout() do
        show(gd)
    end
    io = IOContext(IOBuffer(), :limit=>true, :displaysize=>dsize)
    show(io, gd)
    str2 = String(take!(io.io))
    @test str1 == str2


    @test sprint(show, "text/html", gd) ==
        "<p><b>$GroupedDataFrame with 4 groups based on key: A</b></p>" *
        "<p><i>First Group (1 row): A = 1</i></p><table class=\"data-frame\">" *
        "<thead><tr><th></th><th>A</th><th>B</th><th>C</th></tr><tr><th></th>" *
        "<th>Int64</th><th>String</th><th>Float32</th></tr></thead>" *
        "<tbody><tr><th>1</th><td>1</td><td>x\"</td><td>1.0</td></tr></tbody>" *
        "</table><p>&vellip;</p><p><i>Last Group (1 row): A = 4</i></p>" *
        "<table class=\"data-frame\"><thead><tr><th></th><th>A</th><th>B</th><th>C</th></tr>" *
        "<tr><th></th><th>Int64</th><th>String</th><th>Float32</th></tr></thead>" *
        "<tbody><tr><th>1</th><td>4</td><td>A\\nC</td><td>4.0</td></tr></tbody></table>"

    @test sprint(show, "text/latex", gd) == """
        $GroupedDataFrame with 4 groups based on key: A

        First Group (1 row): A = 1

        \\begin{tabular}{r|ccc}
        \t& A & B & C\\\\
        \t\\hline
        \t& Int64 & String & Float32\\\\
        \t\\hline
        \t1 & 1 & x" & 1.0 \\\\
        \\end{tabular}

        \$\\dots\$

        Last Group (1 row): A = 4

        \\begin{tabular}{r|ccc}
        \t& A & B & C\\\\
        \t\\hline
        \t& Int64 & String & Float32\\\\
        \t\\hline
        \t1 & 4 & A\\textbackslash{}nC & 4.0 \\\\
        \\end{tabular}
        """

    gd = groupby(DataFrame(a=[Symbol("&")], b=["&"]), [1,2])
    summary_str = summary(gd)
    @test summary_str == "$GroupedDataFrame with 1 group based on keys: a, b"
    @test sprint(show, gd) === """
        $summary_str
        Group 1 (1 row): a = :&, b = "&"
        │ Row │ a      │ b      │
        │     │ Symbol │ String │
        ├─────┼────────┼────────┤
        │ 1   │ &      │ &      │"""

    @test sprint(show, "text/html", gd) ==
        "<p><b>$summary_str</b></p><p><i>" *
        "First Group (1 row): a = :&amp;, b = \"&amp;\"</i></p>" *
        "<table class=\"data-frame\"><thead><tr><th></th><th>a</th><th>b</th></tr>" *
        "<tr><th></th><th>Symbol</th><th>String</th></tr></thead><tbody><tr><th>1</th>" *
        "<td>&amp;</td><td>&amp;</td></tr></tbody></table>"

    @test sprint(show, "text/latex", gd) == """
        $summary_str

        First Group (1 row): a = :\\&, b = "\\&"

        \\begin{tabular}{r|cc}
        \t& a & b\\\\
        \t\\hline
        \t& Symbol & String\\\\
        \t\\hline
        \t1 & \\& & \\& \\\\
        \\end{tabular}
        """

        gd = groupby(DataFrame(a = [1,2], b = [1.0, 2.0]), :a)
        @test sprint(show, "text/csv", gd) == """
        "a","b"
        1,1.0
        2,2.0
        """
        @test sprint(show, "text/tab-separated-values", gd) == """
        "a"\t"b"
        1\t1.0
        2\t2.0
        """
end

@testset "DataFrame" begin
    dfx = DataFrame(A = [missing, :A, :B, :A, :B, missing], B = 1:6)

    for df in [dfx, view(dfx, :, :)]
        gd = groupby_checked(df, :A)
        @test sort(DataFrame(gd), :B) ≅ sort(df, :B)
        @test eltype.(eachcol(DataFrame(gd))) == [Union{Missing, Symbol}, Int]

        gd2 = gd[[3,2]]
        @test DataFrame(gd2) == df[[3,5,2,4], :]

        gd = groupby_checked(df, :A, skipmissing=true)
        @test sort(DataFrame(gd), :B) ==
              sort(dropmissing(df, disallowmissing=false), :B)
        @test eltype.(eachcol(DataFrame(gd))) == [Union{Missing, Symbol}, Int]

        gd2 = gd[[2,1]]
        @test DataFrame(gd2) == df[[3,5,2,4], :]

        @test_throws ArgumentError DataFrame!(gd)
        @test_throws ArgumentError DataFrame(gd, copycols=false)
    end

    df = DataFrame(a=Int[], b=[], c=Union{Missing, String}[])
    gd = groupby_checked(df, :a)
    @test size(DataFrame(gd)) == size(df)
    @test eltype.(eachcol(DataFrame(gd))) == [Int, Any, Union{Missing, String}]

    dfv = view(dfx, 1:0, :)
    gd = groupby_checked(dfv, :A)
    @test size(DataFrame(gd)) == size(dfv)
    @test eltype.(eachcol(DataFrame(gd))) == [Union{Missing, Symbol}, Int]
end

@testset "groupindices, groupcols, and valuecols" begin
    df = DataFrame(A = [missing, :A, :B, :A, :B, missing], B = 1:6)
    gd = groupby_checked(df, :A)
    @inferred groupindices(gd)
    @test groupindices(gd) == [1, 2, 3, 2, 3, 1]
    @test groupcols(gd) == [:A]
    @test valuecols(gd) == [:B]
    gd2 = gd[[3,2]]
    @inferred groupindices(gd2)
    @test groupindices(gd2) ≅ [missing, 2, 1, 2, 1, missing]
    @test groupcols(gd2) == [:A]
    @test valuecols(gd2) == [:B]

    gd = groupby_checked(df, :A, skipmissing=true)
    @inferred groupindices(gd)
    @test groupindices(gd) ≅ [missing, 1, 2, 1, 2, missing]
    @test groupcols(gd) == [:A]
    @test valuecols(gd) == [:B]
    gd2 = gd[[2,1]]
    @inferred groupindices(gd2)
    @test groupindices(gd2) ≅ [missing, 2, 1, 2, 1, missing]
    @test groupcols(gd2) == [:A]
    @test valuecols(gd2) == [:B]

    df2 = DataFrame(A = vcat(df.A, df.A), B = repeat([:X, :Y], inner=6), C = 1:12)

    gd = groupby_checked(df2, [:A, :B])
    @inferred groupindices(gd)
    @test groupindices(gd) == [1, 2, 3, 2, 3, 1, 4, 5, 6, 5, 6, 4]
    @test groupcols(gd) == [:A, :B]
    @test valuecols(gd) == [:C]
    gd2 = gd[[3,2,5]]
    @inferred groupindices(gd2)
    @test groupindices(gd2) ≅ [missing, 2, 1, 2, 1, missing, missing, 3, missing, 3, missing, missing]
    @test groupcols(gd2) == [:A, :B]
    @test valuecols(gd) == [:C]

    gd = groupby_checked(df2, [:A, :B], skipmissing=true)
    @inferred groupindices(gd)
    @test groupindices(gd) ≅ [missing, 1, 2, 1, 2, missing, missing, 3, 4, 3, 4, missing]
    @test groupcols(gd) == [:A, :B]
    @test valuecols(gd) == [:C]
    gd2 = gd[[4,2,1]]
    @inferred groupindices(gd2)
    @test groupindices(gd2) ≅ [missing, 3, 2, 3, 2, missing, missing, missing, 1, missing, 1, missing]
    @test groupcols(gd2) == [:A, :B]
    @test valuecols(gd) == [:C]
end

@testset "by skipmissing and sort" begin
    df = DataFrame(a=[2, 2, missing, missing, 1, 1, 3, 3], b=1:8)
    for dosort in (false, true), doskipmissing in (false, true)
        @test by(df, :a, :b=>sum, sort=dosort, skipmissing=doskipmissing) ≅
            combine(groupby(df, :a, sort=dosort, skipmissing=doskipmissing), :b=>sum)
    end
end

@testset "non standard cols arguments" begin
    df = DataFrame(x1=Int64[1,2,2], x2=Int64[1,1,2], y=Int64[1,2,3])
    gdf = groupby_checked(df, r"x")
    @test groupcols(gdf) == [:x1, :x2]
    @test valuecols(gdf) == [:y]
    @test groupindices(gdf) == [1,2,3]

    gdf = groupby_checked(df, Not(r"x"))
    @test groupcols(gdf) == [:y]
    @test valuecols(gdf) == [:x1, :x2]
    @test groupindices(gdf) == [1,2,3]

    gdf = groupby_checked(df, [])
    @test groupcols(gdf) == []
    @test valuecols(gdf) == [:x1, :x2, :y]
    @test groupindices(gdf) == [1,1,1]

    gdf = groupby_checked(df, r"z")
    @test groupcols(gdf) == []
    @test valuecols(gdf) == [:x1, :x2, :y]
    @test groupindices(gdf) == [1,1,1]

    @test by(df, [], :x1 => sum => :a, :x2=>length => :b) == DataFrame(a=5, b=3)

    gdf = groupby_checked(df, [])
    @test gdf[1] == df
    @test_throws BoundsError gdf[2]
    @test gdf[:] == gdf
    @test gdf[1:1] == gdf

    @test map(nrow => :x1, gdf) == groupby_checked(DataFrame(x1=3), [])
    @test map(:x2 => identity => :x2_identity, gdf) ==
          groupby_checked(DataFrame(x2_identity=[1,1,2]), [])
    @test aggregate(df, sum) == aggregate(df, [], sum) == aggregate(df, 1:0, sum)
    @test aggregate(df, sum) == aggregate(df, [], sum, sort=true, skipmissing=true)
    @test DataFrame(gdf) == df

    @test sprint(show, groupby_checked(df, [])) == "GroupedDataFrame with 1 group based on key: \n" *
        "Group 1 (3 rows): \n│ Row │ x1    │ x2    │ y     │\n│     │ Int64 │ Int64 │ Int64 │\n" *
        "├─────┼───────┼───────┼───────┤\n│ 1   │ 1     │ 1     │ 1     │\n" *
        "│ 2   │ 2     │ 1     │ 2     │\n│ 3   │ 2     │ 2     │ 3     │"

    df = DataFrame(a=[1, 1, 2, 2, 2], b=1:5)
    gd = groupby(df, :a)
    @test_throws ArgumentError combine(gd)
end

@testset "GroupedDataFrame dictionary interface" begin
    df = DataFrame(a = repeat([:A, :B, missing], outer=4), b = repeat(1:2, inner=6), c = 1:12)
    gd = groupby_checked(df, [:a, :b])

    @test map(NamedTuple, keys(gd)) ≅
        [(a=:A, b=1), (a=:B, b=1), (a=missing, b=1), (a=:A, b=2), (a=:B, b=2), (a=missing, b=2)]

    @test collect(pairs(gd)) ≅ map(Pair, keys(gd), gd)

    for (i, key) in enumerate(keys(gd))
        # Plain key
        @test gd[key] ≅ gd[i]
        # Named tuple
        @test gd[NamedTuple(key)] ≅ gd[i]
        # Plain tuple
        @test gd[Tuple(key)] ≅ gd[i]
    end

    # Equivalent value of different type
    @test gd[(a=:A, b=1.0)] ≅ gd[1]

    @test get(gd, (a=:A, b=1), nothing) ≅ gd[1]
    @test get(gd, (a=:A, b=3), nothing) == nothing

    # Wrong values
    @test_throws KeyError gd[(a=:A, b=3)]
    @test_throws KeyError gd[(:A, 3)]
    @test_throws KeyError gd[(a=:A, b="1")]
    # Wrong length
    @test_throws KeyError gd[(a=:A,)]
    @test_throws KeyError gd[(:A,)]
    @test_throws KeyError gd[(a=:A, b=1, c=1)]
    @test_throws KeyError gd[(:A, 1, 1)]
    # Out of order
    @test_throws KeyError gd[(b=1, a=:A)]
    @test_throws KeyError gd[(1, :A)]
    # Empty
    @test_throws KeyError gd[()]
    @test_throws KeyError gd[NamedTuple()]
end

@testset "GroupKey and GroupKeys" begin
    df = DataFrame(a = repeat([:A, :B, missing], outer=4), b = repeat([:X, :Y], inner=6), c = 1:12)
    cols = [:a, :b]
    colstup = Tuple(cols)
    gd = groupby_checked(df, cols)
    gdkeys = keys(gd)

    expected =
        [(a=:A, b=:X), (a=:B, b=:X), (a=missing, b=:X), (a=:A, b=:Y), (a=:B, b=:Y), (a=missing, b=:Y)]

    # Check AbstractVector behavior
    @test IndexStyle(gdkeys) === IndexLinear()
    @test length(gdkeys) == length(expected)
    @test size(gdkeys) == size(expected)
    @test eltype(gdkeys) == DataFrames.GroupKey{typeof(gd)}
    @test_throws BoundsError gdkeys[0]
    @test_throws BoundsError gdkeys[length(gdkeys) + 1]

    # Test each key
    cnt = 0
    for (i, key) in enumerate(gdkeys)
        cnt += 1
        nt = expected[i]

        # Check iteration vs indexing of GroupKeys
        @test key == gdkeys[i]

        # Basic methods
        @test parent(key) === gd
        @test length(key) == length(cols)
        @test names(key) == cols
        @test keys(key) == colstup
        @test propertynames(key) == colstup
        @test propertynames(key, true) == colstup
        @test values(key) ≅ values(nt)

        # (Named)Tuple conversion
        @test Tuple(key) ≅ values(nt)
        @test NamedTuple(key) ≅ nt

        # Iteration
        @test collect(key) ≅ collect(nt)

        # Integer/symbol indexing, getproperty of key
        for (j, n) in enumerate(cols)
            @test key[j] ≅ nt[j]
            @test key[n] ≅ nt[j]
            @test getproperty(key, n) ≅ nt[j]
        end

        # Out-of-bounds integer index
        @test_throws BoundsError key[0]
        @test_throws BoundsError key[length(key) + 1]

        # Invalid key/property of key
        @test_throws KeyError key[:foo]
        @test_throws ArgumentError key.foo

        # Using key to index GroupedDataFrame
        @test gd[key] ≅ gd[i]
    end

    # Make sure we actually iterated over all of them
    @test cnt == length(gd)

    # Indexing using another GroupedDataFrame instance should fail
    gd2 = groupby(df, cols, skipmissing=true)
    gd3 = groupby(df, cols, skipmissing=true)
    @test gd2 == gd3  # Use GDF's without missing so they compare equal
    @test_throws ErrorException gd3[first(keys(gd2))]

    # Key equality
    @test collect(keys(gd)) == gdkeys  # These are new instances
    @test all(Ref(gdkeys[1]) .!= gdkeys[2:end])  # Keys should not be equal to each other
    @test !any(collect(keys(gd2)) .== keys(gd3))  # Same values but different (but equal) parent

    # Printing of GroupKey
    df = DataFrame(a = repeat([:foo, :bar, :baz], outer=[4]),
                   b = repeat(1:2, outer=[6]),
                   c = 1:12)

    gd = groupby(df, [:a, :b])

    @test map(repr, keys(gd)) == [
        "GroupKey: (a = :foo, b = 1)",
        "GroupKey: (a = :bar, b = 2)",
        "GroupKey: (a = :baz, b = 1)",
        "GroupKey: (a = :foo, b = 2)",
        "GroupKey: (a = :bar, b = 1)",
        "GroupKey: (a = :baz, b = 2)",
    ]
end

@testset "GroupedDataFrame indexing with array of keys" begin
    df_ref = DataFrame(a = repeat([:A, :B, missing], outer=4),
                       b = repeat(1:2, inner=6), c = 1:12)
    Random.seed!(1234)
    for df in [df_ref, df_ref[randperm(nrow(df_ref)), :]], grpcols = [[:a, :b], :a, :b],
        dosort in [true, false], doskipmissing in [true, false]

        gd = groupby_checked(df, grpcols, sort=dosort, skipmissing=doskipmissing)

        ints = unique(min.(length(gd), [4, 6, 2, 1]))
        gd2 = gd[ints]
        gkeys = keys(gd)[ints]

        # Test with GroupKeys, Tuples, and NamedTuples
        for converter in [identity, Tuple, NamedTuple]
            a = converter.(gkeys)
            @test gd[a] ≅ gd2

            # Infer eltype
            @test gd[Array{Any}(a)] ≅ gd2

            # Duplicate keys
            a2 = converter.(keys(gd)[[1, 2, 1]])
            @test_throws ArgumentError gd[a2]
        end
    end
end

@testset "InvertedIndex with GroupedDataFrame" begin
    df = DataFrame(a = repeat([:A, :B, missing], outer=4),
                   b = repeat(1:2, inner=6), c = 1:12)
    gd = groupby_checked(df, [:a, :b])

    # Inverted scalar index
    skip_i = 3
    skip_key = keys(gd)[skip_i]
    expected = gd[[i != skip_i for i in 1:length(gd)]]
    expected_inv = gd[[skip_i]]

    for skip in [skip_i, skip_key, Tuple(skip_key), NamedTuple(skip_key)]
        @test gd[Not(skip)] ≅ expected
        # Nested
        @test gd[Not(Not(skip))] ≅ expected_inv
    end

    @test_throws ArgumentError gd[Not(true)]  # Bool <: Integer, but should fail

    # Inverted array index
    skipped = [3, 5, 2]
    skipped_bool = [i ∈ skipped for i in 1:length(gd)]
    skipped_keys = keys(gd)[skipped]
    expected2 = gd[.!skipped_bool]
    expected2_inv = gd[skipped_bool]

    for skip in [skipped, skipped_keys, Tuple.(skipped_keys), NamedTuple.(skipped_keys)]
        @test gd[Not(skip)] ≅ expected2
        # Infer eltype
        @test gd[Not(Array{Any}(skip))] ≅ expected2
        # Nested
        @test gd[Not(Not(skip))] ≅ expected2_inv
        @test gd[Not(Not(Array{Any}(skip)))] ≅ expected2_inv
    end

    # Mixed integer arrays
    @test gd[Not(Any[Unsigned(skipped[1]), skipped[2:end]...])] ≅ expected2
    @test_throws ArgumentError gd[Not(Any[2, true])]

    # Boolean array
    @test gd[Not(skipped_bool)] ≅ expected2
    @test gd[Not(Not(skipped_bool))] ≅ expected2_inv
    @test gd[1:2][Not(false:true)] ≅ gd[[1]]  # Not{AbstractArray{Bool}}

    # Inverted colon
    @test gd[Not(:)] ≅ gd[Int[]]
    @test gd[Not(Not(:))] ≅ gd
end

@testset "GroupedDataFrame array index homogeneity" begin
    df = DataFrame(a = repeat([:A, :B, missing], outer=4),
                   b = repeat(1:2, inner=6), c = 1:12)
    gd = groupby_checked(df, [:a, :b])

    # All scalar index types
    idxsets = [1:length(gd), keys(gd), Tuple.(keys(gd)), NamedTuple.(keys(gd))]

    # Mixing index types should fail
    for (i, idxset1) in enumerate(idxsets)
        idx1 = idxset1[1]
        for (j, idxset2) in enumerate(idxsets)
            i == j && continue

            idx2 = idxset2[2]

            # With Any eltype
            a = Any[idx1, idx2]
            @test_throws ArgumentError gd[a]
            @test_throws ArgumentError gd[Not(a)]

            # Most specific applicable eltype, which is <: GroupKeyTypes
            T = Union{typeof(idx1), typeof(idx2)}
            a2 = T[idx1, idx2]
            @test_throws ArgumentError gd[a2]
            @test_throws ArgumentError gd[Not(a2)]
        end
    end
end

@testset "Parent DataFrame names changed" begin
    df = DataFrame(a = repeat([:A, :B, missing], outer=4), b = repeat([:X, :Y], inner=6), c = 1:12)
    gd = groupby_checked(df, [:a, :b])

    @test names(gd) == names(df)
    @test groupcols(gd) == [:a, :b]
    @test valuecols(gd) == [:c]
    @test map(NamedTuple, keys(gd)) ≅
        [(a=:A, b=:X), (a=:B, b=:X), (a=missing, b=:X), (a=:A, b=:Y), (a=:B, b=:Y), (a=missing, b=:Y)]
    @test gd[(a=:A, b=:X)] ≅ gd[1]
    @test gd[keys(gd)[1]] ≅ gd[1]
    @test NamedTuple(keys(gd)[1]) == (a=:A, b=:X)
    @test keys(gd)[1].a == :A

    rename!(df, [:d, :e, :f])

    @test names(gd) == names(df)
    @test groupcols(gd) == [:d, :e]
    @test valuecols(gd) == [:f]
    @test map(NamedTuple, keys(gd)) ≅
        [(d=:A, e=:X), (d=:B, e=:X), (d=missing, e=:X), (d=:A, e=:Y), (d=:B, e=:Y), (d=missing, e=:Y)]
    @test gd[(d=:A, e=:X)] ≅ gd[1]
    @test gd[keys(gd)[1]] ≅ gd[1]
    @test NamedTuple(keys(gd)[1]) == (d=:A, e=:X)
    @test keys(gd)[1].d == :A
    @test_throws KeyError gd[(a=:A, b=:X)]
end

@testset "haskey for GroupKey" begin
    gdf = groupby(DataFrame(a=1, b=2, c=3), [:a, :b])
    k = keys(gdf)[1]
    @test !haskey(k, 0)
    @test haskey(k, 1)
    @test haskey(k, 2)
    @test !haskey(k, 3)
    @test haskey(k, :a)
    @test haskey(k, :b)
    @test !haskey(k, :c)
    @test !haskey(k, :d)

    @test !haskey(gdf, 0)
    @test haskey(gdf, 1)
    @test !haskey(gdf, 2)
    @test_throws MethodError haskey(gdf, true)

    @test haskey(gdf, k)
    @test_throws ArgumentError haskey(gdf, keys(groupby(DataFrame(a=1,b=2,c=3), [:a, :b]))[1])
    @test_throws BoundsError haskey(gdf, DataFrames.GroupKey(gdf, 0))
    @test_throws BoundsError haskey(gdf, DataFrames.GroupKey(gdf, 2))
    @test haskey(gdf, (1,2))
    @test !haskey(gdf, (1,3))
    @test_throws ArgumentError haskey(gdf, (1,2,3))
    @test haskey(gdf, (a=1,b=2))
    @test !haskey(gdf, (a=1,b=3))
    @test_throws ArgumentError haskey(gdf, (a=1,c=3))
    @test_throws ArgumentError haskey(gdf, (a=1,c=2))
    @test_throws ArgumentError haskey(gdf, (a=1,b=2,c=3))
end

@testset "Check aggregation of DataFrameRow" begin
    df = DataFrame(a=1)
    dfr = DataFrame(x=1, y="1")[1, 2:2]
    @test by(sdf -> dfr, df, :a) == DataFrame(a=1, y="1")

    df = DataFrame(a=[1,1,2,2,3,3], b='a':'f', c=string.(1:6))
    @test by(sdf -> sdf[1, [3,2,1]], df, :a) == df[1:2:5, [1,3,2]]
end

@testset "Allow returning DataFrame() or NamedTuple() to drop group" begin
    N = 4
    for (i, x1) in enumerate(collect.(Iterators.product(repeat([[true, false]], N)...))),
        er in (DataFrame(), view(DataFrame(ones(2,2)), 2:1, 2:1),
               view(DataFrame(ones(2,2)), 1:2, 2:1),
               NamedTuple(), rand(0,0), rand(5,0),
               DataFrame(x1=Int[]), DataFrame(x1=Any[]),
               (x1=Int[],), (x1=Any[],), rand(0,1)),
        fr in (DataFrame(x1=[true]), (x1=[true],))

        df = DataFrame(a = 1:N, x1 = x1)
        res = by(sdf -> sdf.x1[1] ? fr : er, df, :a)
        @test res == DataFrame(map(sdf -> sdf.x1[1] ? fr : er, groupby_checked(df, :a)))
        if fr isa AbstractVector && df.x1[1]
            @test res == by(:x1 => (x1 -> x1[1] ? fr : er) => :x1, df, :a)
        else
            @test res == by(:x1 => x1 -> x1[1] ? fr : er, df, :a)
        end
        if nrow(res) == 0 && length(propertynames(er)) == 0 && er != rand(0, 1)
            @test res == DataFrame(a=[])
            @test typeof(res.a) == Vector{Int}
        else
            @test res == df[df.x1, :]
        end
        if 1 < i < 2^N
            @test_throws ArgumentError by(sdf -> sdf.x1[1] ? (x1=true,) : er, df, :a)
            if df.x1[1] || !(fr isa AbstractVector)
                @test_throws ArgumentError by(sdf -> sdf.x1[1] ? fr : (x2=[true],), df, :a)
            else
                res = by(sdf -> sdf.x1[1] ? fr : (x2=[true],), df, :a)
                @test names(res) == [:a, :x2]
            end
            @test_throws ArgumentError by(sdf -> sdf.x1[1] ? true : er, df, :a)
        end
    end
end

@testset "auto-splatting, ByRow, and column renaming" begin
    df = DataFrame(g=[1,1,1,2,2,2], x1=1:6, x2=1:6)
    @test by(df, :g, r"x" => cor) == DataFrame(g=[1,2], x1_x2_cor = [1.0, 1.0])
    @test by(df, :g, Not(:g) => ByRow(/)) == DataFrame(:g => [1,1,1,2,2,2], Symbol("x1_x2_/") => 1.0)
    @test by(df, :g, Between(:x2, :x1) => () -> 1) == DataFrame(:g => 1:2, Symbol("function") => 1)
    @test by(df, :g, :x1 => :z) ==
          by(df, :g, [:x1 => :z]) ==
          by(:x1 => :z, df, :g) ==
          combine(groupby(df, :g), :x1 => :z) ==
          combine(groupby(df, :g), [:x1 => :z]) ==
          combine(:x1 => :z, groupby(df, :g)) ==
          DataFrame(g=[1,1,1,2,2,2], z=1:6)
    @test map(:x1 => :z, groupby(df, :g)) == groupby(DataFrame(g=[1,1,1,2,2,2], z=1:6), :g)
end

@testset "hard tabular return value cases" begin
    Random.seed!(1)
    df = DataFrame(b = repeat([2, 1], outer=[4]), x = randn(8))
    res = by(sdf -> sdf.x[1:2], df, :b)
    @test names(res) == [:b, :x1]
    res2 = by(:x => x -> x[1:2], df, :b)
    @test names(res2) == [:b, :x_function]
    @test Matrix(res) == Matrix(res2)
    res2 = by(:x => (x -> x[1:2]) => :z, df, :b)
    @test names(res2) == [:b, :z]
    @test Matrix(res) == Matrix(res2)

    @test_throws ArgumentError by(df, :b) do sdf
        if sdf.b[1] == 2
            return (c=sdf.x[1:2],)
        else
            return sdf.x[1:2]
        end
    end
    @test_throws ArgumentError by(df, :b) do sdf
        if sdf.b[1] == 1
            return (c=sdf.x[1:2],)
        else
            return sdf.x[1:2]
        end
    end
    @test_throws ArgumentError by(df, :b) do sdf
        if sdf.b[1] == 2
            return (c=sdf.x[1],)
        else
            return sdf.x[1]
        end
    end
    @test_throws ArgumentError by(df, :b) do sdf
        if sdf.b[1] == 1
            return (c=sdf.x[1],)
        else
            return sdf.x[1]
        end
    end

    for i in 1:2, v1 in [1, 1:2], v2 in [1, 1:2]
        @test_throws ArgumentError by([:b, :x] => ((b,x) -> b[1] == i ? x[v1] : (c=x[v2],)) => :v, df, :b)
        @test_throws ArgumentError by([:b, :x] => ((b,x) -> b[1] == i ? x[v1] : (v=x[v2],)) => :v, df, :b)
    end
end

@testset "last Pair interface with multiple return values" begin
    df = DataFrame(g=[1,1,1,2,2,2], x1=1:6)
    @test by(df, :g, :x1 => x -> DataFrame()) == by(:x1 => x -> DataFrame(), df, :g)
    @test by(df, :g, :x1 => x -> (x=1, y=2)) == by(:x1 => x -> (x=1, y=2), df, :g)
    @test by(df, :g, :x1 => x -> (x=[1], y=[2])) == by(:x1 => x -> (x=[1], y=[2]), df, :g)
    @test_throws ArgumentError by(df, :g, :x1 => x -> (x=[1],y=2))
    @test_throws ArgumentError by(:x1 => x -> (x=[1], y=2), df, :g)
    @test by(df, :g, :x1 => x -> ones(2, 2)) == by(:x1 => x -> ones(2, 2), df, :g)
    @test by(df, :g, :x1 => x -> df[1, Not(:g)]) == by(:x1 => x -> df[1, Not(:g)], df, :g)
end

@testset "keepkeys" begin
    df = DataFrame(g=[1,1,1,2,2,2], x1=1:6)
    @test by(df, :g, :x1 => identity, keepkeys=false) == DataFrame(x1_identity=1:6)
    @test by(x -> DataFrame(g=x.x1), df, :g, keepkeys=false) == DataFrame(g=1:6)
    gdf = groupby_checked(df, :g)
    @test combine(gdf, :x1 => identity => :g, keepkeys=false) == DataFrame(g=1:6)
    @test combine(x -> (z=x.x1,), gdf, keepkeys=false) == DataFrame(z=1:6)
end

@testset "additional do_call tests" begin
    Random.seed!(1234)
    df = DataFrame(g = rand(1:10, 100), x1 = rand(1:1000, 100))
    gdf = groupby(df, :g)

    @test combine(gdf, [] => () -> 1, :x1 => length) == combine(gdf) do sdf
        (;[:function => 1, :x1_length => nrow(sdf)]...)
    end
    @test combine(gdf, [] => () -> 1) == combine(gdf) do sdf
        (;:function => 1)
    end
    for i in 1:5
        @test combine(gdf, fill(:x1, i) => ((x...) -> sum(+(x...))) => :res, :x1 => length) ==
              combine(gdf) do sdf
                  (;[:res => i*sum(sdf.x1), :x1_length => nrow(sdf)]...)
              end
        @test combine(gdf, fill(:x1, i) => ((x...) -> sum(+(x...))) => :res) ==
              combine(gdf) do sdf
                  (;:res => i*sum(sdf.x1))
              end
    end
end

end # module
