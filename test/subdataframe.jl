module TestSubDataFrame
    using Test, DataFrames

    @testset "copy - SubDataFrame" begin
        df = DataFrame(x = 1:10, y = 1.0:10.0)
        sdf = view(df, 1:2, 1:1)
        @test sdf isa SubDataFrame
        @test copy(sdf) isa DataFrame
        @test sdf == copy(sdf)
    end

    @testset "view -- DataFrame" begin
        df = DataFrame(x = 1:10, y = 1.0:10.0)
        @test view(df, 1, :) == first(df, 1)
        @test view(df, UInt(1), :) == first(df, 1)
        @test view(df, BigInt(1), :) == first(df, 1)
        @test view(df, 1:2, :) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), :) == first(df, 2)
        @test view(df, [1, 2], :) == first(df, 2)
        @test view(df, 1, :x) == first(df[[:x]], 1)
        @test view(df, 1:2, :x) == first(df[[:x]], 2)
        @test view(df, vcat(trues(2), falses(8)), :x) == first(df[[:x]], 2)
        @test view(df, [1, 2], :x) == first(df[[:x]], 2)
        @test view(df, 1, 1) == first(df[[:x]], 1)
        @test view(df, 1:2, 1) == first(df[[:x]], 2)
        @test view(df, vcat(trues(2), falses(8)), 1) == first(df[[:x]], 2)
        @test view(df, [1, 2], 1) == first(df[[:x]], 2)
        @test view(df, 1, [:x, :y]) == first(df, 1)
        @test view(df, 1:2, [:x, :y]) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), [:x, :y]) == first(df, 2)
        @test view(df, [1, 2], [:x, :y]) == first(df, 2)
        @test view(df, 1, [1, 2]) == first(df, 1)
        @test view(df, 1:2, [1, 2]) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), [1, 2]) == first(df, 2)
        @test view(df, [1, 2], [1, 2]) == first(df, 2)
        @test view(df, 1, trues(2)) == first(df, 1)
        @test view(df, 1:2, trues(2)) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), trues(2)) == first(df, 2)
        @test view(df, [1, 2], trues(2)) == first(df, 2)
        @test view(df, Integer[1, 2], :) == first(df, 2)
        @test view(df, UInt[1, 2], :) == first(df, 2)
        @test view(df, BigInt[1, 2], :) == first(df, 2)
        @test view(df, Union{Int, Missing}[1, 2], :) == first(df, 2)
        @test view(df, Union{Integer, Missing}[1, 2], :) == first(df, 2)
        @test view(df, Union{UInt, Missing}[1, 2], :) == first(df, 2)
        @test view(df, Union{BigInt, Missing}[1, 2], :) == first(df, 2)
        @test view(df, :) == df
        @test view(df, :, :) == df
        @test view(df, 1, :) == first(df, 1)
        @test view(df, :, 1) == df[:, [1]]
        @test_throws ArgumentError view(df, [missing, 1])
        @test_throws ArgumentError view(df, [missing, 1], :)
    end

    @testset "view -- SubDataFrame" begin
        df = view(DataFrame(x = 1:10, y = 1.0:10.0), 1:10)
        @test view(df, 1, :) == first(df, 1)
        @test view(df, UInt(1), :) == first(df, 1)
        @test view(df, BigInt(1), :) == first(df, 1)
        @test view(df, 1:2, :) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), :) == first(df, 2)
        @test view(df, [1, 2], :) == first(df, 2)
        @test view(df, 1, :x) == first(df[[:x]], 1)
        @test view(df, 1:2, :x) == first(df[[:x]], 2)
        @test view(df, vcat(trues(2), falses(8)), :x) == first(df[[:x]], 2)
        @test view(df, [1, 2], :x) == first(df[[:x]], 2)
        @test view(df, 1, 1) == first(df[[:x]], 1)
        @test view(df, 1:2, 1) == first(df[[:x]], 2)
        @test view(df, vcat(trues(2), falses(8)), 1) == first(df[[:x]], 2)
        @test view(df, [1, 2], 1) == first(df[[:x]], 2)
        @test view(df, 1, [:x, :y]) == first(df, 1)
        @test view(df, 1:2, [:x, :y]) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), [:x, :y]) == first(df, 2)
        @test view(df, [1, 2], [:x, :y]) == first(df, 2)
        @test view(df, 1, [1, 2]) == first(df, 1)
        @test view(df, 1:2, [1, 2]) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), [1, 2]) == first(df, 2)
        @test view(df, [1, 2], [1, 2]) == first(df, 2)
        @test view(df, 1, trues(2)) == first(df, 1)
        @test view(df, 1:2, trues(2)) == first(df, 2)
        @test view(df, vcat(trues(2), falses(8)), trues(2)) == first(df, 2)
        @test view(df, [1, 2], trues(2)) == first(df, 2)
        @test view(df, Integer[1, 2], :) == first(df, 2)
        @test view(df, UInt[1, 2], :) == first(df, 2)
        @test view(df, BigInt[1, 2], :) == first(df, 2)
        @test view(df, Union{Int, Missing}[1, 2], :) == first(df, 2)
        @test view(df, Union{Integer, Missing}[1, 2], :) == first(df, 2)
        @test view(df, Union{UInt, Missing}[1, 2], :) == first(df, 2)
        @test view(df, Union{BigInt, Missing}[1, 2], :) == first(df, 2)
        @test view(df, :) == df
        @test view(df, :, :) == df
        @test view(df, 1, :) == first(df, 1)
        @test view(df, :, 1) == df[:, [1]]
        @test_throws ArgumentError view(df, [missing, 1])
        @test_throws ArgumentError view(df, [missing, 1], :)
    end

    @testset "getproperty, setproperty! and propertynames" begin
        x = 1:10
        y = 1.0:10.0
        df = view(DataFrame(x = x, y = y), 2:6, :)

        @test Base.propertynames(df) == names(df)

        @test df.x == 2:6
        @test df.y == 2:6
        @test_throws KeyError df.z

        df.x = 1:5
        @test df.x == 1:5
        @test x == [1; 1:5; 7:10]
        df.y = 1
        @test df.y == [1, 1, 1, 1, 1]
        @test y == [1; 1; 1; 1; 1; 1; 7:10]
        @test_throws ErrorException df.z = 1:5
        @test_throws ErrorException df.z = 1
    end

    @testset "dump" begin
        y = 1.0:10.0
        df = view(DataFrame(y = y), 2:6, :)
        @test sprint(dump, df) == """
                                  SubDataFrame{UnitRange{$Int}}  5 observations of 1 variables
                                    y: Array{Float64}((5,)) [2.0, 3.0, 4.0, 5.0, 6.0]
                                  """
    end

    @testset "deleterows!" begin
        y = 1.0:10.0
        df = view(DataFrame(y = y), 2:6, :)
        @test_throws ArgumentError deleterows!(df, 1)
    end
end
