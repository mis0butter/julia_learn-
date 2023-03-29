

## ============================================ ##
# solve sparse regression 

export sparsify_dynamics 

function sparsify_dynamics( Θ, dx, λ, n_vars ) 
# ----------------------- #
# Purpose: Solve for active terms in dynamics through sparse regression 
# 
# Inputs: 
#   Theta  = data matrix 
#   dx     = state derivatives 
#   lambda = sparsification knob (threshold) 
#   n_vars = # elements in state 
# 
# Outputs: 
#   XI     = sparse coefficients of dynamics 
# ----------------------- #

    # first perform least squares 
    Ξ = Θ \ dx ; 

    # sequentially thresholded least squares = LASSO. Do 10 iterations 
    for i = 1 : 10 

        # for each element in state 
        for j = 1 : n_vars 

            # small_inds = rows of XI < threshold 
            small_inds = findall( <(λ), abs.(Ξ[:,j]) ) ; 

            # set elements < lambda to 0 
            Ξ[small_inds, j] .= 0 ; 

            # big_inds --> select columns of \Theta 
            # big_inds = ~small_inds ; 

        end 

    end 
        
    return Ξ

end 

## ============================================ ##
# build data matrix 

export pool_data 

function pool_data(x, n_vars, poly_order) 
# ----------------------- #
# Purpose: Build data matrix based on possible functions 
# 
# Inputs: 
#   x           = data input 
#   n_vars      = # elements in state 
#   poly_order  = polynomial order (goes up to order 3) 
# 
# Outputs: 
#   THETA       = data matrix passed through function library 
# ----------------------- #

    # turn x into matrix and get length 
    xmat = mapreduce(permutedims, vcat, x) ; 
    m    = length(x) ; 

    # fil out 1st column of THETA with ones (poly order = 0) 
    ind = 1 ; 
    THETA = ones(m, ind) ; 

    # poly order 1 
    for i = 1 : n_vars 
        ind  += 1 ; 
        THETA = [THETA xmat[:,i]]
    end 

    # poly order 2 
    if poly_order >= 2 
        for i = 1 : n_vars 
            for j = i:n_vars 

                ind  += 1 ; 
                vec   = xmat[:,i] .* xmat[:,j] ; 
                THETA = [THETA vec] ; 

            end 
        end 
    end 

    # poly order 3 
    if poly_order >= 3 
        for i = 1 : n_vars 
            for j = i : n_vars 
                for k = j : n_vars 
                    
                    ind  += 1 ;                     
                    vec   = xmat[:,i] .* xmat[:,j] .* xmat[:,k] ; 
                    THETA = [THETA vec] ; 

                end 
            end 
        end 
    end 

    # sine functions 
    for i = 1 : n_vars 
        ind  += 1 ; 
        vec   = sin.(xmat[:,i]) ; 
        THETA = [THETA vec] ; 
    end 
    
    return THETA 

end 


    