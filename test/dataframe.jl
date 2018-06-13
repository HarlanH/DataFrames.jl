module TestDataFrame
    using Compat, Compat.Test, Compat.Dates, DataFrames
    using DataFrames: columns
    const ≅ = isequal
    const ≇ = !isequal

    #
    # Equality
    #

    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) == DataFrame(a=[1, 2, 3], b=[4, 5, 6])
    @test DataFrame(a=[1, 2], b=[4, 5]) != DataFrame(a=[1, 2, 3], b=[4, 5, 6])
    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) != DataFrame(a=[1, 2, 3])
    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) != DataFrame(a=[1, 2, 3], c=[4, 5, 6])
    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) != DataFrame(b=[4, 5, 6], a=[1, 2, 3])
    @test DataFrame(a=[1, 2, 2], b=[4, 5, 6]) != DataFrame(a=[1, 2, 3], b=[4, 5, 6])
    @test DataFrame(a=[1, 2, missing], b=[4, 5, 6]) ≅
                  DataFrame(a=[1, 2, missing], b=[4, 5, 6])

    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) == DataFrame(a=[1, 2, 3], b=[4, 5, 6])
    @test DataFrame(a=[1, 2], b=[4, 5]) != DataFrame(a=[1, 2, 3], b=[4, 5, 6])
    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) != DataFrame(a=[1, 2, 3])
    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) != DataFrame(a=[1, 2, 3], c=[4, 5, 6])
    @test DataFrame(a=[1, 2, 3], b=[4, 5, 6]) != DataFrame(b=[4, 5, 6], a=[1, 2, 3])
    @test DataFrame(a=[1, 2, 2], b=[4, 5, 6]) != DataFrame(a=[1, 2, 3], b=[4, 5, 6])
    @test DataFrame(a=[1, 3, missing], b=[4, 5, 6]) !=
             DataFrame(a=[1, 2, missing], b=[4, 5, 6])
    @test DataFrame(a=[1, 2, missing], b=[4, 5, 6]) ≅
                DataFrame(a=[1, 2, missing], b=[4, 5, 6])
    @test DataFrame(a=[1, 2, missing], b=[4, 5, 6]) ≇
                DataFrame(a=[1, 2, 3], b=[4, 5, 6])

    #
    # Copying
    #

    df = DataFrame(a = Union{Int, Missing}[2, 3],
                   b = Union{DataFrame, Missing}[DataFrame(c = 1), DataFrame(d = 2)])
    dfc = copy(df)
    dfdc = deepcopy(df)

    df[1, :a] = 4
    df[1, :b][:e] = 5
    names!(df, [:f, :g])

    @test names(dfc) == [:a, :b]
    @test names(dfdc) == [:a, :b]

    @test dfc[1, :a] === 4
    @test dfdc[1, :a] === 2

    @test names(dfc[1, :b]) == [:c, :e]
    @test names(dfdc[1, :b]) == [:c]

    x = DataFrame(a = [1, 2, 3], b = [4, 5, 6])

    #test_group("DataFrame assignment")
    # Insert single column
    x0 = x[Int[], :]
    @test_throws ArgumentError x0[:d] = [1]
    @test_throws ArgumentError x0[:d] = 1:3

    # Insert single value
    x[:d] = 3
    @test x[:d] == [3, 3, 3]

    x0[:d] = 3
    @test x0[:d] == Int[]

    # similar / missings
    df = DataFrame(a = Union{Int, Missing}[1],
                   b = Union{String, Missing}["b"],
                   c = CategoricalArray{Union{Float64, Missing}}([3.3]))
    missingdf = DataFrame(a = missings(Int, 2),
                          b = missings(String, 2),
                          c = CategoricalArray{Union{Float64, Missing}}(undef, 2))
    # https://github.com/JuliaData/Missings.jl/issues/66
    # @test missingdf ≅ similar(df, 2)
    @test typeof.(columns(similar(df, 2))) == typeof.(columns(missingdf))
    @test size(similar(df, 2)) == size(missingdf)

    # Associative methods

    df = DataFrame(a=[1, 2], b=[3.0, 4.0])
    @test haskey(df, :a)
    @test !haskey(df, :c)
    @test get(df, :a, -1) === columns(df)[1]
    @test get(df, :c, -1) == -1
    @test !isempty(df)

    @test empty!(df) === df
    @test isempty(columns(df))
    @test isempty(df)
    @test isempty(DataFrame(a=[], b=[]))

    df = DataFrame(a=Union{Int, Missing}[1, 2], b=Union{Float64, Missing}[3.0, 4.0])
    @test_throws BoundsError insert!(df, 5, ["a", "b"], :newcol)
    @test_throws ErrorException insert!(df, 1, ["a"], :newcol)
    @test insert!(df, 1, ["a", "b"], :newcol) == df
    @test names(df) == [:newcol, :a, :b]
    @test df[:a] == [1, 2]
    @test df[:b] == [3.0, 4.0]
    @test df[:newcol] == ["a", "b"]

    @test insert!(df, 1, ["a1", "b1"], :newcol, makeunique=true) == df
    @test names(df) == [:newcol_1, :newcol, :a, :b]
    @test df[:a] == [1, 2]
    @test df[:b] == [3.0, 4.0]
    @test df[:newcol] == ["a", "b"]
    @test df[:newcol_1] == ["a1", "b1"]

    df = DataFrame(a=[1,2], a_1=[3,4])
    @static if VERSION >= v"0.7.0-DEV.2988"
        @test_logs (:warn, r"Inserting") insert!(df, 1, [11,12], :a)
    else
        @test_warn r"Inserting" insert!(df, 1, [11,12], :a)
    end
    df = DataFrame(a=[1,2], a_1=[3,4])
    insert!(df, 1, [11,12], :a, makeunique=true)
    @test names(df) == [:a_2, :a, :a_1]
    insert!(df, 4, [11,12], :a, makeunique=true)
    @test names(df) == [:a_2, :a, :a_1, :a_3]
    @test_throws BoundsError insert!(df, 10, [11,12], :a, makeunique=true)
    df = DataFrame(a=[1,2], a_1=[3,4])
    insert!(df, 1, 11, :a, makeunique=true)
    @test names(df) == [:a_2, :a, :a_1]
    insert!(df, 4, 11, :a, makeunique=true)
    @test names(df) == [:a_2, :a, :a_1, :a_3]
    @test_throws BoundsError insert!(df, 10, 11, :a, makeunique=true)

    df = DataFrame(a=[1, 2], b=[3.0, 4.0])
    df2 = DataFrame(b=["a", "b"], c=[:c, :d])
    @test merge!(df, df2) == df
    @test df == DataFrame(a=[1, 2], b=["a", "b"], c=[:c, :d])

    #test_group("Empty DataFrame constructors")
    df = DataFrame(Union{Int, Missing}, 10, 3)
    @test size(df, 1) == 10
    @test size(df, 2) == 3
    @test typeof(df[:, 1]) == Vector{Union{Int, Missing}}
    @test typeof(df[:, 2]) == Vector{Union{Int, Missing}}
    @test typeof(df[:, 3]) == Vector{Union{Int, Missing}}
    @test all(ismissing, df[:, 1])
    @test all(ismissing, df[:, 2])
    @test all(ismissing, df[:, 3])

    df = DataFrame([Union{Int, Missing}, Union{Float64, Missing}, Union{String, Missing}], 100)
    @test size(df, 1) == 100
    @test size(df, 2) == 3
    @test typeof(df[:, 1]) == Vector{Union{Int, Missing}}
    @test typeof(df[:, 2]) == Vector{Union{Float64, Missing}}
    @test typeof(df[:, 3]) == Vector{Union{String, Missing}}
    @test all(ismissing, df[:, 1])
    @test all(ismissing, df[:, 2])
    @test all(ismissing, df[:, 3])

    df = DataFrame([Union{Int, Missing}, Union{Float64, Missing}, Union{String, Missing}],
                   [:A, :B, :C], 100)
    @test size(df, 1) == 100
    @test size(df, 2) == 3
    @test typeof(df[:, 1]) == Vector{Union{Int, Missing}}
    @test typeof(df[:, 2]) == Vector{Union{Float64, Missing}}
    @test typeof(df[:, 3]) == Vector{Union{String, Missing}}
    @test all(ismissing, df[:, 1])
    @test all(ismissing, df[:, 2])
    @test all(ismissing, df[:, 3])

    df = DataFrame([Union{Int, Missing}, Union{Float64, Missing}, Union{String, Missing}],
                   [:A, :B, :C], [false, false, true], 100)
    @test size(df, 1) == 100
    @test size(df, 2) == 3
    @test typeof(df[:, 1]) == Vector{Union{Int, Missing}}
    @test typeof(df[:, 2]) == Vector{Union{Float64, Missing}}
    @test typeof(df[:, 3]) <: CategoricalVector{Union{String, Missing}}
    @test all(ismissing, df[:, 1])
    @test all(ismissing, df[:, 2])
    @test all(ismissing, df[:, 3])

    df = convert(DataFrame, zeros(10, 5))
    @test size(df, 1) == 10
    @test size(df, 2) == 5
    @test typeof(df[:, 1]) == Vector{Float64}

    df = convert(DataFrame, ones(10, 5))
    @test size(df, 1) == 10
    @test size(df, 2) == 5
    @test typeof(df[:, 1]) == Vector{Float64}

    df = convert(DataFrame, eye(10, 5))
    @test size(df, 1) == 10
    @test size(df, 2) == 5
    @test typeof(df[:, 1]) == Vector{Float64}

    @test DataFrame([Union{Int, Missing}[1, 2, 3], Union{Float64, Missing}[2.5, 4.5, 6.5]],
                    [:A, :B]) ==
        DataFrame(A = Union{Int, Missing}[1, 2, 3], B = Union{Float64, Missing}[2.5, 4.5, 6.5])

    # This assignment was missing before
    df = DataFrame(Column = [:A])
    df[1, :Column] = "Testing"

    # zero-row DataFrame and subDataFrame test
    df = DataFrame(x=[], y=[])
    @test nrow(df) == 0
    df = DataFrame(x=[1:3;], y=[3:5;])
    sdf = view(df, df[:x] .== 4)
    @test size(sdf, 1) == 0

    @test hash(convert(DataFrame, [1 2; 3 4])) == hash(convert(DataFrame, [1 2; 3 4]))
    @test hash(convert(DataFrame, [1 2; 3 4])) != hash(convert(DataFrame, [1 3; 2 4]))
    @test hash(convert(DataFrame, [1 2; 3 4])) == hash(convert(DataFrame, [1 2; 3 4]), zero(UInt))

    @testset "push!(df, row)" begin
        df=DataFrame( first=[1,2,3], second=["apple","orange","pear"] )

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        dfc= DataFrame( first=[1,2], second=["apple","orange"] )
        push!(dfb, Any[3,"pear"])
        @test df == dfb

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        push!(dfb, (3,"pear"))
        @test df == dfb

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        @test_throws ArgumentError push!(dfb, (33.33,"pear"))
        @test dfc == dfb

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        @test_throws ArgumentError push!(dfb, (1,"2",3))
        @test dfc == dfb

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        @test_throws ArgumentError push!(dfb, ("coconut",22))
        @test dfc == dfb

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        @test_throws ArgumentError push!(dfb, (11,22))
        @test dfc == dfb

        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        push!(dfb, Dict(:first=>3, :second=>"pear"))
        @test df == dfb

        df=DataFrame( first=[1,2,3], second=["apple","orange","banana"] )
        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        push!(dfb, Dict(:first=>3, :second=>"banana"))
        @test df == dfb

        df0= DataFrame( first=[1,2], second=["apple","orange"] )
        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        @test_throws ArgumentError push!(dfb, Dict(:first=>true, :second=>false))
        @test df0 == dfb

        df0= DataFrame( first=[1,2], second=["apple","orange"] )
        dfb= DataFrame( first=[1,2], second=["apple","orange"] )
        @test_throws ArgumentError push!(dfb, Dict(:first=>"chicken", :second=>"stuff"))
        @test df0 == dfb

        df0=DataFrame( first=[1,2,3], second=["apple","orange","pear"] )
        dfb=DataFrame( first=[1,2,3], second=["apple","orange","pear"] )
        @test_throws ArgumentError push!(dfb, Dict(:first=>"chicken", :second=>1))
        @test df0 == dfb

        df0=DataFrame( first=["1","2","3"], second=["apple","orange","pear"] )
        dfb=DataFrame( first=["1","2","3"], second=["apple","orange","pear"] )
        @test_throws ArgumentError push!(dfb, Dict(:first=>"chicken", :second=>1))
        @test df0 == dfb

        df = DataFrame(x=1)
        push!(df, Dict(:x=>2), Dict(:x=>3))
        @test df[:x] == [1,2,3]
    
        df = DataFrame(x=1, y=2)
        push!(df, [3, 4], [5, 6])
        @test df[:x] == [1, 3, 5] && df[:y] == [2, 4, 6]
    end

    # delete!
    df = DataFrame(a=1, b=2, c=3, d=4, e=5)
    @test_throws ArgumentError delete!(df, 0)
    @test_throws ArgumentError delete!(df, 6)
    @test_throws KeyError delete!(df, :f)

    d = copy(df)
    delete!(d, [:a, :e, :c])
    @test names(d) == [:b, :d]
    delete!(d, :b)
    @test d == DataFrame(d=4)

    d = copy(df)
    delete!(d, [2, 5, 3])
    @test names(d) == [:a, :d]
    delete!(d, 2)
    @test d == DataFrame(a=1)

    # deleterows!
    df = DataFrame(a=[1, 2], b=[3.0, 4.0])
    @test deleterows!(df, 1) === df
    @test df == DataFrame(a=[2], b=[4.0])

    df = DataFrame(a=[1, 2], b=[3.0, 4.0])
    @test deleterows!(df, 2) === df
    @test df == DataFrame(a=[1], b=[3.0])

    df = DataFrame(a=[1, 2, 3], b=[3.0, 4.0, 5.0])
    @test deleterows!(df, 2:3) === df
    @test df == DataFrame(a=[1], b=[3.0])

    df = DataFrame(a=[1, 2, 3], b=[3.0, 4.0, 5.0])
    @test deleterows!(df, [2, 3]) === df
    @test df == DataFrame(a=[1], b=[3.0])

    df = DataFrame(a=Union{Int, Missing}[1, 2], b=Union{Float64, Missing}[3.0, 4.0])
    @test deleterows!(df, 1) === df
    @test df == DataFrame(a=[2], b=[4.0])

    df = DataFrame(a=Union{Int, Missing}[1, 2], b=Union{Float64, Missing}[3.0, 4.0])
    @test deleterows!(df, 2) === df
    @test df == DataFrame(a=[1], b=[3.0])

    df = DataFrame(a=Union{Int, Missing}[1, 2, 3], b=Union{Float64, Missing}[3.0, 4.0, 5.0])
    @test deleterows!(df, 2:3) === df
    @test df == DataFrame(a=[1], b=[3.0])

    df = DataFrame(a=Union{Int, Missing}[1, 2, 3], b=Union{Float64, Missing}[3.0, 4.0, 5.0])
    @test deleterows!(df, [2, 3]) === df
    @test df == DataFrame(a=[1], b=[3.0])
    
    # Test describe
    @testset "describe(df)" begin
        # Construct the test dataframe
        df = DataFrame(number = [1, 2, 3, 4],
                       number_missing = [1,2, 3, missing],
                       string = ["a", "b", "c", "d"],
                       string_missing = ["a", "b", "c", missing],
                       dates  = Date.([2000, 2001, 2003, 2004]),
                       catarray = CategoricalArray([1,2,1,2]))

        describe_output = DataFrame(variable = [:number, :number_missing, :string, 
                                                :string_missing, :dates, :catarray],
                                    mean = [2.5, 2.0, nothing, nothing, nothing, nothing],
                                    min = [1.0, 1.0, "a", "a", Date(2000), nothing],
                                    median = [2.5, 2.0, nothing, nothing, nothing, nothing],
                                    max = [4.0, 3.0, "d", "c", Date(2004), nothing],
                                    nunique = [nothing, nothing, 4, 3, 4, 2],
                                    nmissing = [nothing, 1, nothing, 1, nothing, nothing],
                                    eltype = [Int, Int, String, String, Date, eltype(df[:catarray])])
        describe_output_all_stats = DataFrame(variable = [:number, :number_missing, 
                                                          :string, :string_missing,
                                                          :dates, :catarray],
                                              mean = [2.5, 2.0, nothing, nothing, nothing, nothing],
                                              std = [Compat.std(df[:number]), 1.0, nothing, 
                                                     nothing, nothing, nothing],
                                              min = [1.0, 1.0, "a", "a", Date(2000), nothing],
                                              q25 = [1.75, 1.5, nothing, nothing, nothing, nothing],
                                              median = [2.5, 2.0, nothing, nothing, nothing, nothing],
                                              q75 = [3.25, 2.5, nothing, nothing, nothing, nothing],
                                              max = [4.0, 3.0, "d", "c", Date(2004), nothing],
                                              nunique = [nothing, nothing, 4, 3, 4, 2],
                                              nmissing = [nothing, 1, nothing, 1, nothing, nothing],
                                              first = [1, 1, "a", "a", Date(2000), 1],
                                              last = [4, missing, "d", missing, Date(2004), 2],
                                              eltype = [Int, Int, String, String, Date, 
                                                        eltype(df[:catarray])])

        
        # Test that it works as a whole, without keyword arguments
        @test describe_output == describe(df)

        # Test that it works with one stats argument
        @test describe_output[[:variable, :mean]] == describe(df, stats = [:mean])

        # Test that it works with all keyword arguments
        # Use isqual because we have `missing`s in this dataframe
        @test describe_output_all_stats ≅ describe(df, stats = [:all])
    end 

    #Check the output of unstack
    df = DataFrame(Fish = CategoricalArray{Union{String, Missing}}(["Bob", "Bob", "Batman", "Batman"]),
                   Key = CategoricalArray{Union{String, Missing}}(["Mass", "Color", "Mass", "Color"]),
                   Value = Union{String, Missing}["12 g", "Red", "18 g", "Grey"])
    # Check that reordering levels does not confuse unstack
    levels!(df[1], ["XXX", "Bob", "Batman"])
    levels!(df[2], ["YYY", "Color", "Mass"])
    #Unstack specifying a row column
    df2 = unstack(df, :Fish, :Key, :Value)
    @test levels(df[1]) == ["XXX", "Bob", "Batman"] # make sure we did not mess df[1] levels
    @test levels(df[2]) == ["YYY", "Color", "Mass"] # make sure we did not mess df[2] levels
    #Unstack without specifying a row column
    df3 = unstack(df, :Key, :Value)
    #The expected output, XXX level should be dropped as it has no rows with this key
    df4 = DataFrame(Fish = Union{String, Missing}["Bob", "Batman"],
                    Color = Union{String, Missing}["Red", "Grey"],
                    Mass = Union{String, Missing}["12 g", "18 g"])
    @test df2 ≅ df4
    @test typeof(df2[:Fish]) <: CategoricalVector{Union{String, Missing}}
    # first column stays as CategoricalArray in df3
    @test df3 == df4
    #Make sure unstack works with missing values at the start of the value column
    df[1,:Value] = missing
    df2 = unstack(df, :Fish, :Key, :Value)
    #This changes the expected result
    df4[1,:Mass] = missing
    @test df2 ≅ df4

    #The same as above but without CategoricalArray
    df = DataFrame(Fish = ["Bob", "Bob", "Batman", "Batman"],
                   Key = ["Mass", "Color", "Mass", "Color"],
                   Value = ["12 g", "Red", "18 g", "Grey"])
    #Unstack specifying a row column
    df2 = unstack(df, :Fish, :Key, :Value)
    #Unstack without specifying a row column
    df3 = unstack(df, :Key, :Value)
    #The expected output, XXX level should be dropped as it has no rows with this key
    df4 = DataFrame(Fish = ["Batman", "Bob"],
                    Color = ["Grey", "Red"],
                    Mass = ["18 g", "12 g"])
    @test df2 ≅ df4
    @test typeof(df2[:Fish]) <: Vector{String}
    # first column stays as CategoricalArray in df3
    @test df3 == df4
    #Make sure unstack works with missing values at the start of the value column
    allowmissing!(df, :Value)
    df[1,:Value] = missing
    df2 = unstack(df, :Fish, :Key, :Value)
    #This changes the expected result
    allowmissing!(df4, :Mass)
    df4[2,:Mass] = missing
    @test df2 ≅ df4

    # test empty set of grouping variables
    @test_throws ArgumentError unstack(df, Int[], :Key, :Value)
    @test_throws ArgumentError unstack(df, Symbol[], :Key, :Value)
    @test_throws KeyError unstack(stack(DataFrame(rand(10, 10))))

    # test missing value in grouping variable
    mdf = DataFrame(id=[missing,1,2,3], a=1:4, b=1:4)
    @test unstack(melt(mdf, :id))[1:3,:] == sort(mdf)[1:3,:]
    @test unstack(melt(mdf, :id))[:,2:3] == sort(mdf)[:,2:3]

    # test more than one grouping column
    wide = DataFrame(id = 1:12,
                     a  = repeat([1:3;], inner = [4]),
                     b  = repeat([1:4;], inner = [3]),
                     c  = randn(12),
                     d  = randn(12))

    long = stack(wide)
    wide3 = unstack(long, [:id, :a], :variable, :value)
    @test wide3 == wide[:, [1, 2, 4, 5]]

    df = DataFrame(A = 1:10, B = 'A':'J')
    @test !(df[:,:] === df)

    @test append!(DataFrame(A = 1:2, B = 1:2), DataFrame(A = 3:4, B = 3:4)) == DataFrame(A=1:4, B = 1:4)
    df = DataFrame(A = Vector{Union{Int, Missing}}(1:3), B = Vector{Union{Int, Missing}}(4:6))
    DRT = CategoricalArrays.DefaultRefType
    @test all(c -> isa(c, Vector{Union{Int, Missing}}), columns(categorical!(deepcopy(df))))
    @test all(c -> typeof(c) <: CategoricalVector{Union{Int, Missing}},
              columns(categorical!(deepcopy(df), [1,2])))
    @test all(c -> typeof(c) <: CategoricalVector{Union{Int, Missing}},
              columns(categorical!(deepcopy(df), [:A,:B])))
    @test findfirst(c -> typeof(c) <: CategoricalVector{Union{Int, Missing}},
                    columns(categorical!(deepcopy(df), [:A]))) == 1
    @test findfirst(c -> typeof(c) <: CategoricalVector{Union{Int, Missing}},
                    columns(categorical!(deepcopy(df), :A))) == 1
    @test findfirst(c -> typeof(c) <: CategoricalVector{Union{Int, Missing}},
                    columns(categorical!(deepcopy(df), [1]))) == 1
    @test findfirst(c -> typeof(c) <: CategoricalVector{Union{Int, Missing}},
                    columns(categorical!(deepcopy(df), 1))) == 1

    @testset "categorical!" begin
        df = DataFrame([["a", "b"], ['a', 'b'], [true, false], 1:2, ["x", "y"]])
        @test all(map(<:, eltypes(categorical!(df)),
                      [CategoricalArrays.CategoricalString,
                       Char, Bool, Int,
                       CategoricalArrays.CategoricalString]))
        @test all(map(<:, eltypes(categorical!(df, names(df))),
                      [CategoricalArrays.CategoricalString,
                       CategoricalArrays.CategoricalValue{Char},
                       CategoricalArrays.CategoricalValue{Bool},
                       CategoricalArrays.CategoricalValue{Int},
                       CategoricalArrays.CategoricalString]))
    end

    @testset "unstack promotion to support missing values" begin
        df = DataFrame(Any[repeat(1:2, inner=4), repeat('a':'d', outer=2), collect(1:8)],
                       [:id, :variable, :value])
        udf = unstack(df)
        @test udf == unstack(df, :variable, :value) == unstack(df, :id, :variable, :value)
        @test udf == DataFrame(Any[Union{Int, Missing}[1, 2], Union{Int, Missing}[1, 5],
                                   Union{Int, Missing}[2, 6], Union{Int, Missing}[3, 7],
                                   Union{Int, Missing}[4, 8]], [:id, :a, :b, :c, :d])
        @test isa(udf[1], Vector{Int})
        @test all(isa.(columns(udf)[2:end], Vector{Union{Int, Missing}}))
        df = DataFrame(Any[categorical(repeat(1:2, inner=4)),
                           categorical(repeat('a':'d', outer=2)), categorical(1:8)],
                       [:id, :variable, :value])
        udf = unstack(df)
        @test udf == unstack(df, :variable, :value) == unstack(df, :id, :variable, :value)
        @test udf == DataFrame(Any[Union{Int, Missing}[1, 2], Union{Int, Missing}[1, 5],
                                   Union{Int, Missing}[2, 6], Union{Int, Missing}[3, 7],
                                   Union{Int, Missing}[4, 8]], [:id, :a, :b, :c, :d])
        @test isa(udf[1], CategoricalVector{Int})
        @test all(isa.(columns(udf)[2:end], CategoricalVector{Union{Int, Missing}}))
    end

    @testset "duplicate entries in unstack warnings" begin
        df = DataFrame(id=Union{Int, Missing}[1, 2, 1, 2],
                       id2=Union{Int, Missing}[1, 2, 1, 2],
                       variable=["a", "b", "a", "b"], value=[3, 4, 5, 6])
        @static if VERSION >= v"0.7.0-DEV.2988"
            @test_logs (:warn, "Duplicate entries in unstack at row 3 for key 1 and variable a.") unstack(df, :id, :variable, :value)
            @test_logs (:warn, "Duplicate entries in unstack at row 3 for key (1, 1) and variable a.") unstack(df, :variable, :value)
        else
            @test_warn "Duplicate entries in unstack at row 3 for key 1 and variable a." unstack(df, :id, :variable, :value)
            @test_warn "Duplicate entries in unstack at row 3 for key (1, 1) and variable a." unstack(df, :variable, :value)
        end
        a = unstack(df, :id, :variable, :value)
        @test a ≅ DataFrame(id = [1, 2], a = [5, missing], b = [missing, 6])
        b = unstack(df, :variable, :value)
        @test b ≅ DataFrame(id = [1, 2], id2 = [1, 2], a = [5, missing], b = [missing, 6])

        df = DataFrame(id=1:2, variable=["a", "b"], value=3:4)
        @test_nowarn unstack(df, :id, :variable, :value)
        @test_nowarn unstack(df, :variable, :value)
        a = unstack(df, :id, :variable, :value)
        b = unstack(df, :variable, :value)
        @test a ≅ b ≅ DataFrame(id = [1, 2], a = [3, missing], b = [missing, 4])

        df = DataFrame(variable=["x", "x"], value=[missing, missing], id=[1,1])
        @static if VERSION >= v"0.7.0-DEV.2988"
            @test_logs (:warn, "Duplicate entries in unstack at row 2 for key 1 and variable x.") unstack(df, :variable, :value)
            @test_logs (:warn, "Duplicate entries in unstack at row 2 for key 1 and variable x.") unstack(df)
        else
            @test_warn "Duplicate entries in unstack at row 2 for key 1 and variable x." unstack(df, :variable, :value)
            @test_warn "Duplicate entries in unstack at row 2 for key 1 and variable x." unstack(df)
        end
    end

    @testset "missing values in colkey" begin
        df = DataFrame(id=[1, 1, 1, missing, missing, missing, 2, 2, 2],
                       variable=["a", "b", missing, "a", "b", "missing", "a", "b", "missing"],
                       value=[missing, 2.0, 3.0, 4.0, 5.0, missing, 7.0, missing, 9.0])
        @static if VERSION >= v"0.7.0-DEV.2988"
            @test_logs (:warn, "Missing value in variable variable at row 3. Skipping.") unstack(df)
        else
            @test_warn "Missing value in variable variable at row 3. Skipping." unstack(df)
        end
        udf = unstack(df)
        @test names(udf) == [:id, :a, :b, :missing]
        @test udf[:missing] ≅ [missing, 9.0, missing]
        df = DataFrame(id=[1, 1, 1, missing, missing, missing, 2, 2, 2],
                       id2=[1, 1, 1, missing, missing, missing, 2, 2, 2],
                       variable=["a", "b", missing, "a", "b", "missing", "a", "b", "missing"],
                       value=[missing, 2.0, 3.0, 4.0, 5.0, missing, 7.0, missing, 9.0])
        @static if VERSION >= v"0.7.0-DEV.2988"
            @test_logs (:warn, "Missing value in variable variable at row 3. Skipping.") unstack(df, 3, 4)
        else
            @test_warn "Missing value in variable variable at row 3. Skipping." unstack(df, 3, 4)
        end
        udf = unstack(df, 3, 4)
        @test names(udf) == [:id, :id2, :a, :b, :missing]
        @test udf[:missing] ≅ [missing, 9.0, missing]
    end

    @testset "stack-unstack correctness" begin
        x = DataFrame(rand(100, 50))
        x[:id] = [1:99; missing]
        x[:id2] = string.("a", x[:id])
        x[:s] = [i % 2 == 0 ? randstring() : missing for i in 1:100]
        allowmissing!(x, :x1)
        x[1, :x1] = missing
        y = melt(x, [:id, :id2])
        z = unstack(y)
        @test all(isequal(z[n], x[n]) for n in names(z))
        z = unstack(y, :variable, :value)
        @test all(isequal(z[n], x[n]) for n in names(x))
    end

    @testset "rename" begin
        df = DataFrame(A = 1:3, B = 'A':'C')
        @test names(rename(df, :A => :A_1)) == [:A_1, :B]
        @test names(df) == [:A, :B]
        @test names(rename(df, :A => :A_1, :B => :B_1)) == [:A_1, :B_1]
        @test names(df) == [:A, :B]
        @test names(rename(df, [:A => :A_1, :B => :B_1])) == [:A_1, :B_1]
        @test names(df) == [:A, :B]
        @test names(rename(df, Dict(:A => :A_1, :B => :B_1))) == [:A_1, :B_1]
        @test names(df) == [:A, :B]
        @test names(rename(x->Symbol(lowercase(string(x))), df)) == [:a, :b]
        @test names(df) == [:A, :B]

        @test rename!(df, :A => :A_1) === df
        @test names(df) == [:A_1, :B]
        @test rename!(df, :A_1 => :A_2, :B => :B_2) === df
        @test names(df) == [:A_2, :B_2]
        @test rename!(df, [:A_2 => :A_3, :B_2 => :B_3]) === df
        @test names(df) == [:A_3, :B_3]
        @test rename!(df, Dict(:A_3 => :A_4, :B_3 => :B_4)) === df
        @test names(df) == [:A_4, :B_4]
        @test rename!(x->Symbol(lowercase(string(x))), df) === df
        @test names(df) == [:a_4, :b_4]
    end

    @testset "size" begin
        df = DataFrame(A = 1:3, B = 'A':'C')
        @test_throws ArgumentError size(df, 3)
        @test length(df) == 2
        @test ndims(df) == 2
    end

    @testset "description" begin
        df = DataFrame(A = 1:10)
        @test head(df) == DataFrame(A = 1:6)
        @test head(df, 1) == DataFrame(A = 1)
        @test tail(df) == DataFrame(A = 5:10)
        @test tail(df, 1) == DataFrame(A = 10)
    end

    @testset "misc" begin
        df = DataFrame(Any[collect('A':'C')])
        @test sprint(dump, df) == """
                                  $DataFrame  3 observations of 1 variables
                                    x1: Array{Char}((3,))
                                      1: Char A
                                      2: Char B
                                      3: Char C
                                  """
        df = DataFrame(A = 1:12, B = repeat('A':'C', inner=4))
        # @test DataFrames.without(df, 1) == DataFrame(B = repeat('A':'C', inner=4))
    end

    @testset "column conversions" begin
        df = DataFrame(Any[collect(1:10), collect(1:10)])
        @test !isa(df[1], Vector{Union{Int, Missing}})
        allowmissing!(df, 1)
        @test isa(df[1], Vector{Union{Int, Missing}})
        @test !isa(df[2], Vector{Union{Int, Missing}})
        df[1,1] = missing
        @test_throws MethodError disallowmissing!(df, 1)
        df[1,1] = 1
        disallowmissing!(df, 1)
        @test isa(df[1], Vector{Int})

        df = DataFrame(Any[collect(1:10), collect(1:10)])
        allowmissing!(df, [1,2])
        @test isa(df[1], Vector{Union{Int, Missing}}) && isa(df[2], Vector{Union{Int, Missing}})
        disallowmissing!(df, [1,2])
        @test isa(df[1], Vector{Int}) && isa(df[2], Vector{Int})

        df = DataFrame(Any[collect(1:10), collect(1:10)])
        allowmissing!(df)
        @test isa(df[1], Vector{Union{Int, Missing}}) && isa(df[2], Vector{Union{Int, Missing}})
        disallowmissing!(df)
        @test isa(df[1], Vector{Int}) && isa(df[2], Vector{Int})

        df = DataFrame(Any[CategoricalArray(1:10),
                           CategoricalArray(string.('a':'j'))])
        allowmissing!(df)
        @test all(issubtype.(typeof.(columns(df)), CategoricalVector))
        @test eltypes(df)[1] <: Union{CategoricalValue{Int}, Missing}
        @test eltypes(df)[2] <: Union{CategoricalString, Missing}
        df[1,2] = missing
        @test_throws MissingException disallowmissing!(df)
        df[1,2] = "a"
        disallowmissing!(df)
        @test all(issubtype.(typeof.(columns(df)), CategoricalVector))
        @test eltypes(df)[1] <: CategoricalValue{Int}
        @test eltypes(df)[2] <: CategoricalString
    end

    @testset "similar" begin
        df = DataFrame(a = ["foo"],
                       b = CategoricalArray(["foo"]),
                       c = [0.0],
                       d = CategoricalArray([0.0]))
        @test typeof.(columns(similar(df))) == typeof.(columns(df))
        @test size(similar(df)) == size(df)

        rows = size(df, 1) + 5
        @test size(similar(df, rows)) == (rows, size(df, 2))
        @test typeof.(columns(similar(df, rows))) == typeof.(columns(df))

        e = @test_throws ArgumentError similar(df, -1)
        @test e.value.msg == "the number of rows must be positive"
    end

    @testset "setindex! special cases" begin
        df = DataFrame(rand(3,2), [:x3, :x3_1])
        @test_throws ArgumentError df[3] = [1, 2]
        @test_throws ArgumentError df[4] = [1, 2, 3]
        df[3] = [1,2,3]
        df[4] = [1,2,3]
        @test names(df) == [:x3, :x3_1, :x3_2, :x4]
    end

    @testset "passing range to a DataFrame" begin
        df = DataFrame(a=1:3, b='a':'c')
        df[:c] = 1:3
        df[:d] = 'a':'c'
        @test all(typeof(df[i]) <: Vector for i in 1:ncol(df))
    end

    @testset "handling of end in indexing" begin
        z = DataFrame(rand(4,5))
        for x in [z, view(z, 1:4)]
            y = deepcopy(x)
            @test x[end] == x[5]
            @test x[end:end] == x[5:5]
            @test x[end, :] == x[4, :]
            @test x[end, end] == x[4,5]
            @test x[2:end, 2:end] == x[2:4,2:5]
            x[end] = 1:4
            y[5] = 1:4
            @test x == y
            x[4:end] = DataFrame([11:14, 21:24])
            y[4] = [11:14;]
            y[5] = [21:24;]
            @test x == y
            x[end, :] = 111
            y[4, :] = 111
            @test x == y
            x[end,end] = 1000
            y[4,5] = 1000
            @test x == y
            x[2:end, 2:end] = 0
            y[2:4, 2:5] = 0
            @test x == y
        end
    end

    @testset "permutecols!" begin
        a, b, c = 1:5, 2:6, 3:7
        original = DataFrame(a=a, b=b, c=c)

        df = deepcopy(original)
        expected = deepcopy(original)
        permutecols!(df, [:a, :b, :c])
        @test df == expected
        permutecols!(df, 1:3)
        @test df == expected

        df = deepcopy(original)
        expected = DataFrame(b=b, c=c, a=a)
        permutecols!(df, [:b, :c, :a])
        @test df == expected
        df = deepcopy(original)
        permutecols!(df, [2, 3, 1])
        @test df == expected

        df = deepcopy(original)
        expected = DataFrame(c=c, a=a, b=b)
        permutecols!(df, [:c, :a, :b])
        @test df == expected
        df = deepcopy(original)
        permutecols!(df, [3, 1, 2])
        @test df == expected

        df = deepcopy(original)
        expected = DataFrame(a=a, c=c, b=b)
        permutecols!(df, [:a, :c, :b])
        @test df == expected
        df = deepcopy(original)
        permutecols!(df, [1, 3, 2])
        @test df == expected

        df = deepcopy(original)
        expected = DataFrame(b=b, a=a, c=c)
        permutecols!(df, [:b, :a, :c])
        @test df == expected
        df = deepcopy(original)
        permutecols!(df, [2, 1, 3])
        @test df == expected

        df = deepcopy(original)
        expected = DataFrame(c=c, b=b, a=a)
        permutecols!(df, [:c, :b, :a])
        @test df == expected
        df = deepcopy(original)
        permutecols!(df, [3, 2, 1])
        @test df == expected

        # Invalid
        df = DataFrame(a=a, b=b, c=c)
        @test_throws ArgumentError permutecols!(df, [:a, :b])
        @test_throws ArgumentError permutecols!(df, 1:4)
        @test_throws KeyError permutecols!(df, [:a, :b, :c, :d])
        @test_throws ArgumentError permutecols!(df, [1, 3])
        @test_throws ArgumentError permutecols!(df, [:a, :c])
        @test_throws ArgumentError permutecols!(df, [1, 2, 3, 1])
        @test_throws ArgumentError permutecols!(df, [:a, :b, :c, :a])
    end

    if VERSION >= v"0.7.0-DEV.3067"
        @testset "getproperty, setproperty! and propertynames" begin
            x = collect(1:10)
            y = collect(1.0:10.0)
            z = collect(10:-1:1)
            df = DataFrame(x = x, y = y)

            @test Base.propertynames(df) == names(df)

            @test df.x === x
            @test df.y === y
            @test_throws KeyError df.z

            df.x = 2:11
            @test df.x == 2:11
            @test x == 1:10
            df.y = 1
            @test df.y == [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
            @test df.y === y
            df.z = z
            @test df.z === z
            df.zz = 1
            @test df.zz == df.y
        end
    end
end
