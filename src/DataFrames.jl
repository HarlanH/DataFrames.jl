__precompile__(true)
module DataFrames

##############################################################################
##
## Dependencies
##
##############################################################################

using Reexport, StatsBase, SortingAlgorithms, Compat
@reexport using CategoricalArrays, Missings
using Base.Sort
using Base.Order
using Compat.Unicode
using Compat.Printf

if VERSION >= v"0.7.0-DEV.2738"
    using Unicode: normalize

    const kwpairs = pairs
else
    kwpairs(x::AbstractArray) = (first(v) => last(v) for v in x)
    macro isdefined(sym)
        sym = Expr(:quote, sym)
        esc(:(isdefined($sym)))
    end
    using Compat.IOBuffer
    const normalize = normalize_string  # requires that we don't use LinearAlgebra normalize
end

##############################################################################
##
## Exported methods and types (in addition to everything reexported above)
##
##############################################################################

export AbstractDataFrame,
       DataFrame,
       DataFrameRow,
       GroupApplied,
       GroupedDataFrame,
       SubDataFrame,

       allowmissing!,
       aggregate,
       by,
       categorical!,
       colwise,
       combine,
       completecases,
       deleterows!,
       describe,
       dropmissing,
       dropmissing!,
       eachcol,
       eachrow,
       eltypes,
       groupby,
       head,
       melt,
       meltdf,
       names!,
       ncol,
       nonunique,
       nrow,
       order,
       rename!,
       rename,
       showcols,
       stack,
       stackdf,
       unique!,
       unstack,
       head,
       tail,

       # Remove after deprecation period
       pool,
       pool!


##############################################################################
##
## Load files
##
##############################################################################

include("other/utils.jl")
include("other/index.jl")

include("abstractdataframe/abstractdataframe.jl")
include("dataframe/dataframe.jl")
include("subdataframe/subdataframe.jl")
include("groupeddataframe/grouping.jl")
include("dataframerow/dataframerow.jl")
include("dataframerow/utils.jl")

include("abstractdataframe/iteration.jl")
include("abstractdataframe/join.jl")
include("abstractdataframe/reshape.jl")

include("abstractdataframe/io.jl")

include("abstractdataframe/show.jl")
include("groupeddataframe/show.jl")
include("dataframerow/show.jl")

include("abstractdataframe/sort.jl")
include("dataframe/sort.jl")

# include("deprecated.jl")

end # module DataFrames
