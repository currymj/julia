# This file is a part of Julia. License is MIT: https://julialang.org/license

# DO NOT ALTER ORDER OR SPACING OF METHODS BELOW
const lineoffset = @__LINE__
ambig(x, y) = 1
ambig(x::Integer, y) = 2
ambig(x, y::Integer) = 3
ambig(x::Int, y::Int) = 4
ambig(x::Number, y) = 5
# END OF LINE NUMBER SENSITIVITY

# For curmod_*
include("testenv.jl")

ambigs = Any[[], [3], [2,5], [], [3]]

mt = methods(ambig)

getline(m::Method) = m.line - lineoffset

for m in mt
    ln = getline(m)
    atarget = ambigs[ln]
    if isempty(atarget)
        @test m.ambig === nothing
    else
        aln = Int[getline(a) for a in m.ambig]
        @test sort(aln) == atarget
    end
end

@test length(methods(ambig)) == 5
@test length(Base.methods_including_ambiguous(ambig, Tuple)) == 5

@test length(methods(ambig, (Int, Int))) == 1
@test length(methods(ambig, (UInt8, Int))) == 0
@test length(Base.methods_including_ambiguous(ambig, (UInt8, Int))) == 2

@test ambig("hi", "there") == 1
@test ambig(3.1, 3.2) == 5
@test ambig(3, 4) == 4
@test_throws MethodError ambig(0x03, 4)
@test_throws MethodError ambig(0x03, 4)  # test that not inserted into cache

# Ensure it still works with potential inlining
callambig(x, y) = ambig(x, y)
@test_throws MethodError callambig(0x03, 4)

# Printing ambiguity errors
let err = try
              ambig(0x03, 4)
          catch _e_
              _e_
          end
    io = IOBuffer()
    Base.showerror(io, err)
    lines = split(String(take!(io)), '\n')
    ambig_checkline(str) = startswith(str, "  ambig(x, y::Integer) in $curmod_str at") ||
                           startswith(str, "  ambig(x::Integer, y) in $curmod_str at")
    @test ambig_checkline(lines[2])
    @test ambig_checkline(lines[3])
    @test lines[4] == "Possible fix, define"
    @test lines[5] == "  ambig(::Integer, ::Integer)"
end

## Other ways of accessing functions
# Test that non-ambiguous cases work
let io = IOBuffer()
    @test precompile(ambig, (Int, Int)) == true
    cf = cfunction(ambig, Int, Tuple{Int, Int})
    @test ccall(cf, Int, (Int, Int), 1, 2) == 4
    @test length(code_lowered(ambig, (Int, Int))) == 1
    @test length(code_typed(ambig, (Int, Int))) == 1
    code_llvm(io, ambig, (Int, Int))
    code_native(io, ambig, (Int, Int))
end

# Test that ambiguous cases fail appropriately
let io = IOBuffer()
    @test precompile(ambig, (UInt8, Int)) == false
    cf = cfunction(ambig, Int, Tuple{UInt8, Int})  # test for a crash (doesn't throw an error)
    @test_throws MethodError ccall(cf, Int, (UInt8, Int), 1, 2)
    @test_throws(ErrorException("no unique matching method found for the specified argument types"),
                 which(ambig, (UInt8, Int)))
    @test_throws(ErrorException("no unique matching method found for the specified argument types"),
                 code_llvm(io, ambig, (UInt8, Int)))
    @test_throws(ErrorException("no unique matching method found for the specified argument types"),
                 code_native(io, ambig, (UInt8, Int)))
end

# Method overwriting doesn't destroy ambiguities
@test_throws MethodError ambig(2, 0x03)
ambig(x, y::Integer) = 3
@test_throws MethodError ambig(2, 0x03)

# Method overwriting by an ambiguity should also invalidate the method cache (#21963)
ambig(x::Union{Char, Int8}) = 'r'
@test ambig('c') == 'r'
@test ambig(Int8(1)) == 'r'
@test_throws MethodError ambig(Int16(1))
ambig(x::Union{Char, Int16}) = 's'
@test_throws MethodError ambig('c')
@test ambig(Int8(1)) == 'r'
@test ambig(Int16(1)) == 's'

# Automatic detection of ambiguities
module Ambig1
ambig(x, y) = 1
ambig(x::Integer, y) = 2
ambig(x, y::Integer) = 3
end

ambs = detect_ambiguities(Ambig1)
@test length(ambs) == 1

module Ambig2
ambig(x, y) = 1
ambig(x::Integer, y) = 2
ambig(x, y::Integer) = 3
ambig(x::Number, y) = 4
end

ambs = detect_ambiguities(Ambig2)
@test length(ambs) == 2

module Ambig3
ambig(x, y) = 1
ambig(x::Integer, y) = 2
ambig(x, y::Integer) = 3
ambig(x::Int, y::Int) = 4
end

ambs = detect_ambiguities(Ambig3)
@test length(ambs) == 1

module Ambig4
ambig(x, y) = 1
ambig(x::Int, y) = 2
ambig(x, y::Int) = 3
ambig(x::Int, y::Int) = 4
end
ambs = detect_ambiguities(Ambig4)
@test length(ambs) == 0

module Ambig5
ambig(x::Int8, y) = 1
ambig(x::Integer, y) = 2
ambig(x, y::Int) = 3
end

ambs = detect_ambiguities(Ambig5)
@test length(ambs) == 2

# Test that Core and Base are free of ambiguities
# not using isempty so this prints more information when it fails
@test detect_ambiguities(Core, Base; imported=true, recursive=true, ambiguous_bottom=false) == []
# some ambiguities involving Union{} type parameters are expected, but not required
@test !isempty(detect_ambiguities(Core, Base; imported=true, ambiguous_bottom=true))

amb_1(::Int8, ::Int) = 1
amb_1(::Integer, x) = 2
amb_1(x, ::Int) = 3
# if there is an ambiguity with some methods and not others, `methods`
# should return just the non-ambiguous ones, i.e. the ones that could actually
# be called.
@test length(methods(amb_1, Tuple{Integer, Int})) == 1

amb_2(::Int, y) = 1
amb_2(x, ::Int) = 2
amb_2(::Int8, y) = 3
@test length(methods(amb_2)) == 3  # make sure no duplicates

amb_3(::Int8, ::Int8) = 1
amb_3(::Int16, ::Int16) = 2
amb_3(::Integer, ::Integer) = 3
amb_3(::Integer, x) = 4
amb_3(x, ::Integer) = 5
# ambiguous definitions exist, but are covered by multiple more specific definitions
let ms = methods(amb_3).ms
    @test !Base.isambiguous(ms[4], ms[5])
end

amb_4(::Int8, ::Int8) = 1
amb_4(::Int16, ::Int16) = 2
amb_4(::Integer, x) = 4
amb_4(x, ::Integer) = 5
# as above, but without sufficient definition coverage
let ms = methods(amb_4).ms
    @test Base.isambiguous(ms[3], ms[4])
end

g16493(x::T, y::Integer) where {T<:Number} = 0
g16493(x::Complex{T}, y) where {T} = 1
let ms = methods(g16493, (Complex, Any))
    @test length(ms) == 1
    @test first(ms).sig == (Tuple{typeof(g16493), Complex{T}, Any} where T)
end

# issue #17350
module Ambig6
struct ScaleMinMax{To,From} end
map1(mapi::ScaleMinMax{To,From}, val::From) where {To<:Union{Float32,Float64},From<:Real} = 1
map1(mapi::ScaleMinMax{To,From}, val::Union{Real,Complex}) where {To<:Union{Float32,Float64},From<:Real} = 2
end

@test isempty(detect_ambiguities(Ambig6))

module Ambig7
struct T end
(::T)(x::Int8, y) = 1
(::T)(x, y::Int8) = 2
end
@test length(detect_ambiguities(Ambig7)) == 1

module Ambig17648
struct MyArray{T,N} <: AbstractArray{T,N}
    data::Array{T,N}
end

foo(::Type{Array{T,N}}, A::MyArray{T,N}) where {T,N} = A.data
foo(::Type{Array{T,N}}, A::MyArray{T,N}) where {T<:AbstractFloat,N} = A.data
foo(::Type{Array{S,N}}, A::MyArray{T,N}) where {S<:AbstractFloat,N,T<:AbstractFloat} =
    copy!(Array{S}(uninitialized, unsize(A)), A.data)
foo(::Type{Array{S,N}}, A::AbstractArray{T,N}) where {S<:AbstractFloat,N,T<:AbstractFloat} =
    copy!(Array{S}(uninitialized, size(A)), A)
end

@test isempty(detect_ambiguities(Ambig17648))

module Ambig8
using Base: DimsInteger, Indices
g18307(::Union{Indices,Dims}, I::AbstractVector{T}...) where {T<:Integer} = 1
g18307(::DimsInteger) = 2
g18307(::DimsInteger, I::Integer...) = 3
end
try
    # want this to be a test_throws MethodError, but currently it's not (see #18307)
    Ambig8.g18307((1,))
catch err
    if isa(err, MethodError)
        error("Test correctly returned a MethodError, please change to @test_throws MethodError")
    else
        rethrow(err)
    end
end

module Ambig9
f(x::Complex{<:Integer}) = 1
f(x::Complex{<:Rational}) = 2
end
@test !Base.isambiguous(methods(Ambig9.f)..., ambiguous_bottom=false)
@test Base.isambiguous(methods(Ambig9.f)..., ambiguous_bottom=true)
@test !Base.isambiguous(methods(Ambig9.f)...)
@test length(detect_ambiguities(Ambig9, ambiguous_bottom=false)) == 0
@test length(detect_ambiguities(Ambig9, ambiguous_bottom=true)) == 1
@test length(detect_ambiguities(Ambig9)) == 0

# Test that Core and Base are free of UndefVarErrors
# not using isempty so this prints more information when it fails
@testset "detect_unbound_args in Base and Core" begin
    # TODO: review this list and remove everything between test_broken and test
    let need_to_handle_undef_sparam =
            Set{Method}(detect_unbound_args(Core; recursive=true))
        pop!(need_to_handle_undef_sparam, which(Core.Inference.eltype, Tuple{Type{Tuple{Vararg{E}}} where E}))
        pop!(need_to_handle_undef_sparam, which(Core.Inference.eltype, Tuple{Type{Tuple{Any}}}))
        @test_broken need_to_handle_undef_sparam == Set()
        pop!(need_to_handle_undef_sparam, which(Core.Inference.cat, Tuple{Any, AbstractArray}))
        @test need_to_handle_undef_sparam == Set()
    end
    let need_to_handle_undef_sparam =
            Set{Method}(detect_unbound_args(Base; recursive=true))
        pop!(need_to_handle_undef_sparam, which(Base._totuple, (Type{Tuple{Vararg{E}}} where E, Any, Any)))
        pop!(need_to_handle_undef_sparam, which(Base.eltype, Tuple{Type{Tuple{Vararg{E}}} where E}))
        pop!(need_to_handle_undef_sparam, which(Base.eltype, Tuple{Type{Tuple{Any}}}))
        pop!(need_to_handle_undef_sparam, first(methods(Base.same_names)))
        @test_broken need_to_handle_undef_sparam == Set()
        pop!(need_to_handle_undef_sparam, which(Base.cat, Tuple{Any, AbstractArray}))
        pop!(need_to_handle_undef_sparam, which(Base.byteenv, (Union{AbstractArray{Pair{T}, 1}, Tuple{Vararg{Pair{T}}}} where T<:AbstractString,)))
        pop!(need_to_handle_undef_sparam, which(Base.LinAlg.promote_leaf_eltypes, (Union{AbstractArray{T}, Tuple{Vararg{T}}} where T<:Number,)))
        pop!(need_to_handle_undef_sparam, which(Base.LinAlg.promote_leaf_eltypes,
                                                (Union{AbstractArray{T}, Tuple{Vararg{T}}} where T<:(AbstractArray{<:Number}),)))
        pop!(need_to_handle_undef_sparam, which(Base.SparseArrays._absspvec_vcat, (AbstractSparseArray{Tv, Ti, 1} where {Tv, Ti},)))
        pop!(need_to_handle_undef_sparam, which(Base.SparseArrays._absspvec_hcat, (AbstractSparseArray{Tv, Ti, 1} where {Tv, Ti},)))
        pop!(need_to_handle_undef_sparam, which(Base.cat, (Any, Base.SparseArrays._TypedDenseConcatGroup{T} where T)))
        @test need_to_handle_undef_sparam == Set()
    end
end

nothing # don't return a module from the remote include
