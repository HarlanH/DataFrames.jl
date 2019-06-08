module TestBroadcasting

using Test, DataFrames, PooledArrays

const ≅ = isequal

refdf = DataFrame(reshape(1.5:15.5, (3,5)))

@testset "broadcasting of AbstractDataFrame objects" begin
    for df in (copy(refdf), view(copy(refdf), :, :))
        @test identity.(df) == refdf
        @test (x->x).(df) == refdf
        @test (df .+ df) ./ 2 == refdf
        @test df .+ Matrix(df) == 2 .* df
        @test Matrix(df) .+ df == 2 .* df
        @test (Matrix(df) .+ df .== 2 .* df) == DataFrame(trues(size(df)), names(df))
        @test df .+ 1 == df .+ ones(size(df))
        @test df .+ axes(df, 1) == DataFrame(Matrix(df) .+ axes(df, 1), names(df))
        @test df .+ permutedims(axes(df, 2)) == DataFrame(Matrix(df) .+ permutedims(axes(df, 2)), names(df))
    end
end

@testset "broadcasting of AbstractDataFrame objects errors" begin
    df = copy(refdf)
    dfv = view(df, :, 2:ncol(df))

    @test_throws DimensionMismatch df .+ dfv
    @test_throws DimensionMismatch df .+ df[2:end, :]

    @test_throws DimensionMismatch df .+ [1, 2]
    @test_throws DimensionMismatch df .+ [1 2]
    @test_throws DimensionMismatch df .+ rand(2,2)
    @test_throws DimensionMismatch dfv .+ [1, 2]
    @test_throws DimensionMismatch dfv .+ [1 2]
    @test_throws DimensionMismatch dfv .+ rand(2,2)

    df2 = copy(df)
    names!(df2, [:x1, :x2, :x3, :x4, :y])
    @test_throws ArgumentError df .+ df2
    @test_throws ArgumentError df .+ 1 .+ df2
end

@testset "broadcasting of AbstractDataFrame objects corner cases" begin
    df = DataFrame(c11 = categorical(["a", "b"]), c12 = categorical([missing, "b"]), c13 = categorical(["a", missing]),
                   c21 = categorical([1, 2]), c22 = categorical([missing, 2]), c23 = categorical([1, missing]),
                   p11 = PooledArray(["a", "b"]), p12 = PooledArray([missing, "b"]), p13 = PooledArray(["a", missing]),
                   p21 = PooledArray([1, 2]), p22 = PooledArray([missing, 2]), p23 = PooledArray([1, missing]),
                   b1 = [true, false], b2 = [missing, false], b3 = [true, missing],
                   f1 = [1.0, 2.0], f2 = [missing, 2.0], f3 = [1.0, missing],
                   s1 = ["a", "b"], s2 = [missing, "b"], s3 = ["a", missing])

    df2 = DataFrame(c11 = categorical(["a", "b"]), c12 = [nothing, "b"], c13 = ["a", nothing],
                    c21 = categorical([1, 2]), c22 = [nothing, 2], c23 = [1, nothing],
                    p11 = ["a", "b"], p12 = [nothing, "b"], p13 = ["a", nothing],
                    p21 = [1, 2], p22 = [nothing, 2], p23 = [1, nothing],
                    b1 = [true, false], b2 = [nothing, false], b3 = [true, nothing],
                    f1 = [1.0, 2.0], f2 = [nothing, 2.0], f3 = [1.0, nothing],
                    s1 = ["a", "b"], s2 = [nothing, "b"], s3 = ["a", nothing])

    @test df ≅ identity.(df)
    @test df ≅ (x->x).(df)
    df3 = coalesce.(df, nothing)
    @test df2 == df3
    @test eltypes(df2) == eltypes(df3)
    for i in axes(df, 2)
        @test typeof(df2[i]) == typeof(df3[i])
    end
    df4 = (x -> df[1,1]).(df)
    @test names(df4) == names(df)
    @test all(isa.(eachcol(df4), CategoricalArray))
    @test all(eachcol(df4) .== Ref(categorical(["a", "a"])))

    df5 = DataFrame(x = Any[1, 2, 3], y = Any[1, 2.0, big(3)])
    @test identity.(df5) == df5
    @test (x->x).(df5) == df5
    @test df5 .+ 1 == DataFrame(Matrix(df5) .+ 1, names(df5))
    @test eltypes(identity.(df5)) == [Int, BigFloat]
    @test eltypes((x->x).(df5)) == [Int, BigFloat]
    @test eltypes(df5 .+ 1) == [Int, BigFloat]
end

@testset "normal data frame and data frame row in broadcasted assignment - one column" begin
    df = copy(refdf)
    df[1] .+= 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[1] .+= 1
    @test dfv.x2 == [5.5, 6.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         3.5  6.5  8.5  11.5  14.5
                         4.5  6.5  9.5  12.5  15.5]

    dfr = df[1, 3:end]
    dfr[end-1:end] .= 10
    @test Vector(dfr) == [7.5, 10.0, 10.0]
    @test Matrix(df) == [2.5  5.5  7.5  10.0  10.0
                         3.5  6.5  8.5  11.5  14.5
                         4.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, 1] .+= 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:, 1] .+= 1
    @test dfv.x2 == [5.5, 6.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         3.5  6.5  8.5  11.5  14.5
                         4.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[1] .+= [1, 2, 3]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[1] .+= [1, 2]
    @test dfv.x2 == [5.5, 7.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    dfr = df[1, 3:end]
    dfr[end-1:end] .= [10, 11]
    @test Vector(dfr) == [7.5, 10.0, 11.0]
    @test Matrix(df) == [2.5  5.5  7.5  10.0  11.0
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, 1] .+= [1, 2, 3]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:, 1] .+= [1, 2]
    @test dfv.x2 == [5.5, 7.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    # test a more complex broadcasting pattern
    df = copy(refdf)
    df[1] .+= [0, 1, 2] .+ 1
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[1] .+= [0, 1] .+ 1
    @test dfv.x2 == [5.5, 7.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    dfr = df[1, 3:end]
    dfr[end-1:end] .= [9, 10] .+ 1
    @test Vector(dfr) == [7.5, 10.0, 11.0]
    @test Matrix(df) == [2.5  5.5  7.5  10.0  11.0
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, 1] .+= [0, 1, 2] .+ 1
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:, 1] .+= [0, 1] .+ 1
    @test dfv.x2 == [5.5, 7.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    dfv = @view df[1:2, 2:end]
    dfr = df[1, 3:end]
    @test_throws DimensionMismatch df[1] .= rand(3, 1)
    @test_throws DimensionMismatch dfv[1] .= rand(2, 1)
    @test_throws DimensionMismatch dfr[end-1:end] .= rand(3, 1)
    @test_throws DimensionMismatch df[:, 1] .= rand(3, 1)
    @test_throws DimensionMismatch dfv[:, 1] .= rand(2, 1)
    @test_throws DimensionMismatch df[1] .= reshape(rand(3), :, 1)
    @test_throws DimensionMismatch dfv[1] .= reshape(rand(2), :, 1)
    @test_throws DimensionMismatch dfr[end-1:end] .= reshape(rand(3), :, 1)
    @test_throws DimensionMismatch df[:, 1] .= reshape(rand(3), :, 1)
    @test_throws DimensionMismatch dfv[:, 1] .= reshape(rand(2), :, 1)

    df = copy(refdf)
    df[:x1] .+= 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:x2] .+= 1
    @test dfv.x2 == [5.5, 6.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         3.5  6.5  8.5  11.5  14.5
                         4.5  6.5  9.5  12.5  15.5]

    dfr = df[1, 3:end]
    dfr[[:x4, :x5]] .= 10
    @test Vector(dfr) == [7.5, 10.0, 10.0]
    @test Matrix(df) == [2.5  5.5  7.5  10.0  10.0
                         3.5  6.5  8.5  11.5  14.5
                         4.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, :x1] .+= 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:, :x2] .+= 1
    @test dfv.x2 == [5.5, 6.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         3.5  6.5  8.5  11.5  14.5
                         4.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:x1] .+= [1, 2, 3]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:x2] .+= [1, 2]
    @test dfv.x2 == [5.5, 7.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    dfr = df[1, 3:end]
    dfr[[:x4, :x5]] .= [10, 11]
    @test Vector(dfr) == [7.5, 10.0, 11.0]
    @test Matrix(df) == [2.5  5.5  7.5  10.0  11.0
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, :x1] .+= [1, 2, 3]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df[2:end] == refdf[2:end]

    dfv = @view df[1:2, 2:end]
    dfv[:, :x2] .+= [1, 2]
    @test dfv.x2 == [5.5, 7.5]
    @test dfv[2:end] == refdf[1:2, 3:end]
    @test Matrix(df) == [2.5  5.5  7.5  10.5  13.5
                         4.5  7.5  8.5  11.5  14.5
                         6.5  6.5  9.5  12.5  15.5]

    df = copy(refdf)
    dfv = @view df[1:2, 2:end]
    dfr = df[1, 3:end]
    @test_throws DimensionMismatch df[:x1] .= rand(3, 1)
    @test_throws DimensionMismatch dfv[:x2] .= rand(2, 1)
    @test_throws DimensionMismatch dfr[[:x4, :x5]] .= rand(3, 1)
    @test_throws DimensionMismatch df[:, :x1] .= rand(3, 1)
    @test_throws DimensionMismatch dfv[:, :x2] .= rand(2, 1)
    @test_throws DimensionMismatch df[1] .= reshape(rand(3), :, 1)
    @test_throws DimensionMismatch dfv[1] .= reshape(rand(2), :, 1)
    @test_throws DimensionMismatch dfr[end-1:end] .= reshape(rand(3), :, 1)
    @test_throws DimensionMismatch df[:, 1] .= reshape(rand(3), :, 1)
    @test_throws DimensionMismatch dfv[:, 1] .= reshape(rand(2), :, 1)
end

@testset "normal data frame and data frame view in broadcasted assignment - two columns" begin
    df = copy(refdf)
    df[[1,2]] .= Matrix(df[[1,2]]) .+ 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df.x2 == [5.5, 6.5, 7.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[[1,2]] .= Matrix(dfv[[1,2]]) .+ 1
    @test dfv.x3 == [8.5, 9.5]
    @test dfv.x4 == [11.5, 12.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5  5.5  8.5  11.5  13.5
                         3.5  6.5  9.5  12.5  14.5
                         4.5  7.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, [1,2]] .= Matrix(df[[1,2]]) .+ 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df.x2 == [5.5, 6.5, 7.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[:, [1,2]] .= Matrix(dfv[[1,2]]) .+ 1
    @test dfv.x3 == [8.5, 9.5]
    @test dfv.x4 == [11.5, 12.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5  5.5  8.5  11.5  13.5
                         3.5  6.5  9.5  12.5  14.5
                         4.5  7.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[[1,2]] .= Matrix(df[[1,2]]) .+ [1 4
                                       2 5
                                       3 6]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df.x2 == [8.5, 10.5, 12.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[[1,2]] .= Matrix(dfv[[1,2]]) .+ [1 3
                                         2 4]
    @test dfv.x3 == [8.5, 10.5]
    @test dfv.x4 == [13.5, 15.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5   8.5   8.5  13.5  13.5
                         4.5  10.5  10.5  15.5  14.5
                         6.5  12.5   9.5  12.5  15.5]

    df = copy(refdf)
    df[:, [1,2]] .= Matrix(df[[1,2]]) .+ [1 4
                                          2 5
                                          3 6]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df.x2 == [8.5, 10.5, 12.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[:, [1,2]] .= Matrix(dfv[[1,2]]) .+ [1 3
                                            2 4]
    @test dfv.x3 == [8.5, 10.5]
    @test dfv.x4 == [13.5, 15.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5   8.5   8.5  13.5  13.5
                         4.5  10.5  10.5  15.5  14.5
                         6.5  12.5   9.5  12.5  15.5]

    df = copy(refdf)
    dfv = @view df[1:2, 2:end]
    @test_throws DimensionMismatch df[[1,2]] .= rand(3, 10)
    @test_throws DimensionMismatch dfv[[1,2]] .= rand(2, 10)
    @test_throws DimensionMismatch df[:, [1,2]] .= rand(3, 10)
    @test_throws DimensionMismatch dfv[:, [1,2]] .= rand(2, 10)

    df = copy(refdf)
    df[[:x1,:x2]] .= Matrix(df[[:x1,:x2]]) .+ 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df.x2 == [5.5, 6.5, 7.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[[:x3,:x4]] .= Matrix(dfv[[:x3,:x4]]) .+ 1
    @test dfv.x3 == [8.5, 9.5]
    @test dfv.x4 == [11.5, 12.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5  5.5  8.5  11.5  13.5
                         3.5  6.5  9.5  12.5  14.5
                         4.5  7.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[:, [:x1,:x2]] .= Matrix(df[[:x1,:x2]]) .+ 1
    @test df.x1 == [2.5, 3.5, 4.5]
    @test df.x2 == [5.5, 6.5, 7.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[:, [:x3,:x4]] .= Matrix(dfv[[:x3,:x4]]) .+ 1
    @test dfv.x3 == [8.5, 9.5]
    @test dfv.x4 == [11.5, 12.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5  5.5  8.5  11.5  13.5
                         3.5  6.5  9.5  12.5  14.5
                         4.5  7.5  9.5  12.5  15.5]

    df = copy(refdf)
    df[[:x1,:x2]] .= Matrix(df[[:x1,:x2]]) .+ [1 4
                                               2 5
                                               3 6]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df.x2 == [8.5, 10.5, 12.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[[:x3,:x4]] .= Matrix(dfv[[:x3,:x4]]) .+ [1 3
                                                 2 4]
    @test dfv.x3 == [8.5, 10.5]
    @test dfv.x4 == [13.5, 15.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5   8.5   8.5  13.5  13.5
                         4.5  10.5  10.5  15.5  14.5
                         6.5  12.5   9.5  12.5  15.5]

    df = copy(refdf)
    df[:, [:x1,:x2]] .= Matrix(df[[:x1,:x2]]) .+ [1 4
                                                  2 5
                                                  3 6]
    @test df.x1 == [2.5, 4.5, 6.5]
    @test df.x2 == [8.5, 10.5, 12.5]
    @test df[3:end] == refdf[3:end]

    dfv = @view df[1:2, 3:end]
    dfv[:, [:x3,:x4]] .= Matrix(dfv[[:x3,:x4]]) .+ [1 3
                                                    2 4]
    @test dfv.x3 == [8.5, 10.5]
    @test dfv.x4 == [13.5, 15.5]
    @test dfv[3:end] == refdf[1:2, 5:end]
    @test Matrix(df) == [2.5   8.5   8.5  13.5  13.5
                         4.5  10.5  10.5  15.5  14.5
                         6.5  12.5   9.5  12.5  15.5]

    df = copy(refdf)
    dfv = @view df[1:2, 2:end]
    @test_throws DimensionMismatch df[[:x1,:x2]] .= rand(3, 10)
    @test_throws DimensionMismatch dfv[[:x3,:x4]] .= rand(2, 10)
    @test_throws DimensionMismatch df[:, [:x1,:x2]] .= rand(3, 10)
    @test_throws DimensionMismatch dfv[:, [:x3,:x4]] .= rand(2, 10)

    df = copy(refdf)
    df[[1,2]] .= [1 2
                  3 4
                  5 6]
    @test Matrix(df) == [1.0  2.0  7.5  10.5  13.5
                         3.0  4.0  8.5  11.5  14.5
                         5.0  6.0  9.5  12.5  15.5]

    df = copy(refdf)
    df[[1,2]] .= [1, 3, 5]
    @test Matrix(df) == [1.0  1.0  7.5  10.5  13.5
                         3.0  3.0  8.5  11.5  14.5
                         5.0  5.0  9.5  12.5  15.5]

    df = copy(refdf)
    df[[1,2]] .= reshape([1, 3, 5], 3, 1)
    @test Matrix(df) == [1.0  1.0  7.5  10.5  13.5
                         3.0  3.0  8.5  11.5  14.5
                         5.0  5.0  9.5  12.5  15.5]

    df = copy(refdf)
    df[[1,2]] .= 1
    @test Matrix(df) == [1.0  1.0  7.5  10.5  13.5
                         1.0  1.0  8.5  11.5  14.5
                         1.0  1.0  9.5  12.5  15.5]

    df = copy(refdf)
    dfv = view(df, 2:3, 2:4)
    dfv[[1,2]] .= [1 2
                   3 4]
    @test Matrix(df) == [1.5  4.5  7.5  10.5  13.5
                         2.5  1.0  2.0  11.5  14.5
                         3.5  3.0  4.0  12.5  15.5]

    df = copy(refdf)
    dfv = view(df, 2:3, 2:4)
    dfv[[1,2]] .= [1, 3]
    @test Matrix(df) == [1.5  4.5  7.5  10.5  13.5
                         2.5  1.0  1.0  11.5  14.5
                         3.5  3.0  3.0  12.5  15.5]

    df = copy(refdf)
    dfv = view(df, 2:3, 2:4)
    dfv[[1,2]] .= reshape([1, 3], 2, 1)
    @test Matrix(df) == [1.5  4.5  7.5  10.5  13.5
                         2.5  1.0  1.0  11.5  14.5
                         3.5  3.0  3.0  12.5  15.5]

    df = copy(refdf)
    dfv = view(df, 2:3, 2:4)
    dfv[[1,2]] .= 1
    @test Matrix(df) == [1.5  4.5  7.5  10.5  13.5
                         2.5  1.0  1.0  11.5  14.5
                         3.5  1.0  1.0  12.5  15.5]
end

@testset "assignment to a whole data frame and data frame row" begin
    df = copy(refdf)
    df .= 10
    @test all(Matrix(df) .== 10)
    dfv = view(df, 1:2, 1:4)
    dfv .= 100
    @test Matrix(df) == [100.0  100.0  100.0  100.0  10.0
                        100.0  100.0  100.0  100.0  10.0
                         10.0   10.0   10.0   10.0  10.0]
    dfr = df[1, 1:2]
    dfr .= 1000
    @test Matrix(df) == [1000.0  1000.0  100.0  100.0  10.0
                         100.0   100.0  100.0  100.0  10.0
                          10.0    10.0   10.0   10.0  10.0]

    df = copy(refdf)
    df[:] .= 10
    @test all(Matrix(df) .== 10)
    dfv = view(df, 1:2, 1:4)
    dfv[:] .= 100
    @test Matrix(df) == [100.0  100.0  100.0  100.0  10.0
                        100.0  100.0  100.0  100.0  10.0
                         10.0   10.0   10.0   10.0  10.0]
    dfr = df[1, 1:2]
    dfr[:] .= 1000
    @test Matrix(df) == [1000.0  1000.0  100.0  100.0  10.0
                         100.0   100.0  100.0  100.0  10.0
                          10.0    10.0   10.0   10.0  10.0]

    df = copy(refdf)
    df[:,:] .= 10
    @test all(Matrix(df) .== 10)
    dfv = view(df, 1:2, 1:4)
    dfv[:, :] .= 100
    @test Matrix(df) == [100.0  100.0  100.0  100.0  10.0
                        100.0  100.0  100.0  100.0  10.0
                         10.0   10.0   10.0   10.0  10.0]
end

@testset "extending data frame in broadcasted assignment - one column" begin
    df = copy(refdf)
    df[:a] .= 1
    @test Matrix(df) == [1.5  4.5  7.5  10.5  13.5  1.0
                         2.5  5.5  8.5  11.5  14.5  1.0
                         3.5  6.5  9.5  12.5  15.5  1.0]
    @test names(df)[end] == :a
    @test df[1:end-1] == refdf
    df[:b] .= [1, 2, 3]
    @test Matrix(df) == [1.5  4.5  7.5  10.5  13.5  1.0 1.0
                         2.5  5.5  8.5  11.5  14.5  1.0 2.0
                         3.5  6.5  9.5  12.5  15.5  1.0 3.0]
    @test names(df)[end] == :b
    @test df[1:end-2] == refdf
    cdf = copy(df)
    @test_throws DimensionMismatch df[:c] .= ones(3, 1)
    @test df == cdf
    @test_throws DimensionMismatch df[:x] .= ones(4)
    @test df == cdf
    @test_throws BoundsError df[10] .= ones(3)
    @test df == cdf

    dfv = @view df[1:2, 2:end]
    @test_throws BoundsError dfv[10] .= ones(3)
    @test_throws ArgumentError dfv[:z] .= ones(3)
    @test df == cdf
    dfr = df[1, 3:end]
    @test_throws BoundsError dfr[10] .= ones(3)
    @test_throws ArgumentError dfr[:z] .= ones(3)
    @test df == cdf
end

@testset "empty data frame corner case" begin
    df = DataFrame()
    @test_throws ArgumentError df[1] .= 1
    @test_throws ArgumentError df[:a] .= [1]
    @test_throws ArgumentError df[[:a,:b]] .= [1]
    @test df == DataFrame()
    df .= 1
    @test df == DataFrame()
    df .= [1]
    @test df == DataFrame()
    df .= ones(1,1)
    @test df == DataFrame()
    @test_throws DimensionMismatch df .= ones(1,2)
    @test_throws DimensionMismatch df .= ones(1,1,1)

    @test_throws ArgumentError df[:a] .= 1
    @test_throws ArgumentError df[[:a, :b]] .= 1

    df = DataFrame(a=[])
    @test_throws ArgumentError df[:b] .= 1
end

@testset "test categorical values" begin
    for v in [categorical([1,2,3]), categorical([1,2, missing]),
              categorical([missing, 1,2]),
              categorical(["1","2","3"]), categorical(["1","2", missing]),
              categorical([missing, "1","2"])]
        df = copy(refdf)
        df[:c1] .= v
        @test df.c1 ≅ v
        @test df.c1 !== v
        @test df.c1 isa CategoricalVector
        @test levels(df.c1) == levels(v)
        @test levels(df.c1) !== levels(v)
        df[:c2] .= v[2]
        @test df.c2 == get.([v[2], v[2], v[2]])
        @test df.c2 isa CategoricalVector
        @test levels(df.c2) != levels(v)
        df[:c3] .= (x->x).(v)
        @test df.c3 ≅ v
        @test df.c3 !== v
        @test df.c3 isa CategoricalVector
        @test levels(df.c3) == levels(v)
        @test levels(df.c3) !== levels(v)
        df[:c4] .= identity.(v)
        @test df.c4 ≅ v
        @test df.c4 !== v
        @test df.c4 isa CategoricalVector
        @test levels(df.c4) == levels(v)
        @test levels(df.c4) !== levels(v)
        df[:c5] .= (x->v[2]).(v)
        @test unique(df.c5) == [get(v[2])]
        @test df.c5 isa CategoricalVector
        @test length(levels(df.c5)) == 1
    end
end

end # module
