function simplified_matvec(Ξ::AbstractArray{T, 2}, basis) where T <: Real
    eqs = Operation[]
    for i=1:size(Ξ, 2)
        eq = nothing
        for j = 1:size(Ξ, 1)
            if !iszero(Ξ[j,i])
                if eq === nothing
                    eq = basis[j]*Ξ[j,i]
                else
                    eq += basis[j]*Ξ[j,i]
                end
            end
        end
        if eq != nothing
            push!(eqs, eq)
        end
    end
    eqs
end

function simplified_matvec(Ξ::AbstractArray{T,1}, basis) where T <: Real
    eq = nothing
    @inbounds for i in 1:size(Ξ, 1)
        if !iszero(Ξ[i])
            if eq === nothing
                eq = basis[i]*Ξ[i]
            else
                eq += basis[i]*Ξ[i]
            end
        end

    end
    eq
end

function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 1}, Ψ::Basis; kwargs...) where S <: Number
    return SInDy(X, Ẋ', Ψ; kwargs...)
end

# Returns a basis for the differential state
function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 2}, Ψ::Basis; p::AbstractArray = [], maxiter::Int64 = 10, opt::T = Optimise.STRRidge()) where {T <: Optimise.AbstractOptimiser, S <: Number}
    @assert size(X)[end] == size(Ẋ)[end]
    nx, nm = size(X)
    ny, nm = size(Ẋ)

    Ξ = zeros(eltype(X), length(Ψ), ny)
    θ = Ψ(X, p = p)

    # Initial estimate
    Optimise.init!(Ξ, opt, θ', Ẋ')
    Optimise.fit!(Ξ, θ', Ẋ', opt, maxiter = maxiter)
    return Basis(simplified_matvec(Ξ, Ψ.basis), variables(Ψ), parameters = p)
end


function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 1}, Ψ::Basis, thresholds::AbstractArray; kwargs...) where S <: Number
    return SInDy(X, Ẋ', Ψ, thresholds; kwargs...)
end

# Returns an array of basis for all values of lambda
function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 2}, Ψ::Basis, thresholds::AbstractArray ; p::AbstractArray = [], maxiter::Int64 = 10, opt::T = Optimise.STRRidge()) where {T <: Optimise.AbstractOptimiser, S <: Number}
    @assert size(X)[end] == size(Ẋ)[end]
    nx, nm = size(X)
    ny, nm = size(Ẋ)

    θ = Ψ(X, p = p)

    ξ = zeros(eltype(X), length(Ψ), ny)
    Ξ_opt = zeros(eltype(X), length(Ψ), ny)
    Ξ = zeros(eltype(X), length(thresholds), ny, length(Ψ))
    x = zeros(eltype(X), length(thresholds), ny, 2)
    pareto = zeros(eltype(X),  ny, length(thresholds))

    @inbounds for (j, threshold) in enumerate(thresholds)
        set_threshold!(opt, threshold)
        Optimise.init!(ξ, opt, θ', Ẋ')
        Optimise.fit!(ξ, θ', Ẋ', opt, maxiter = maxiter)
        Ξ[j, :, :] = ξ[:, :]'
        [x[j, i, :] = [norm(xi, 0)/length(Ψ); norm(view(Ẋ , i, :) - θ'*xi, 2)] for (i, xi) in enumerate(eachcol(ξ))]
    end

    # Create the evaluation
    @inbounds for i in 1:ny
        x[:, i, 2] .= x[:, i, 2]./maximum(x[:, i, 2])
        pareto[i, :] = [norm(x[j, i, :], 2) for j in 1:length(thresholds)]
        _, indx = findmin(pareto[i, :])
        Ξ_opt[:, i] = Ξ[indx, i, :]
    end

    return Basis(simplified_matvec(Ξ_opt, Ψ.basis), variables(Ψ), parameters = p)
end
